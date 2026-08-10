# ECR + GitHub Actions OIDC 전용 state. platform과 마찬가지로 workspace 구분 없이
# 독립적으로(주로 수동으로) 적용 — release/prod가 공유하는 싱글턴 레이어라 workload처럼
# workspace별로 나뉘면 안 됨(나뉘면 release/prod가 같은 이름의 ECR 저장소를 각자 만들려다 충돌함).
terraform {
  backend "s3" {
    bucket       = "team5-qket-tfstate-727646470302"
    key          = "registry/terraform.tfstate"
    region       = "ap-northeast-2"
    encrypt      = true
    use_lockfile = true
  }
}
