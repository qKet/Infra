// 대용량 부하테스트 — frontend/backend에만 부하를 걸림(대기열은 뺌).
// "홈 → 로그인 → 상세 → 좌석조회 → 예매" 를 한 VU가 순서대로 수행함 —
// 홈/상세는 frontend(SSR 페이지), 나머지는 backend API. 대기열(QueueController) 경유는
// 의도적으로 안 함 — queueToken은 ReservationServiceImpl.reserve()에서 선택값이라
// 안 보내도 예매 자체는 그대로 동작함(성공 시 대기열 이탈 처리만 스킵될 뿐).
// 대기열까지 포함해서 Redis 폴링 부하도 같이 보고 싶으면 open_run_10000_with_queue.js 참고.
//
// executor: per-vu-iterations(vus × iterations:1) — "만 명이 동시에 왔다가 각자 딱 한 번만
// 시도하고 끝" 모델. 2026-08-18에 constant-vus(반복형)로 500 VU를 돌렸다가, 각 VU가 2분
// 내내 시나리오를 계속 반복해서 실제로는 500명이 아니라 그보다 훨씬 많은 시도(로그인만 초당
// ~40건)를 만들어냈던 걸 뒤늦게 발견함 — 진짜 오픈런은 "그 순간 한 번씩" 몰리는 거지 "계속
// 재시도"가 아니라서, 이 실수를 재현 안 하려고 per-vu-iterations로 바꿈.
//
// 대부분의 VU는 예매에 실패하는 게 정상 — 좌석은 몇백~몇천 석뿐인데 10000명이 한 회차를
// 동시에 경쟁하므로 좌석 매진으로 끝나는 시나리오가 대다수. 이건 버그가 아니라 실제
// 오픈런의 모습. 그래서 threshold는 "예매 성공률"이 아니라 "서버가 죽지 않았는가"
// (5xx/타임아웃 비율)만 봄 — 예매 성공률은 커스텀 메트릭(reservation_success)으로 별도 관찰.

import http from 'k6/http';
import { sleep, check, group } from 'k6';
import { Rate } from 'k6/metrics';

const BASE_WEB = __ENV.BASE_WEB || 'https://dev.jun979.click';
const BASE_API = `${BASE_WEB}/api`;

// 오픈런 대상 회차 — 기본값은 아이유 콘서트 1회차(performance_id=1, round_id=1, data.sql 시드 기준).
// 다른 공연/회차로 바꾸고 싶으면 실행할 때 -e 로 덮어쓰면 됨:
//   k6 run -e PERFORMANCE_ID=2 -e ROUND_ID=3 open_run_10000_no_queue.js
const PERFORMANCE_ID = __ENV.PERFORMANCE_ID || '1';
const ROUND_ID = __ENV.ROUND_ID || '1';

// data.sql 시드 계정 중 로그인 가능한 5개만 씀 — testuser06은 SUSPENDED라 로그인 자체가 실패함.
// VU마다 순환 배정(__VU % 5)해서 한 계정에만 부하가 쏠리지 않게 함.
const TEST_USERS = ['testuser01', 'testuser02', 'testuser03', 'testuser04', 'testuser05'];

// per-vu-iterations는 VU를 거의 동시에 다 띄움 — VU 수천 개가 진짜 같은 순간에 커넥션을
// 열면 ALB 자체가 순간적으로 못 받아내서 TLS 핸드셰이크 단계에서 리셋됨(2026-08-18 10000 VU
// 테스트에서 실제로 겪음 — CloudWatch ClientTLSNegotiationErrorCount가 분당 6~8천건까지 튐,
// RejectedConnectionCount/TargetConnectionErrorCount는 0이라 backend가 아니라 ALB 자체의
// 순간 용량 한계였음이 확인됨. ALB는 트래픽 추세를 보고 점진적으로 용량을 늘리는 구조라
// "완전히 같은 순간"의 폭증은 AWS 인프라 레벨에서도 못 받아냄). 실제 오픈런도 완전히 같은
// 밀리초에 동시 접속하진 않으므로, 각 VU가 요청을 시작하기 전 0~RAMP_SECONDS초 사이에서
// 무작위로 대기하게 해서 커넥션 개설을 몇 초에 걸쳐 자연스럽게 분산시킴.
const RAMP_SECONDS = Number(__ENV.RAMP_SECONDS) || 10;

const reservationSuccessRate = new Rate('reservation_success');

