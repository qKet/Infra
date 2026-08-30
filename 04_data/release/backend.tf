# release 전용 root — 04_data(단일 root + workspace)에서 디렉토리로 분리됨.
# key가 옛 workspace 네이밍("env:/release/...") 그대로인 이유: 분리 전 실제 상태가 저장된 그
# S3 키라서, state mv 없이 기존 리소스를 이어받으려고 유지함. prod는 새 이름(prod/backend.tf)을
# 씀 — 두 키 이름 형식이 다른 건 의도된 비대칭.
terraform {
  backend "s3" {
    bucket       = "team5-qket-tfstate-727646470302"
    key          = "env:/release/data/terraform.tfstate"
    region       = "ap-northeast-2"
    encrypt      = true
    use_lockfile = true
  }
}
