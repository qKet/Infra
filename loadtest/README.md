# 부하테스트 (k6)

release 환경(`dev.jun979.click`)을 대상으로 한 k6 부하테스트 스크립트 모음.

## 설치

```bash
# Windows (PowerShell/winget)
winget install -e --id GrafanaLabs.k6

# Mac
brew install k6
```

## 실행

```bash
cd Infra/loadtest
k6 run spike_1000_login.js
```

## `spike_1000_login.js` 시나리오

가상 유저 1000명이 동시에 시작(즉시 스파이크)해서 90초 동안 반복:
1. `testuser01`/`test1234`로 로그인 (Redis 세션 생성)
2. `/categories`, `/events/paged` 조회 (DB 조회)
3. 1초 쉬고 반복

**결과**: 마지막에 `checks_succeeded`(로그인 성공률), `http_req_failed`(실패율), `http_req_duration`(응답시간) 요약이 나옴.

**조절**: `vus`(가상 유저 수), `duration`(지속 시간) 숫자만 바꾸면 규모/시간 조절 가능.

## `open_run_10000_*.js` 시나리오 — 오픈런 재현 (2개 버전)

`spike_1000_login.js`는 로그인+조회만 보는 단순 스크립트였는데, 이 둘은 **frontend/backend 양쪽에 다 부하가 걸리는 풀 예매 여정**임. 대기열 포함 여부만 다른 두 파일로 나눠져 있음(둘 다 가상 유저 10000명이 각자 딱 한 번씩 시도).

공통 흐름: 홈 진입(frontend SSR) → 로그인(`testuser01`~`05` 순환 배정, `testuser06`은 SUSPENDED라 제외) → 공연 상세(frontend SSR) → (대기열, `with_queue`만) → 좌석 조회(frontend 페이지 + API) → 예매 시도.

**executor는 `per-vu-iterations`(`vus` × `iterations: 1`)** — VU마다 시나리오를 딱 1번만 실행하고 끝남. 2026-08-18에 `constant-vus`(반복형, `duration`만 주고 `iterations` 없음)로 500 VU를 돌렸다가, 각 VU가 그 시간 내내 시나리오를 계속 반복해서 "500명"이 아니라 로그인만 초당 ~40건(≈500명이 2분간 9번씩 재시도한 것과 같은 부하)을 만들어냈던 걸 뒤늦게 발견함 — 실제 오픈런은 "그 순간 한 번씩" 몰리는 거지 "계속 재시도"가 아니라서, `VUS` 숫자가 곧 "그 순간 시도한 사람 수"와 정확히 일치하도록 바꿈.

### `open_run_10000_no_queue.js` — 대기열 없이 frontend+backend만

```bash
k6 run open_run_10000_no_queue.js
```

대기열(`/api/queues/*`)을 안 거치고 상세 페이지 다음 바로 좌석 조회로 감. `queueToken`은 `ReservationServiceImpl.reserve()`에서 선택값이라 안 보내도 예매 자체는 그대로 됨(성공 시 대기열 이탈 처리만 스킵). 순수하게 frontend SSR + backend API(로그인/좌석조회/예매)에만 부하를 집중시키고 싶을 때.

### `open_run_10000_with_queue.js` — 대기열까지 포함한 완전판

```bash
k6 run open_run_10000_with_queue.js
```

상세 페이지 다음 대기열 참가 → **3초 간격 폴링**(최대 40회=2분, `QueueModal.tsx`의 `setInterval(...,3000)`과 동일 주기)까지 재현 — Redis(대기열 상태)+세션에 계속 부하를 줌. 이게 바로 [CLAUDE_LLM_WIKI decisions/2026-08-10-redis-session-queue-shared-instance-risk](../../CLAUDE_LLM_WIKI/wiki/decisions/2026-08-10-redis-session-queue-shared-instance-risk.md)가 요구했던 "재검토 트리거"(실제 오픈런 트래픽을 흉내낸 부하테스트) — 결과 보고 세션/대기열 Redis 물리 분리 여부를 재판단하기로 했었음.

### 공통 옵션

두 파일 다 환경변수로 조절 가능:

```bash
# 다른 공연/회차로 바꾸거나 규모를 줄여서 먼저 검증하고 싶으면:
k6 run -e PERFORMANCE_ID=2 -e ROUND_ID=3 -e VUS=500 -e DURATION=2m open_run_10000_no_queue.js
```
(`DURATION`은 `per-vu-iterations`에서 `maxDuration`으로 쓰임 — 실제로 다 끝나면 그 전에 종료되는 안전상한선일 뿐, "몇 초간 반복"이라는 뜻이 아님)

**대부분의 VU는 예매에 실패하는 게 정상** — 좌석은 몇백~몇천 석뿐인데 10000명이 한 회차(기본값: 아이유 콘서트 1회차)를 동시에 경쟁하므로, `with_queue`는 대기열에서 못 들어오거나, `no_queue`는 좌석이 이미 매진돼서 끝나는 게 대다수. 이건 버그가 아니라 실제 오픈런의 모습 — 그래서 `thresholds`는 예매 성공률이 아니라 `http_req_failed`(5xx/타임아웃 비율)만 봄. 예매 성공률/대기열 진입률은 커스텀 메트릭(`reservation_success`, `queue_entered` — `with_queue`만)으로 결과 요약에서 따로 확인 가능.

