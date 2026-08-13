# backend/frontend가 공유하는 단일 ECR 저장소. release/prod는 태그(backend-<sha> 등)로만 구분.
# platform과 마찬가지로 workspace 구분 없는 싱글턴 레이어 — workload(workspace별 state)에 두면
# release/prod가 같은 이름의 저장소를 각자 만들려다 충돌하므로 여기 별도 state로 둔다.
module "ecr" {
  source = "../modules/ecr"

  repository_name = var.ecr_repository_name
}

# Amazon Managed Prometheus(AMP) — 02_k8s-addon의 Prometheus가 수집한 지표를 EKS 클러스터
# 수명과 무관하게 영구 저장하는 곳. 원래 01_infrastructure에 뒀었는데(2026-08-12), 그 root도
# 매일 브랜치가 안 맞으면 orphan 리소스로 오인돼 지워질 수 있다는 걸 실제로 겪음(2026-08-13,
# 팀원이 이 코드 없는 main으로 apply해서 AMP 워크스페이스가 통째로 삭제됨). registry는 ECR처럼
# 완전히 독립적이고 수동으로만 apply하는 불변 싱글턴이라 이게 진짜 안전한 자리 — IRSA(쓰기 권한)는
# 02_k8s-addon의 Prometheus ServiceAccount 생명주기를 따라가야 해서 여기 안 두고 modules/addons/monitoring에 둠.
#
# 일반 EBS(PVC) 방식도 검토했으나 기각 — EKS를 destroy하면 PVC도 같이 삭제되고 StorageClass의
# ReclaimPolicy가 Delete라 EBS 볼륨도 함께 지워짐(Pod 재시작엔 강하지만 클러스터 재생성엔 무력).
resource "aws_prometheus_workspace" "this" {
  alias = "${var.project_name}-amp"
}

# GitHub Actions가 고정 키 없이 OIDC로 AWS(ECR push)에 접근하기 위한 IAM.
# backend/frontend 레포 각각 별도 role — 서로 다른 레포의 워크플로우가 남의 role을 못 씀.
module "github_actions_oidc" {
  source = "../modules/github-actions-oidc"

  project_name       = var.project_name
  ecr_repository_arn = module.ecr.repository_arn

  # qKet 조직의 불변 ID. `curl https://api.github.com/repos/qKet/backend`의 .owner.id로 확인.
  github_owner_id = "313320752"

  repos = {
    backend = {
      repo             = "qKet/backend"
      repository_id    = "1323850932" # curl https://api.github.com/repos/qKet/backend 의 .id
      allowed_branches = ["release", "main"]
    }
    frontend = {
      repo             = "qKet/frontend"
      repository_id    = "1323797216" # curl https://api.github.com/repos/qKet/frontend 의 .id
      allowed_branches = ["release", "main"]
    }
  }
}

# 예매 오픈 알림 발신 도메인. release/prod 구분 없는 도메인 단위 리소스라 ECR/OIDC와
# 같은 이유로 여기 둠(04_data는 workspace별로 두 번 생기는 구조라 안 맞음). 반드시 import 먼저 — modules/ses/main.tf 상단 주석 참고.
module "ses" {
  source = "../modules/ses"

  domain = var.ses_domain
}
