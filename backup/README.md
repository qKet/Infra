# backup/

Terraform으로 Helm 차트를 설치하던 부분을 여기로 옮겨뒀습니다. **사용 여부 보류 중** — ArgoCD 기반 CD로 갈지, Terraform이 계속 클러스터 애드온까지 관리할지 아직 결정 전입니다.

> ✅ 2026-08-10: **ALB Controller는 이미 재활성화되어 `02_k8s-addon`에 있습니다** (`module.alb_controller`, `../modules/alb-controller`) — 더 이상 여기 보류돼 있지 않습니다. 아래 내용은 **ESO(External Secrets Operator)에만** 해당합니다.

## 들어있는 것

- `modules/eso/` — External Secrets Operator용 IRSA + `helm_release` + SecretStore/ExternalSecret(`kubectl_manifest`)
- `kubernetes/` — 예전 raw manifest(namespace/ingress/networkpolicy/deploy) 백업. `CD` 레포가 Helm 차트로 바뀌면서 더 이상 안 씀.

## ⚠️ 2026-08-06 terraform 구조 재편으로 달라진 것

이 파일들을 백업할 당시엔 `platform`/`release`/`prod`가 디렉토리별 root였는데, 그 후 `release`/`prod`가 **`workload/` 단일 root + terraform workspace**로 통합됐습니다. 그래서:

- `release/eso.tf`는 없음 — 원래 `release` root에서 `module.eso_release`를 호출하던 파일이었지만, `release` 디렉토리 자체가 없어졌습니다.
- **ESO를 재활성화하려면 `04_data/eso.tf`를 새로 만들어야 합니다** — `04_data/rds.tf`/`04_data/redis.tf`가 하듯 `local.environment`(workspace 값)로 release/prod를 구분해서 `module "eso" { environment = local.environment ... }` 형태로 호출. `modules/eso`의 `variables.tf`가 받는 `environment`/`namespace`/`oidc_provider_arn` 등은 지금 `04_data/`의 `local.environment`, `kubernetes_namespace.this`, `data.terraform_remote_state.infrastructure.outputs.oidc_provider_*`로 그대로 대응됨.
- `04_data/versions.tf`에 helm/kubectl provider가 빠져있음 — ESO(`helm_release`+`kubectl_manifest`)를 쓰려면 다시 추가해야 함 (`versions.tf` required_providers + k8s-providers.tf에 provider 블록).

## root 이름/구조 (2026-08-10 기준)

`01_infrastructure`(순수 AWS) / `02_k8s-addon`(namespace/ArgoCD/ALB Controller 등 K8s addon) / `03_registry`(ECR/OIDC) / `04_data`(RDS/Redis/S3) — apply 순서를 그대로 드러내는 숫자 접두사가 붙어있습니다. S3 backend의 state key는 접두사 없이 깨끗한 이름(`infrastructure/terraform.tfstate` 등)을 그대로 씁니다.

## ⚠️ 재활성화 전 반드시 확인할 것

이 모듈이 **과거에 실제로 `terraform apply`된 적이 있다면**, 설정 없이 apply하면 Terraform이 해당 리소스(IAM Role, Helm 릴리스)를 상태(S3 backend)엔 남아있는데 설정엔 없는 것으로 보고 **삭제 대상으로 잡습니다.**

재활성화하려면:
1. `terraform state list`로 `module.eso_release.*`가 실제 상태에 남아있는지 먼저 확인
2. 남아있다면: 파일을 되돌리고 `terraform plan`으로 diff가 없는지(=기존 리소스와 정확히 일치하는지) 확인 후 적용
3. 이미 지워졌거나 처음부터 apply 안 된 상태였다면: 그냥 되돌리고 `terraform apply`

## ESO 재활성화하는 법 (구조가 바뀌어서 단순 mv로 안 됨)

```bash
cd Infra
mv backup/modules/eso modules/
# 04_data/eso.tf를 새로 작성 (위 "달라진 것" 참고)
# 04_data/versions.tf에 helm/kubectl required_providers 추가
# 04_data/k8s-providers.tf에 helm/kubectl provider 블록 추가 (02_k8s-addon/providers.tf의 kubernetes/helm provider 패턴 참고)
```

ESO도 kubernetes/helm provider를 쓰는 K8s addon 성격이지만, `qket-backend`용 다른 ServiceAccount/ConfigMap과 마찬가지로 `04_data`가 만든 RDS/Redis 값(`rds_master_user_secret_arn` 등)을 참조해야 해서 `02_k8s-addon`으로는 못 옮기고 `04_data`에 둬야 함 — [[architecture/terraform-platform-workload-split]]의 IRSA 관련 논의와 같은 이유(순환 의존).
