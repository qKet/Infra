# release 환경 전용 state (RDS/Redis/ESO/S3/네임스페이스 등 환경별 리소스).
# release 브랜치 push가 이 root에서만 apply를 돌리므로, main이 건드리는 prod state와 물리적으로 분리됨.
terraform {
  backend "s3" {
    bucket       = "team5-qket-tfstate-727646470302"
    key          = "release/terraform.tfstate"
    region       = "ap-northeast-2"
    encrypt      = true
    use_lockfile = true
  }
}
