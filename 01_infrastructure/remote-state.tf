# 00_network(vpc/subnet/security_group, 영구 root)가 backend-s3에 올려둔 output값을 읽어옴.
# 2026-08-13: 이 root에서 vpc/subnet/security_group을 분리하면서 신설 — 자세한 배경은
# 00_network/backend.tf 주석 참고.
data "terraform_remote_state" "network" {
  backend = "s3"

  config = {
    bucket = "team5-qket-tfstate-727646470302"
    key    = "network/terraform.tfstate"
    region = "ap-northeast-2"
  }
}
