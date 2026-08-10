# 공유 싱글턴 레이어(network/eks/bastion/alb-controller) 전용 state.
# release/prod가 이 레이어의 output을 terraform_remote_state로 읽어가므로,
# 이 root는 release/main 어느 쪽 apply와도 무관하게 독립적으로(주로 수동으로) 적용함.
terraform {
  backend "s3" {
    bucket       = "team5-qket-tfstate-727646470302"
    key          = "infrastructure/terraform.tfstate"
    region       = "ap-northeast-2"
    encrypt      = true
    use_lockfile = true
  }
}