⚠️ **10000 VU는 로컬 머신의 파일디스크립터 한도에 걸릴 수 있음** — 특히 macOS 기본값(`ulimit -n 256`)으로는 못 엶. 실행 전에 반드시 올려둘 것:
```bash
ulimit -n 65536
```
그래도 로컬 노트북 성능/네트워크가 병목이 될 수 있으니, 처음엔 `-e VUS=500` 정도로 스크립트 자체가 잘 도는지 먼저 확인 후 10000까지 올리는 걸 추천. 계속 불안정하면 같은 리전 EC2에서 돌리는 것도 고려.

⚠️ **macOS에서 VU 수천 개가 순간적으로 몰리면 k6 프로세스 자체가 죽을 수 있음**(`runtime: program exceeds 10000-thread limit`류 크래시, 2026-08-18 10000 VU 테스트에서 실제로 겪음) — macOS는 TLS 인증서 검증을 시스템(Security.framework) 블로킹 syscall로 처리해서, VU 수천 개가 거의 동시에 HTTPS 커넥션을 열면 그만큼 OS 스레드가 한꺼번에 블로킹되고 Go 런타임 스레드 상한(1만 개)을 넘겨버림 — **서버(EKS) 문제가 아니라 로컬 테스트 클라이언트 한계**. 두 스크립트 다 `options.insecureSkipTLSVerify: true`로 이 경로를 회피해뒀음. 그래도 계속 죽으면 같은 리전 EC2(Linux — 이 syscall 문제 자체가 없음)에서 돌리는 걸 추천.

⚠️ **VU 1만 개가 진짜로 같은 순간에 커넥션을 열면 ALB 자체가 TLS 핸드셰이크 단계에서 리셋시킴** — macOS 크래시를 피해서 Linux(EC2)에서 돌려도 이 문제는 남음. 2026-08-18 실측: CloudWatch `ClientTLSNegotiationErrorCount`가 분당 6~8천 건까지 튀었는데 `RejectedConnectionCount`/`TargetConnectionErrorCount`는 0 — backend/frontend가 아니라 **ALB 자체의 순간 용량(LCU) 한계**였음(ALB는 트래픽 추세를 보고 점진적으로 용량을 늘리는 구조라 대비 없는 순간 폭증은 AWS 인프라 레벨에서도 못 받아냄, AWS도 대규모 스파이크 예정 시 사전 pre-warming을 권장함). 두 스크립트 다 이제 각 VU가 요청 시작 전 `0~RAMP_SECONDS`초(기본 10초) 사이에서 무작위로 대기해서 커넥션 개설을 자연스럽게 분산시킴 — "만 명이 각자 한 번씩"이라는 본질은 그대로 유지. 그래도 TLS negotiation 에러가 보이면 `-e RAMP_SECONDS=30`처럼 더 넓게 잡아서 재시도.
## `e2e_reservation_2000.js` 시나리오 (엔드투엔드 + Redis 부하테스트)

로그인 → 목록조회 → 대기열 진입 → 좌석선택 → 예매까지, 실제 예매 여정 전체를 2000명이 동시에 수행.
로그인(Redis 세션), 대기열(Redis), 좌석 락(Redis 분산락) 세 군데를 전부 실제로 거침.

**결제 단계는 제외됨** — `POST /payments/confirm`이 실제 토스페이먼츠 API를 호출해서 검증하기 때문에
자동화된 부하테스트로는 완주 불가. 대신 `POST /reservations`(결제 없이 직접 예매)를 쓰는데, 이게
내부적으로 결제 흐름과 완전히 동일한 Redis 락 로직을 타서 락 검증 목적으로는 충분함.

**사전 조건**:
1. `seed_test_accounts.sql`로 `loadtest0001`~`loadtest2000` 계정을 대상 DB에 미리 생성해둘 것
2. `ROUND_ID`(스크립트 상단)를 AVAILABLE 좌석이 넉넉한 실제 회차 ID로 맞춰둘 것 — 아래처럼 직접 조회해서 확인:
   ```sql
   SELECT round_id, COUNT(*) FROM RESERVATIONS WHERE reserved_status='AVAILABLE' GROUP BY round_id ORDER BY 2 DESC;
   ```

```bash
k6 run e2e_reservation_2000.js
```

**대기열 특성상 오래 걸림**: `QueueServiceImpl`의 `MAX_ACTIVE_USERS=10`이라 한 번에 10명만 활성화되고
나머지는 대기함. 2000명이 전부 순서를 받으려면 시간이 꽤 걸리므로 `maxDuration: 40m`로 넉넉히 잡아둠 —
빨리 끝나지 않는다고 이상한 게 아님.

