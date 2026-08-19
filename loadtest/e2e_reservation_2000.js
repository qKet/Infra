import http from 'k6/http';
import { sleep, check } from 'k6';
import { Counter, Trend } from 'k6/metrics';

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
const BASE = 'https://dev.jun979.click/api';
const ROUND_ID = 18;

const reservationSuccess = new Counter('reservation_success');
const reservationGiveUp = new Counter('reservation_give_up'); // 매진/대기열 만료로 포기
const reservationBug = new Counter('reservation_unexpected_fail'); // 200이 아닌 응답 = 진짜 버그
const transientFail = new Counter('transient_http_fail'); // 폴링/좌석조회 중 일시적 비-200 응답(배포 등) — 버그 아님, 그 VU만 조기 종료
const queueWaitSeconds = new Trend('queue_wait_seconds');

export const options = {
  scenarios: {
    e2e_reservation: {
      executor: 'per-vu-iterations',
      vus: 2000,
      iterations: 1,
      maxDuration: '40m', // 대기열 MAX_ACTIVE_USERS=10 이라 2000명이 다 순서 오는데 오래 걸림 — 넉넉히 잡음
    },
  },
  thresholds: {
    reservation_unexpected_fail: ['count==0'], // 이게 0이 아니면 락/서버 버그 의심
  },
};

export default function () {
  const userId = `loadtest${String(__VU).padStart(4, '0')}`;
  const headers = { 'Content-Type': 'application/json' };

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
  const queueToken = JSON.parse(joinRes.body).queueToken;

  // 4. 대기열 상태 폴링 — ENTERED(활성) 될 때까지 (MAX_ACTIVE_USERS=10이라 순서 기다림)
  const waitStart = Date.now();
  let entered = false;
  let pollBroke = false;
  for (let i = 0; i < 300; i++) {
    const statusRes = http.get(`${BASE}/queues/${queueToken}`);
    if (statusRes.status !== 200) {
      // 배포 중 ALB가 순간적으로 HTML 에러페이지를 돌려주는 경우 등 — JSON 파싱 시도하지 않고
      // 이 VU만 조기 종료 (전체 테스트를 죽이지 않기 위해 여기서 return)
      transientFail.add(1);
      pollBroke = true;
      break;
    }
    const status = JSON.parse(statusRes.body).status;
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
    return;
  }

  if (!entered) {
    reservationGiveUp.add(1); // 대기열 만료 = 실사용자라면 포기했을 상황
    return;
  }

  // 5. 좌석 선택 + 예매 (실패하면 다른 좌석으로 재시도 — 실제 유저 행동 재현)
  let reserved = false;
  for (let attempt = 0; attempt < 20; attempt++) {
    const seatsRes = http.get(`${BASE}/schedules/${ROUND_ID}/seats`);
    if (seatsRes.status !== 200) {
      transientFail.add(1);
      return; // give_up과 섞이지 않게 여기서 바로 종료
    }
    const seats = JSON.parse(seatsRes.body);
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
        roundId: pick.roundId,
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
  }

  // 6. 마이페이지 확인
  http.get(`${BASE}/reservations/my`);
}
