# release/prod 공용 root — terraform workspace로 환경을 나눈다 (default 워크스페이스는 안 씀).
# S3 backend + workspace 조합이면 state key가 자동으로 "env:/<workspace>/data/terraform.tfstate"로
# 나뉘어서, release/prod가 물리적으로 완전히 다른 state 파일에 저장됨 (여기 key는 그 접두사 뒤에 붙는 부분).
terraform {
  backend "s3" {
    bucket       = "team5-qket-tfstate-727646470302"
    key          = "data/terraform.tfstate"
    region       = "ap-northeast-2"
    encrypt      = true
    use_lockfile = true
  }
}
