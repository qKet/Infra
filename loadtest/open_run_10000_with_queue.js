// 오픈런 시뮬레이션 — 대기열(QueueController)까지 포함한 풀 유저 여정.
// "홈 → 로그인 → 상세 → 대기열 참가 → 3초 폴링(QueueModal.tsx와 동일 주기) → 좌석조회 → 예매"
// 전체를 한 VU가 순서대로 수행함 — frontend(SSR 페이지)와 backend(API) 둘 다 부하가 걸림.
// 대기열 없이 frontend/backend만 보고 싶으면 open_run_10000_no_queue.js 참고.
//
// executor: per-vu-iterations(vus × iterations:1) — "만 명이 동시에 왔다가 각자 딱 한 번만
// 시도하고 끝" 모델. 2026-08-18에 constant-vus(반복형)로 500 VU를 돌렸다가, 각 VU가 2분
// 내내 시나리오를 계속 반복해서 실제로는 500명이 아니라 그보다 훨씬 많은 시도(로그인만 초당
// ~40건)를 만들어냈던 걸 뒤늦게 발견함 — 진짜 오픈런은 "그 순간 한 번씩" 몰리는 거지 "계속
// 재시도"가 아니라서, 이 실수를 재현 안 하려고 per-vu-iterations로 바꿈.
//
// 2026-08-10 CLAUDE_LLM_WIKI decisions/2026-08-10-redis-session-queue-shared-instance-risk
// 문서가 "재검토 트리거"로 요구했던 바로 그 부하테스트 — 세션+대기열이 같은 Redis 인스턴스를
// 공유하는데, 대기열 폴링(3초 간격)이 Redis에 명령어를 얼마나 쏟아붓는지 실측하기 위함.
//
// 대부분의 VU는 실패하는 게 정상 — 좌석은 몇백~몇천 석뿐인데 10000명이 동시에 경쟁하므로
// 대기열 만료/좌석 매진으로 끝나는 시나리오가 대다수. 이건 버그가 아니라 실제 오픈런의 모습.
// 그래서 threshold는 "예매 성공률"이 아니라 "서버가 죽지 않았는가"(5xx/타임아웃 비율)만 봄.

import http from 'k6/http';
import { sleep, check, group } from 'k6';
import { Rate } from 'k6/metrics';

const BASE_WEB = __ENV.BASE_WEB || 'https://dev.jun979.click';
const BASE_API = `${BASE_WEB}/api`;

// 오픈런 대상 회차 — 기본값은 아이유 콘서트 1회차(performance_id=1, round_id=1, data.sql 시드 기준).
// 다른 공연/회차로 바꾸고 싶으면 실행할 때 -e 로 덮어쓰면 됨:
//   k6 run -e PERFORMANCE_ID=2 -e ROUND_ID=3 open_run_10000_with_queue.js
const PERFORMANCE_ID = __ENV.PERFORMANCE_ID || '1';
const ROUND_ID = __ENV.ROUND_ID || '1';

// data.sql 시드 계정 중 로그인 가능한 5개만 씀 — testuser06은 SUSPENDED라 로그인 자체가 실패함.
// VU마다 순환 배정(__VU % 5)해서 한 계정에만 부하가 쏠리지 않게 함.
const TEST_USERS = ['testuser01', 'testuser02', 'testuser03', 'testuser04', 'testuser05'];

// 대기열 폴링 최대 횟수 — 3초 간격 × 40회 = 최대 2분 대기 후 포기(실제 QueueModal은 무한 폴링이지만,
// 테스트에서는 유한하게 끊어야 VU가 영원히 안 끝남).
const MAX_POLL_ATTEMPTS = 40;
const POLL_INTERVAL_SEC = 3;

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
const queueEnteredRate = new Rate('queue_entered');

export const options = {
  scenarios: {
    open_run: {
      executor: 'per-vu-iterations',
      vus: Number(__ENV.VUS) || 10000,
      iterations: 1, // VU당 딱 1번 — "만 명이 각자 한 번씩 시도"를 그대로 재현
      // 대기열 폴링(최대 2분)까지 포함해서 VU 하나가 끝나는 데 시간이 걸리므로 no_queue보다
      // 여유 있게 잡음 — 10000 VU를 한꺼번에 못 띄우면 k6가 배치로 나눠 도는데 그 전체 상한.
      maxDuration: __ENV.DURATION || '15m',
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

  let queueToken;
  group('4. 대기열 참가', () => {
    const res = http.post(
      `${BASE_API}/queues`,
      JSON.stringify({ scheduleId: Number(ROUND_ID) }),
      { headers: { 'Content-Type': 'application/json' }, tags: { name: 'queue-join' } }
    );
    if (check(res, { '대기열 참가 200': (r) => r.status === 200 })) {
      queueToken = res.json('queueToken');
    }
  });

  if (!queueToken) return;

  // 5. 3초 간격 폴링 — 실제 QueueModal.tsx의 setInterval(..., 3000)과 동일한 주기로
  // Redis(대기열 상태) + 세션(로그인 유지)에 계속 부하를 줌.
  let entered = false;
  group('5. 대기열 폴링', () => {
    for (let i = 0; i < MAX_POLL_ATTEMPTS; i++) {
      sleep(POLL_INTERVAL_SEC);
      const res = http.get(`${BASE_API}/queues/${queueToken}`, { tags: { name: 'queue-poll' } });
      if (res.status !== 200) break;
      const status = res.json('status');
      if (status === 'ENTERED') {
        entered = true;
        break;
      }
      if (status === 'EXPIRED') break;
    }
  });
  queueEnteredRate.add(entered);

  if (!entered) return; // 대기열에서 못 들어옴 — 오픈런에서 제일 흔한 결말

  let seat;
  group('6. 좌석 조회', () => {
    // 프론트 좌석선택 페이지도 같이 호출 — frontend에도 부하가 걸리게 함
    http.get(`${BASE_WEB}/seats/${ROUND_ID}?queueToken=${queueToken}`, { tags: { name: 'seats-page' } });

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

  if (!seat) return; // 좌석 매진 — 이것도 오픈런에서 흔한 결말

  randomSleep(1, 4); // 좌석 고르는 시간

  group('7. 예매', () => {
    // 백엔드는 실패(좌석 선점됨 등)도 HTTP 200 + {success:false}로 응답함
    // (ReservationServiceImpl 참고) — 그래서 http.post 상태코드가 아니라 body.success로 판단해야 함.
    const res = http.post(
      `${BASE_API}/reservations`,
      JSON.stringify({
        seatId: seat.seatId,
        roundId: Number(ROUND_ID),
        reservationId: seat.reservationId,
        queueToken,
      }),
      { headers: { 'Content-Type': 'application/json' }, tags: { name: 'reserve' } }
    );
    const ok = check(res, { '예매 응답 200': (r) => r.status === 200 });
    const success = ok && res.json('success') === true;
    reservationSuccessRate.add(success);
  });
}
