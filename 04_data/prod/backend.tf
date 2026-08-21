# prod 전용 root — 2026-08-21에 04_data(단일 root + terraform workspace)에서 분리됨. release와
# 대칭되는 이유로 여기 key는 "prod/data/terraform.tfstate"라는 새 이름을 씀 — 분리 시점 기준 이
# root가 한 번도 apply된 적이 없어서(S3에 이 state 자체가 존재하지 않았음) 옛 workspace 네이밍을
# 굳이 이어받을 이유가 없었음. release/backend.tf 상단 주석 참고.
terraform {
  backend "s3" {
    bucket       = "team5-qket-tfstate-727646470302"
    key          = "prod/data/terraform.tfstate"
    region       = "ap-northeast-2"
    encrypt      = true
    use_lockfile = true
  }
}