**테스트 후 반드시 확인**:
- k6 리포트의 `reservation_unexpected_fail` 카운터가 0인지 (500 등 진짜 서버 에러 여부)
- DB에서 이중예매 여부 직접 확인:
  ```sql
  SELECT seat_id, COUNT(*) FROM RESERVATIONS
  WHERE round_id=18 AND reserved_status='RESERVED' GROUP BY seat_id HAVING COUNT(*) > 1;
  ```
  (결과가 하나라도 있으면 Redis 락이 뚫린 것 — 심각한 버그)
- 테스트 끝나고 좌석 원복하려면: `UPDATE RESERVATIONS SET user_id=NULL, reserved_status='AVAILABLE', reserved_at=NULL WHERE round_id=18 AND user_id LIKE 'loadtest%';`

## `sustained_1000_login.js` 시나리오 (장시간 부하테스트)

`spike_1000_login.js`는 90초짜리 즉시 스파이크라 아래 세 가지는 확인이 안 됨:
- RDS(`db.t3.*`)는 버스터블 인스턴스라 CPU 크레딧이 바닥나야 성능이 급락하는데, 크레딧 소진에는 몇 분 이상 지속 부하가 필요함
- cluster-autoscaler가 노드를 실제로 추가하는 데 수 분이 걸림 — 짧은 테스트는 그 전에 끝나버림
- KEDA/HPA가 replica를 늘렸다 줄였다 진동하지 않고 안정적인 값으로 수렴하는지도 몇 분은 지켜봐야 보임

그래서 총 25분 구성으로 만듦: 3분 램프업(0→1000, 커넥션 스톰 방지) → **20분 유지(1000 VU)** → 2분 램프다운.

```bash
k6 run sustained_1000_login.js
```

### 테스트 도중 반드시 같이 관찰할 것

1. **RDS CPU 크레딧 잔량**: CloudWatch → RDS → 해당 인스턴스 → `CPUCreditBalance` 지표. 테스트 시작 시점 대비 20분 유지 구간 동안 계속 떨어지기만 하면 소진 위험 신호. `CPUUtilization`도 같이 보면 크레딧 소진 시점부터 처리량이 꺾이는 게 보임.
2. **노드 개수 변화**: `kubectl get nodes -w` 로 cluster-autoscaler가 실제로 노드를 늘리는지, 몇 분 만에 늘리는지 관찰.
3. **HPA 수렴 여부**: `kubectl get hpa -w` — replica 수가 어느 값에서 안정되는지, 아니면 계속 오르내리는지(진동) 확인.
4. **Grafana `qket` 대시보드** — CPU 스로틀링(pod별), 노드 CPU 사용률, HikariCP 커넥션 수 패널을 20분 내내 관찰. ([[backend-cpu-throttling-and-scaling-load-test]], [[hikaricp-connection-storm-load-test]] 참고)
5. **램프다운 이후 회복**: 부하가 0으로 내려간 뒤 HikariCP 커넥션/노드 개수가 원래 수준으로 돌아오는지(과도한 노드가 남아있지 않은지, cluster-autoscaler의 scale-down도 정상 동작하는지).

## 테스트 중 모니터링

### 1. k6 자체 실시간 웹 대시보드 (요청률/응답시간/에러율 — 클라이언트 관점)

```bash
K6_WEB_DASHBOARD=true k6 run spike_1000_login.js
```

`http://127.0.0.1:5665`가 자동으로 열리고, 테스트 도는 동안 VU 수/요청률/응답시간이 실시간 그래프로 나옴. 끝나고 리포트 파일로 남기고 싶으면:

```bash
K6_WEB_DASHBOARD=true K6_WEB_DASHBOARD_EXPORT=report.html k6 run spike_1000_login.js
```

### 2. Grafana (CPU/DB/Redis — 서버 관점)

```bash
kubectl port-forward -n monitoring svc/monitoring-grafana 3030:80
```

→ 브라우저에서 `http://localhost:3030` 접속, 대시보드 "qket" 확인.

두 화면을 나란히 띄워서 "k6가 보는 요청/응답 상황"과 "서버가 실제로 느끼는 부하"를 같이 보는 걸 추천. (k6→Prometheus로 흘려서 한 Grafana에 합치는 방법도 있지만, 지금 AMP 인증이 미해결 이슈라 별도로 안 함)

## 주의사항

- 대상은 `release` 환경 실제 배포 도메인(`dev.jun979.click`) — 로컬/개발 서버가 아니라 실제 EKS 위 서비스에 부하를 줌
- 백엔드 replica 수/`DB_POOL_SIZE`가 RDS 커넥션 상한을 넘지 않는지 테스트 전 확인 — `CD/helm/values.yaml`의 `backend.replicas`(KEDA `maxReplicas`) × `backend.dbPoolSize` 참고. release는 2026-08-18에 `db.t3.micro`(~85 커넥션) → `db.t3.medium`(~340 커넥션)으로 상향함(`Infra/04_data/main.tf`) — CLAUDE_LLM_WIKI decisions/2026-08-18-capacity-planning-large-traffic-readiness 참고
- 테스트 계정(`testuser01`/`test1234`)은 release DB 시드 데이터(`backend/src/main/resources/data.sql`)에 포함돼 있어야 함
