# Infra

Qket 인프라의 Terraform 코드. 디렉토리는 apply 순서를 그대로 드러내는 숫자 접두사로 정렬됩니다.

```
00_network/           VPC, 서브넷, 보안그룹 — 무료 리소스, 절대 안 지움
01_infrastructure/    EKS, bastion, NAT Gateway — 순수 AWS API 리소스, 매일 껐다 켬
02_k8s-addon/         ArgoCD, Karpenter, KEDA, ALB Controller, 모니터링 등 K8s addon 전체
03_registry/          ECR, GitHub Actions OIDC — 공유·불변, 절대 안 지움
04_data/release/      release용 데이터 계층 (dev-datastore StatefulSet + S3)
04_data/prod/         prod용 데이터 계층 (RDS + ElastiCache + S3)
modules/               위 root들이 공유하는 Terraform 모듈
modules/addons/        02_k8s-addon이 쓰는 K8s addon 모듈들(아래 참고)
loadtest/               k6 부하테스트 스크립트
lambda/                 이메일 발송 등 Lambda 함수 소스
```

## 최초 적용 순서

```bash
cd 00_network && terraform init && terraform apply
cd 01_infrastructure && terraform init && terraform apply
cd 02_k8s-addon && terraform init && terraform apply
cd 03_registry && terraform init && terraform apply
cd 04_data/release && terraform init && terraform apply
cd 04_data/prod && terraform init && terraform apply
```

## 매일 아침/저녁

`01_infrastructure`/`02_k8s-addon`은 비용 절감을 위해 매일 밤 destroy → 아침 재적용합니다. `00_network`/`03_registry`/`04_data`는 손대지 않습니다.

> ⚠️ `01_infrastructure`는 반드시 `-target`으로 지울 리소스를 명시해서 destroy할 것 — target 없이 지우면 로컬에 없는 브랜치의 리소스(예: AMP 등)까지 같이 날아갈 수 있습니다.

## `modules/addons/` 한눈에 보기

| 모듈 | 역할 |
|---|---|
| `karpenter` | 노드 레벨 오토스케일링(cluster-autoscaler 대체) |
| `overprovisioning` | 낮은 우선순위 "풍선" 파드로 노드 여유 용량을 미리 확보 |
| `keda` | 파드 레벨 오토스케일링(backend/frontend replica 조절) |
| `alb-controller` | Gateway API/Ingress → ALB 연동 |
| `gateway-api` | Gateway API CRD + GatewayClass/Gateway/HTTPRoute |
| `argocd` | ArgoCD 설치 + Application 등록(`qKet/CD` 동기화) |
| `eso`, `eso-controller` | External Secrets Operator — Secrets Manager 값을 K8s Secret으로 동기화 |
| `metrics-server`, `monitoring`, `loki`, `promtail`, `alloy-faro`, `backend-servicemonitor` | 지표/로그 모니터링 스택(kube-prometheus-stack + Grafana) |
| `external-dns` | ALB 주소를 Route53에 자동 연결 |
| `dev-datastore` | release용 자체 호스팅 MySQL/Redis(StatefulSet) |
| `cluster-autoscaler` | 사용 중단됨(Karpenter로 대체, 과거 참고용) |

## 더 자세한 내용

설계 배경, 트러블슈팅, ADR은 `CLAUDE_LLM_WIKI` 레포를 참고하세요. 이전 버전 README는 `README.md.backup`에 남겨뒀습니다.
