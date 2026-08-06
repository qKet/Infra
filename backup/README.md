# backup/

Terraform으로 Helm 차트를 설치하던 부분을 여기로 옮겨뒀습니다. **사용 여부 보류 중** — ArgoCD 기반 CD로 갈지, Terraform이 계속 클러스터 애드온까지 관리할지 아직 결정 전입니다.

## 들어있는 것

- `modules/alb-controller/` — AWS Load Balancer Controller용 IRSA + `helm_release`
- `modules/eso/` — External Secrets Operator용 IRSA + `helm_release` + SecretStore/ExternalSecret(`kubectl_manifest`)
- `platform/alb-controller.tf` — `platform` root에서 `module.alb_controller`를 호출하던 파일

## ⚠️ 2026-08-06 terraform 구조 재편으로 달라진 것

이 파일들을 백업할 당시엔 `platform`/`release`/`prod`가 디렉토리별 root였는데, 그 후 `release`/`prod`가 **`workload/` 단일 root + terraform workspace**로 통합됐습니다. 그래서:

- `release/eso.tf`는 없음 — 원래 `release` root에서 `module.eso_release`를 호출하던 파일이었지만, `release` 디렉토리 자체가 없어졌습니다.
- **ESO를 재활성화하려면 `workload/eso.tf`를 새로 만들어야 합니다** — `workload/rds.tf`/`workload/redis.tf`가 하듯 `local.environment`(workspace 값)로 release/prod를 구분해서 `module "eso" { environment = local.environment ... }` 형태로 호출. `modules/eso`의 `variables.tf`가 받는 `environment`/`namespace`/`oidc_provider_arn` 등은 지금 `workload/`의 `local.environment`, `kubernetes_namespace.this`, `data.terraform_remote_state.platform.outputs.oidc_provider_*`로 그대로 대응됨.
- `workload/versions.tf`에 helm/kubectl provider가 빠져있음 — ESO(`helm_release`+`kubectl_manifest`)를 쓰려면 다시 추가해야 함 (`versions.tf` required_providers + k8s-providers.tf에 provider 블록).

## 옮기면서 같이 손댄 것

원래 자리에서 이 모듈들을 참조하던 output도 깨지지 않게 주석 처리해뒀습니다:

- `platform/outputs.tf` — `alb_controller_role_arn` output (아직 유효)

`terraform validate`로 `platform`/`workload` 둘 다 정상 통과 확인함 (2026-08-06, terraform 구조 재편 이후 기준).

## ⚠️ 재활성화 전 반드시 확인할 것

이 모듈들이 **과거에 실제로 `terraform apply`된 적이 있다면**, 설정 없이 apply하면 Terraform이 해당 리소스(IAM Role, Helm 릴리스)를 상태(S3 backend)엔 남아있는데 설정엔 없는 것으로 보고 **삭제 대상으로 잡습니다.**

재활성화하려면:
1. `terraform state list`로 `module.alb_controller.*` / `module.eso_release.*`가 실제 상태에 남아있는지 먼저 확인
2. 남아있다면: 파일을 되돌리고 `terraform plan`으로 diff가 없는지(=기존 리소스와 정확히 일치하는지) 확인 후 적용
3. 이미 지워졌거나 처음부터 apply 안 된 상태였다면: 그냥 되돌리고 `terraform apply`

## ALB Controller 원래 위치로 되돌리는 법

```bash
cd Infra/terraform
mv backup/modules/alb-controller modules/
mv backup/platform/alb-controller.tf platform/
# platform/outputs.tf에서 주석 처리된 alb_controller_role_arn output 주석 해제
```

## ESO 재활성화하는 법 (구조가 바뀌어서 단순 mv로 안 됨)

```bash
cd Infra/terraform
mv backup/modules/eso modules/
# workload/eso.tf를 새로 작성 (위 "달라진 것" 참고)
# workload/versions.tf에 helm/kubectl required_providers 추가
# workload/k8s-providers.tf에 helm/kubectl provider 블록 추가 (platform/k8s-providers.tf 참고)
```
