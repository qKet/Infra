# VPC/서브넷/보안그룹 전용 state — 전부 무료 리소스라 영구 보존. 03_registry와 같은 성격의
# 싱글턴 root. 01_infrastructure에서 분리 — 덕분에 01_infrastructure는 통째로 destroy해도 안전.
terraform {
  backend "s3" {
    bucket       = "team5-qket-tfstate-727646470302"
    key          = "network/terraform.tfstate"
    region       = "ap-northeast-2"
    encrypt      = true
    use_lockfile = true
  }
}
