# network/eks/bastion/alb-controller(공유 싱글턴)는 platform root가 소유.
# 여기서는 그 state를 읽기 전용으로 참조만 함 — vpc_id, subnet ids, eks 클러스터 정보, oidc, bastion sg 등.
data "terraform_remote_state" "platform" {
  backend = "s3"

  config = {
    bucket = "team5-qket-tfstate-727646470302"
    key    = "platform/terraform.tfstate"
    region = "ap-northeast-2"
  }
}
