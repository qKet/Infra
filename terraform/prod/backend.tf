# prod 환경 전용 state — release와 완전히 분리된 state라, main push의 apply가
# release가 건드리는 리소스를 절대 건드릴 수 없음.
terraform {
  backend "s3" {
    bucket       = "team5-qket-tfstate-727646470302"
    key          = "prod/terraform.tfstate"
    region       = "ap-northeast-2"
    encrypt      = true
    use_lockfile = true
  }
}
