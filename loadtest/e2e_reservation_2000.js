import http from 'k6/http';
import { sleep, check } from 'k6';
import { Counter, Trend } from 'k6/metrics';


const K6_WEB_DASHBOARD = true
// 엔드투엔드(로그인→대기열→좌석선택→예매) + Redis 부하테스트.
//
// 결제(POST /payments/confirm)는 제외함 — PaymentServiceImpl.confirm()이 실제 토스페이먼츠 API를
// 호출해서 검증하기 때문에 가짜 paymentKey로는 테스트가 불가능함. 대신 POST /reservations를 씀 —
// 결제 없이 바로 예매하는 엔드포인트지만, ReservationServiceImpl.reserve() 안에서 결제 흐름과
// 완전히 동일한 Redis 분산락(lock:reservation:{seatId})을 타므로 락 검증 목적으로는 충분함.
//
// 사전 조건:
//   - loadtest0001~loadtest2000 계정이 release DB에 시드되어 있어야 함 (seed_test_accounts.sql)
//   - ROUND_ID는 사전에 AVAILABLE 좌석이 넉넉한 회차로 직접 조회해서 정함 (round_id=18: 2000석 확인됨)
const BASE = 'https://app.jun979.click/api';
const ROUND_ID = Number(__ENV.ROUND_ID) || 62; //11번 레미제라블 21일

// 0~RAMP_SECONDS초 사이 무작위로 대기해서 커넥션 개설을 몇 초에 걸쳐 분산시킨다.
const RAMP_SECONDS = Number(__ENV.RAMP_SECONDS) || 10;

const reservationSuccess = new Counter('reservation_success');
const reservationGiveUp = new Counter('reservation_give_up'); // 매진/대기열 만료로 포기
const reservationBug = new Counter('reservation_unexpected_fail'); // 200이 아닌 응답 = 진짜 버그
const transientFail = new Counter('transient_http_fail'); // 폴링/좌석조회 중 일시적 비-200 응답(배포 등) — 버그 아님, 그 VU만 조기 종료
const queueWaitSeconds = new Trend('queue_wait_seconds');

export const options = {
  scenarios: {
    e2e_reservation: {
      executor: 'per-vu-iterations',
      vus: 4000,
      iterations: 1,
      maxDuration: '40m', // 좌석 2000석에 인원 2000명 — 경합은 있지만 전원 매진 실패가 정상은 아님
    },
  },
  // macOS용 무거운 경로를 회피.
  insecureSkipTLSVerify: true,
  thresholds: {
    // 2026-08-21: count==0으로 엄격하게 잡아뒀다가, KEDA 스케일업 순간(신규 파드 부팅 중 ALB가
    // TargetConnectionError를 잠깐 겪는 것 — Target_5XX는 0이었음, 즉 앱이 직접 준 500은 아니었음)
    // 몇 건이 여기 같이 잡혀서 threshold가 깨짐. 2000명 중 20건(1%)까지는 이런 정상적인 스케일업
    // blip으로 보고 허용, 그 이상이면 진짜 락/서버 버그로 의심.
    reservation_unexpected_fail: ['count<20'],
  },
};

// 2026-08-24: 실제 브라우저는 QueueModal.tsx/seats page의 beforeunload로 "포기"를 서버에 알려서
// active 슬롯을 즉시 반납하는데, k6 VU는 탭을 안 닫으므로 이 반납이 전혀 안 일어남 — 그 결과
// 이 테스트에서 queue_wait_seconds가 실제보다 훨씬 나쁘게(ACTIVE_TTL=10분 그대로) 측정됐었음.
// 좌석을 못 구하고 포기하는 시점에 이 호출로 그 반납을 흉내 내서, 프론트/백엔드에 넣은 슬롯
// 즉시반납 로직(seats page/payments fail page)의 효과가 이 테스트에도 그대로 반영되게 함.
function leaveQueue(token, headers) {
  http.post(`${BASE}/queues/${token}/leave`, null, { headers });
}

