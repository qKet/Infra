# Infra

Qket 인프라의 Terraform 코드. root(디렉토리)는 apply 순서를 그대로 드러내는 숫자 접두사로 정렬돼 있다.

```
01_infrastructure/   VPC, EKS, bastion — 순수 AWS API 리소스만
02_k8s-addon/         namespace, ArgoCD — kubernetes/helm provider로 EKS 위에 배포
03_registry/          ECR, github-actions-oidc — 공유·불변, env 안 나뉨, 절대 안 지움
04_data/               RDS, Redis, S3(포스터) — release/prod workspace로 분리, 절대 안 지움
```

`argocd/qket-cd-app.yaml`은 Terraform root가 아니라 ArgoCD Application 매니페스트 — `qKet/CD` 레포의 `release` 경로를 `qket-release` 네임스페이스로 동기화하는 정의. `02_k8s-addon`이 설치한 ArgoCD가 뜬 뒤 이 매니페스트를 `kubectl apply`(또는 App-of-Apps로) 등록하면 됨.

## 최초 적용 순서

```bash
cd 01_infrastructure && terraform init
cd 01_infrastructure && terraform apply

cd 02_k8s-addon && terraform init
cd 02_k8s-addon && terraform apply

# ECR/github-actions-oidc는 EKS/네임스페이스와 의존관계가 없어서 순서상 꼭 여기일 필요는 없고,
# 그냥 숫자 접두사 순서에 맞춰서 여기 둠 — 다른 root보다 먼저 apply해도 무방.
cd 03_registry && terraform init
cd 03_registry && terraform apply

cd 04_data && terraform init
cd 04_data && terraform workspace new release   # 최초 1회
cd 04_data && terraform workspace new prod      # 최초 1회
cd 04_data && terraform workspace select release
cd 04_data && terraform apply
cd 04_data && terraform workspace select prod
cd 04_data && terraform apply
```

자세한 이유/주의사항은 CLAUDE_LLM_WIKI의 `runbook/terraform-apply-order.md` 참고.

## 매일 아침/저녁 — `01_infrastructure`/`02_k8s-addon` 켜고 끄기

`01_infrastructure`(EKS/bastion/NAT)는 비용 때문에 매일 껐다 켠다. **VPC/서브넷/라우팅테이블은 떠있어도 과금되지 않으므로 안 지운다** — 지우는 건 실제로 비용이 나가는 리소스(EKS, bastion EC2, NAT Gateway)뿐이다. `03_registry`(ECR/OIDC)는 애초에 별도 root라 이 과정과 무관하고, `04_data`(RDS/Redis/S3 등 실제 AWS 리소스)는 SG를 bastion SG ID가 아니라 서브넷 CIDR로만 참조하도록 되어 있어서 전혀 영향받지 않는다.

**순서가 중요하다** — `02_k8s-addon`(ArgoCD/namespace)을 EKS Access Entry가 아직 살아있을 때 먼저 지워야 한다. 순서를 안 지키면 `Unauthorized` 에러가 난다(자세한 원인: `troubleshooting/eks-destroy-layer-separation.md`).

> ⚠️ **아침에 `04_data`도 다시 apply해야 한다.** `04_data`의 실제 AWS 리소스(RDS/Redis/S3)는 밤새 안 지워지지만, `04_data`가 그 안에 만들어둔 K8s 오브젝트(`kubernetes_service_account.backend`(IRSA), `kubernetes_config_map.app_config`/`storage-config`)는 **부모인 네임스페이스가 `02_k8s-addon` destroy로 지워지면 Kubernetes가 자동으로 같이 지워버린다**(cascade delete) — Terraform이 `04_data`를 직접 건드린 게 아니어도 `04_data`의 state와 실제 상태가 어긋나게 됨(drift). 다행히 `terraform apply`는 refresh를 먼저 하므로 RDS/Redis는 안 건드리고 사라진 K8s 오브젝트 3개만 다시 만들어준다 — 비용/위험 없는 몇 초짜리 작업.

### 저녁 — 끄기

```bash
# 1. k8s-addon 전체 destroy (EKS가 아직 살아있을 때)
cd 02_k8s-addon && terraform destroy

# 2. infrastructure에서 비용 나가는 리소스만 targeted destroy
#    (VPC/서브넷/라우팅은 손대지 않음)
cd 01_infrastructure && terraform destroy \
  -target=module.eks \
  -target=module.ec2 \
  -target=aws_nat_gateway.this \
  -target=aws_eip.nat \
  -target=module.security_group
```

### 아침 — 켜기

```bash
# 1. infrastructure apply (지워졌던 EKS/bastion/NAT 재생성)
cd 01_infrastructure && terraform apply

# 2. k8s-addon apply (namespace, ArgoCD 재생성)
cd 02_k8s-addon && terraform apply

# 3. data도 다시 apply — RDS/Redis는 안 건드리고, 네임스페이스가 새로 생기면서
#    같이 사라졌던 ServiceAccount(qket-backend, IRSA)/ConfigMap만 다시 채워짐
cd 04_data && terraform workspace select release && terraform apply
cd 04_data && terraform workspace select prod && terraform apply
```

## 참고

이 저장소의 설계 배경(왜 이렇게 나눴는지, 겪었던 문제들)은 `CLAUDE_LLM_WIKI` 레포의 아래 문서에 정리돼 있다:

- `wiki/architecture/terraform-platform-workload-split.md`
- `wiki/architecture/terraform-module-boundaries.md`
- `wiki/architecture/terraform-remote-state.md`
- `wiki/troubleshooting/eks-provider-auth.md`
- `wiki/troubleshooting/eks-destroy-layer-separation.md`
- `wiki/runbook/terraform-apply-order.md`
- `wiki/runbook/daily-infrastructure-toggle.md`
