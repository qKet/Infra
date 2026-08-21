# release 전용 root — 2026-08-21에 04_data(단일 root + terraform workspace)에서 분리됨
# ([[../../../CLAUDE_LLM_WIKI/wiki/decisions/2026-08-21-...]] 참고, release가 RDS/ElastiCache 대신
# dev-datastore StatefulSet을 쓰게 되면서 prod와 구조 자체가 달라져 workspace+삼항식으로 억지로
# 합쳐두는 것보다 아예 디렉토리를 나누는 게 낫다고 판단함).
#
# key가 "env:/release/..."라는 옛 workspace 네이밍 그대로인 이유: 분리 전 이 값이 실제로 살아있던
# release RDS/ElastiCache 등 상태가 저장된 바로 그 S3 키라서, 여기만 그대로 유지해야 상태 이전
# 없이(=terraform state mv/import 없이) 기존 리소스를 그대로 이어받음. prod는 이 root가 한 번도
# apply된 적이 없어서(2026-08-21 확인, S3에 env:/prod/data/terraform.tfstate 자체가 없었음) 새
# 이름(prod/backend.tf 참고)을 씀 — 두 키 이름 형식이 다른 건 의도된 비대칭.
terraform {
  backend "s3" {
    bucket       = "team5-qket-tfstate-727646470302"
    key          = "env:/release/data/terraform.tfstate"
    region       = "ap-northeast-2"
    encrypt      = true
    use_lockfile = true
  }
}
