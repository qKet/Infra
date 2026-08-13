# backend/frontend가 공유하는 단일 ECR 저장소. release/prod는 태그(backend-<sha> 등)로만 구분.
# platform과 마찬가지로 workspace 구분 없는 싱글턴 레이어 — workload(workspace별 state)에 두면
# release/prod가 같은 이름의 저장소를 각자 만들려다 충돌하므로 여기 별도 state로 둔다.
module "ecr" {
  source = "../modules/addons/ecr"

  repository_name = var.ecr_repository_name
}

# GitHub Actions가 고정 키 없이 OIDC로 AWS(ECR push)에 접근하기 위한 IAM.
# backend/frontend 레포 각각 별도 role — 서로 다른 레포의 워크플로우가 남의 role을 못 씀.
module "github_actions_oidc" {
  source = "../modules/addons/github-actions-oidc"

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
