# Infra

Qket 인프라의 Terraform 코드. root(디렉토리)는 apply 순서를 그대로 드러내는 숫자 접두사로 정렬돼 있다.

```
00_network/            VPC, 서브넷, 보안그룹 — 전부 무료 리소스, 절대 안 지움(03_registry와 같은 성격)
01_infrastructure/   EKS, bastion, NAT Gateway — 비용이 나가는 것만 남음, 순수 AWS API 리소스
02_k8s-addon/         namespace, ArgoCD — kubernetes/helm provider로 EKS 위에 배포
03_registry/          ECR, github-actions-oidc — 공유·불변, env 안 나뉨, 절대 안 지움
04_data/               RDS, Redis, S3(포스터) — release/prod workspace로 분리, 절대 안 지움
```

> `00_network`는 2026-08-13에 `01_infrastructure`에서 분리됨 — VPC/서브넷/보안그룹은 AWS 요금이 안 붙는 무료 리소스라 매일 밤 destroy할 이유가 없었고, 오히려 밤 시간대에 값이 없어서 `-refresh-only`가 깨지는 원인만 됐음. 이제 `01_infrastructure`는 `-target` 없이 통째로 destroy해도 안전함.

ArgoCD Application(`qket-cd`, `qKet/CD` 레포의 `helm` 경로를 `qket-release` 네임스페이스로 동기화)은 2026-08-13부터 `02_k8s-addon/argocd-apps.tf`가 `kubectl_manifest`로 직접 만든다 — `02_k8s-addon` apply 한 번으로 ArgoCD 설치 + Application 등록까지 끝남. 예전엔 `argocd/qket-cd-app.yaml`을 사람이 매번 `kubectl apply`해야 했는데(02_k8s-addon이 매일 밤 destroy될 때 Application 등록도 같이 사라져서), 이제 그럴 필요 없음. sync는 여전히 수동(ArgoCD UI에서 Sync 버튼) — automated(prune/selfHeal)는 일부러 안 켬.

## 최초 적용 순서

```bash
cd 00_network && terraform init
cd 00_network && terraform apply

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

`01_infrastructure`(EKS/bastion/NAT)는 비용 때문에 매일 껐다 켠다. `00_network`(VPC/서브넷/보안그룹)는 떠있어도 과금되지 않는 데다 아예 별도 root로 분리돼서 **이 과정에서 전혀 손대지 않는다** — `03_registry`(ECR/OIDC)와 마찬가지로 최초 1회 적용 이후로는 다시 볼 일이 없다. `04_data`(RDS/Redis/S3 등 실제 AWS 리소스)는 SG를 bastion SG ID가 아니라 서브넷 CIDR로만 참조하도록 되어 있어서 전혀 영향받지 않는다.

> ⚠️ **`01_infrastructure`를 절대 `-target` 없이 plain `terraform destroy`로 지우지 말 것.** 이 root에 팀원이 아직 로컬에 없는 브랜치(예: 모니터링/AMP 관련 코드)의 리소스가 이미 배포돼 있는 상태에서 target 없이 destroy하면, 로컬 `.tf`에 없다는 이유로 **그 리소스까지 통째로 날아간다** — 특히 AMP(Amazon Managed Prometheus) workspace가 여기 해당되면 그동안 쌓인 지표 이력이 영구 삭제된다. 반드시 아래처럼 지울 리소스를 `-target`으로 명시할 것.

**순서가 중요하다** — `02_k8s-addon`(ArgoCD/namespace)을 EKS Access Entry가 아직 살아있을 때 먼저 지워야 한다. 순서를 안 지키면 `Unauthorized` 에러가 난다(자세한 원인: `troubleshooting/eks-destroy-layer-separation.md`).

> ⚠️ **아침에 `04_data`도 다시 apply해야 한다.** `04_data`의 실제 AWS 리소스(RDS/Redis/S3)는 밤새 안 지워지지만, `04_data`가 그 안에 만들어둔 K8s 오브젝트(`kubernetes_service_account.backend`(IRSA), `kubernetes_config_map.app_config`/`storage-config`)는 **부모인 네임스페이스가 `02_k8s-addon` destroy로 지워지면 Kubernetes가 자동으로 같이 지워버린다**(cascade delete) — Terraform이 `04_data`를 직접 건드린 게 아니어도 `04_data`의 state와 실제 상태가 어긋나게 됨(drift). 다행히 `terraform apply`는 refresh를 먼저 하므로 RDS/Redis는 안 건드리고 사라진 K8s 오브젝트 3개만 다시 만들어준다 — 비용/위험 없는 몇 초짜리 작업.

### 저녁 — 끄기

```bash
# 1. k8s-addon 전체 destroy (EKS가 아직 살아있을 때)
cd 02_k8s-addon && terraform destroy

# 2. infrastructure destroy — 00_network로 옮겨간 vpc/subnet/security_group은
#    이 root에 아예 없으니(-target 목록에서도 뺌) 신경 쓸 필요 없음.
#    라우팅 테이블(aws_route_table.*)은 -target으로 명시 안 해도 nat_gateway를 참조하고
#    있어서 destroy 시 자동으로 같이 정리됨(Terraform이 의존관계를 따라감).
cd 01_infrastructure && terraform destroy \
  -target=module.eks \
  -target=module.ec2 \
  -target=aws_nat_gateway.this \
  -target=aws_eip.nat
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