export default function () {
  const userId = `loadtest${String(__VU).padStart(4, '0')}`;
  const headers = { 'Content-Type': 'application/json' };

  // VU마다 시작 시점을 0~RAMP_SECONDS초 사이로 흩어서 커넥션 개설이 진짜 한순간에 안 몰리게 함
  // (위 RAMP_SECONDS 주석 참고 — ALB TLS negotiation 실패 방지).
  sleep(Math.random() * RAMP_SECONDS);

  // 1. 로그인 (bcrypt 검증 → Redis 세션 생성)
  const loginRes = http.post(
    `${BASE}/auth/login`,
    JSON.stringify({ userId, pwd: 'test1234' }),
    { headers }
  );
  if (!check(loginRes, { '로그인 성공': (r) => r.status === 200 })) {
    return;
  }

  // 2. 실제 사용자 탐색 흐름 (목록/상세 조회)
  http.get(`${BASE}/events/paged`);
  http.get(`${BASE}/categories`);
  sleep(1 + Math.random());

  // 3. 대기열 진입 (Redis: scheduleId+userId 기준 토큰 발급)
  const joinRes = http.post(
    `${BASE}/queues`,
    JSON.stringify({ scheduleId: ROUND_ID }),
    { headers }
  );
  if (!check(joinRes, { '대기열 진입 성공': (r) => r.status === 200 })) {
    reservationBug.add(1);
    return;
  }
  // GlobalResponseAdvice: record/DTO/List를 리턴하는 컨트롤러(QueueJoinResponse 등)는
  // { success, message, data, timestamp }로 감싸지고 실제 값은 data 밑에 있음 —
  // Map을 직접 리턴하는 /reservations 계열과 다름(거긴 안 감싸짐). 이 구분을 안 하고
  // 최상위에서 바로 필드를 읽어서 계속 undefined였던 게 지금까지 모든 실행의 진짜 원인이었음.
  const queueToken = JSON.parse(joinRes.body).data.queueToken;

  // 4. 대기열 상태 폴링 — ENTERED(활성) 될 때까지
  // 2026-08-24: 최대 300회(10분)로 잡혀있던 걸 90회(3분)로 줄임 — MAX_ACTIVE_USERS를 400으로
  // 올리고 예매실패/이탈 시 슬롯 즉시반납(leaveQueue)까지 넣은 뒤로는 회전율이 훨씬 빨라져서,
  // 이 안에 못 들어가면 사실상 이 테스트 시간 내엔 못 들어간다고 봐도 되는 수준. 진짜 유저가
  // 대기열에서 버티는 현실적인 인내심 상한과도 더 가까움. queue_wait_seconds의 "최악의 경우"
  // 상한이 3분으로 줄어드니 전체 테스트 체감 시간도 그만큼 짧아짐.
  const MAX_WAITING_POLLS = 90;
  const waitStart = Date.now();
  let entered = false;
  let pollBroke = false;
  for (let i = 0; i < MAX_WAITING_POLLS; i++) {
    const statusRes = http.get(`${BASE}/queues/${queueToken}`);
    if (statusRes.status !== 200) {
      // 배포 중 ALB가 순간적으로 HTML 에러페이지를 돌려주는 경우 등 — JSON 파싱 시도하지 않고
      // 이 VU만 조기 종료 (전체 테스트를 죽이지 않기 위해 여기서 return)
      transientFail.add(1);
      pollBroke = true;
      break;
    }
    const status = JSON.parse(statusRes.body).data.status;
    if (status === 'ENTERED') {
      entered = true;
      break;
    }
    if (status === 'EXPIRED') {
      break;
    }
    sleep(2);
  }
  queueWaitSeconds.add((Date.now() - waitStart) / 1000);

  if (pollBroke) {
    leaveQueue(queueToken, headers); // 폴링 중 일시 오류로 조기 종료 — 마찬가지로 유령으로 안 남게 반납
    return;
  }

  if (!entered) {
    reservationGiveUp.add(1); // 대기열 만료 = 실사용자라면 포기했을 상황
    // 2026-08-24: 이 경로(WAITING 폴링 상한 초과로 포기)에서 leaveQueue를 안 불러서, k6 VU가
    // 다 끝난 뒤에도 서버 waiting 목록엔 "유령"으로 계속 남아있던 버그 발견 — 실제 브라우저는
    // beforeunload가 WAITING/ENTERED 상관없이 항상 반납해주는데, k6는 탭을 안 닫으니 이 경로만
    // 누락돼있었음(실측: 2000/2000 완료된 테스트인데 waiting에 898명 유령이 남아있었음, round 62).
    leaveQueue(queueToken, headers);
    return;
  }

  // 5. 좌석 선택 + 예매 (실패하면 다른 좌석으로 재시도 — 실제 유저 행동 재현)
  let reserved = false;
  for (let attempt = 0; attempt < 20; attempt++) {
    // 2026-08-24: 2026-08-21에 SeatController가 queueToken 필수 검증(QueueService.canEnter)으로
    // 바뀐 걸 이 스크립트가 못 따라가고 있었음 — queueToken 없이 조회해서 전부 403 FORBIDDEN
    // "대기열을 통해 입장해주세요"로 실패, 테스트가 64초 만에 끝나며 reservation_unexpected_fail
    // threshold까지 깨졌던 진짜 원인. frontend(lib/api/seats.ts)의 getSeats(roundId, queueToken)
    // 시그니처와 맞춰서 쿼리파라미터 추가.
    const seatsRes = http.get(`${BASE}/schedules/${ROUND_ID}/seats?queueToken=${queueToken}`);
    if (seatsRes.status !== 200) {
      transientFail.add(1);
      // 2026-08-24: 여기도 ENTERED 이후 조기 종료라 active 슬롯을 붙잡고 있었음 — 세 번째로
      // 발견된 같은 종류의 누락(위 leaveQueue 주석들 참고). 이 경로로 빠지는 VU가 원인이 돼서
      // 테스트가 100% 완료된 뒤에도 active 슬롯이 (MAX_ACTIVE_USERS만큼) 안 비고 남아있었음
      // (실측: round 62, 테스트 종료 후 active 400/400 그대로 남음, 토큰 만료 전이라 orphan도 아님).
      leaveQueue(queueToken, headers);
      return; // give_up과 섞이지 않게 여기서 바로 종료
    }
    const seats = JSON.parse(seatsRes.body).data;
    const available = seats.filter((s) => s.status === 'AVAILABLE');

    if (available.length === 0) {
      reservationGiveUp.add(1); // 매진
      break;
    }

    const pick = available[Math.floor(Math.random() * available.length)];
    const reserveRes = http.post(
      `${BASE}/reservations`,
      JSON.stringify({
        seatId: pick.seatId,
        roundId: ROUND_ID,
        reservationId: pick.reservationId,
        queueToken,
      }),
      { headers }
    );

    if (reserveRes.status !== 200) {
      reservationBug.add(1); // 500 등 진짜 서버 에러
      break;
    }

    const body = JSON.parse(reserveRes.body);
    if (body.success) {
      reservationSuccess.add(1);
      reserved = true;
      break;
    }
    // "이미 예매된/선점된 좌석" — 정상적인 경합 실패, 다른 좌석으로 재시도
    sleep(0.3 + Math.random() * 0.5);
  }

  if (!reserved) {
    reservationGiveUp.add(1);
    leaveQueue(queueToken, headers); // 못 구하고 포기 — 슬롯 바로 반납(위 leaveQueue 주석 참고)
  }

  // 6. 마이페이지 확인
  http.get(`${BASE}/reservations/my`);
}