export const options = {
  scenarios: {
    open_run: {
      executor: 'per-vu-iterations',
      vus: Number(__ENV.VUS) || 10000,
      iterations: 1, // VU당 딱 1번 — "만 명이 각자 한 번씩 시도"를 그대로 재현
      // 10000 VU를 한꺼번에 못 띄우면(로컬 리소스 한계) k6가 배치로 나눠 도는데, 그 전체가
      // 끝나는 데 걸리는 최대 허용 시간. 넉넉하게 잡아둠 — 실제로 다 끝나면 그 전에 종료됨.
      maxDuration: __ENV.DURATION || '10m',
    },
  },
  // macOS는 TLS 인증서 검증을 시스템(Security.framework) 블로킹 syscall로 처리함 — VU
  // 수천 개가 거의 동시에 HTTPS 커넥션을 열면 그만큼 OS 스레드가 한꺼번에 블로킹되고,
  // Go 런타임 스레드 상한(1만 개)을 넘겨서 k6 프로세스 자체가 죽는 문제가 있음(2026-08-18
  // 10000 VU 테스트에서 실제로 겪음 — "runtime: program exceeds 10000-thread limit"류 크래시).
  // 우리 도메인이라 인증서 검증 자체가 불필요해서 꺼서 이 무거운 경로를 회피함.
  insecureSkipTLSVerify: true,
  thresholds: {
    // 4xx(좌석마감 등 정상적인 비즈니스 실패)는 http_req_failed에 안 잡힘 — 이 지표가 튀면
    // 5xx/타임아웃/커넥션 에러라는 뜻이라 진짜 장애 신호로 봐도 됨.
    http_req_failed: ['rate<0.3'],
  },
};

function randomSleep(minSec, maxSec) {
  sleep(minSec + Math.random() * (maxSec - minSec));
}

export default function () {
  const user = TEST_USERS[__VU % TEST_USERS.length];

  // VU마다 시작 시점을 0~RAMP_SECONDS초 사이로 흩어서 커넥션 개설이 진짜 한순간에 안 몰리게 함
  // (위 RAMP_SECONDS 주석 참고 — ALB TLS negotiation 실패 방지).
  sleep(Math.random() * RAMP_SECONDS);

  group('1. 홈 진입 (frontend SSR)', () => {
    const res = http.get(BASE_WEB + '/', { tags: { name: 'home' } });
    check(res, { '홈 200': (r) => r.status === 200 });
  });

  randomSleep(0.5, 2);

  let loggedIn = false;
  group('2. 로그인', () => {
    const res = http.post(
      `${BASE_API}/auth/login`,
      JSON.stringify({ userId: user, pwd: 'test1234' }),
      { headers: { 'Content-Type': 'application/json' }, tags: { name: 'login' } }
    );
    loggedIn = check(res, { '로그인 200': (r) => r.status === 200 });
  });

  if (!loggedIn) return;

  randomSleep(1, 3);

  group('3. 공연 상세 (frontend SSR)', () => {
    const res = http.get(`${BASE_WEB}/events/${PERFORMANCE_ID}`, { tags: { name: 'event-detail' } });
    check(res, { '상세 200': (r) => r.status === 200 });
  });

  randomSleep(1, 3); // "예매하기" 누르기까지의 사용자 딜레이

  let seat;
  group('4. 좌석 조회', () => {
    // 프론트 좌석선택 페이지도 같이 호출 — frontend에도 부하가 걸리게 함
    http.get(`${BASE_WEB}/seats/${ROUND_ID}`, { tags: { name: 'seats-page' } });

    const res = http.get(`${BASE_API}/schedules/${ROUND_ID}/seats`, { tags: { name: 'seats-api' } });
    if (check(res, { '좌석 조회 200': (r) => r.status === 200 })) {
      // 이 엔드포인트는 배열을 바로 안 주고 {success, message, data} 로 감싸서 내려줌
      // (ApiResponse 컨벤션 — wiki conventions/api-response-format 참고). data가 실제 배열.
      const seats = res.json('data') || [];
      const available = seats.filter((s) => s.status === 'AVAILABLE');
      if (available.length > 0) {
        seat = available[Math.floor(Math.random() * available.length)];
      }
    }
  });

  if (!seat) return; // 좌석 매진 — 오픈런에서 흔한 결말

  randomSleep(1, 4); // 좌석 고르는 시간

  group('5. 예매', () => {
    // 백엔드는 실패(좌석 선점됨 등)도 HTTP 200 + {success:false}로 응답함
    // (ReservationServiceImpl 참고) — 그래서 http.post 상태코드가 아니라 body.success로 판단해야 함.
    const res = http.post(
      `${BASE_API}/reservations`,
      JSON.stringify({
        seatId: seat.seatId,
        roundId: Number(ROUND_ID),
        reservationId: seat.reservationId,
      }),
      { headers: { 'Content-Type': 'application/json' }, tags: { name: 'reserve' } }
    );
    const ok = check(res, { '예매 응답 200': (r) => r.status === 200 });
    const success = ok && res.json('success') === true;
    reservationSuccessRate.add(success);
  });
}
