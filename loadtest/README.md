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
- 백엔드 replica 수/`DB_POOL_SIZE`가 RDS(`db.t3.micro`) 커넥션 상한(~85)을 넘지 않는지 테스트 전 확인 — `CD/helm/values.yaml`의 `backend.replicas` × `backend.dbPoolSize` 참고
- 테스트 계정(`testuser01`/`test1234`)은 release DB 시드 데이터(`backend/src/main/resources/data.sql`)에 포함돼 있어야 함
