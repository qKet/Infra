import http from 'k6/http';
import { sleep, check } from 'k6';

// 목적: spike_1000_login.js(90초 즉시 스파이크)와 달리,
// "부하가 몇 분 이상 지속되면 무슨 일이 일어나는가"를 보기 위한 시나리오.
// - RDS(db.t3.*)는 버스터블 인스턴스라 CPU 크레딧이 바닥나면 그때부터 성능이 급락함 — 짧은 스파이크로는 안 보임
// - cluster-autoscaler(노드 추가)는 반응까지 수 분이 걸림 — 짧은 스파이크로는 노드 스케일아웃이 끝나기도 전에 테스트가 끝남
// - KEDA/HPA가 replica를 늘렸다 줄였다 진동(thrashing)하지 않고 안정적으로 수렴하는지도 몇 분은 지켜봐야 보임
export const options = {
  scenarios: {
    sustained: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '3m', target: 1000 },  // 점진적 램프업 — HikariCP 커넥션 스톰 재발 방지 (hikaricp-connection-storm-load-test 참고)
        { duration: '20m', target: 1000 }, // 핵심 구간: 20분 이상 유지 — RDS CPU 크레딧 소진, 노드 오토스케일링, HPA 수렴 여부 관찰
        { duration: '2m', target: 0 },     // 램프다운 — 부하 해소 후 커넥션/리소스가 정상 회복되는지 확인
      ],
      gracefulRampDown: '30s',
    },
  },
  thresholds: {
    http_req_failed: ['rate<0.05'],
    'checks{check:로그인 성공}': ['rate>0.95'],
  },
};

const BASE = 'https://dev.jun979.click/api';

export default function () {
  const loginRes = http.post(
    `${BASE}/auth/login`,
    JSON.stringify({ userId: 'testuser01', pwd: 'test1234' }),
    { headers: { 'Content-Type': 'application/json' } }
  );
  check(loginRes, { '로그인 성공': (r) => r.status === 200 });

  http.get(`${BASE}/categories`);
  http.get(`${BASE}/events/paged`);

  // 모든 VU가 정확히 같은 박자로 요청을 쏘면 실제 트래픽보다 인위적인 주기적 스파이크가 생김 — 지터 추가
  sleep(1 + Math.random() * 2);
}
