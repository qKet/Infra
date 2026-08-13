import http from 'k6/http';
import { sleep, check } from 'k6';

export const options = {
  scenarios: {
    spike: {
      executor: 'constant-vus',
      vus: 1000,
      duration: '90s',
    },
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
  sleep(1);
}
