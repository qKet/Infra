# 01_infrastructure가 backend-s3에 올린 공개해둔 output값(EKS 엔드포인트/CA/cluster_admin role 등) 불러오는 파일
data "terraform_remote_state" "infrastructure" {
  backend = "s3"

  config = {
    bucket = "team5-qket-tfstate-727646470302"
    key    = "infrastructure/terraform.tfstate"
    region = "ap-northeast-2"
  }
}

# AMP(Amazon Managed Prometheus) 워크스페이스 정보 — 03_registry에 있음(2026-08-13, 01_infrastructure에서
# 이전됨. 이유: registry는 완전히 불변·수동 apply되는 싱글턴이라 AMP처럼 절대 안 지워져야 하는 리소스에 안전함).
data "terraform_remote_state" "registry" {
  backend = "s3"

  config = {
    bucket = "team5-qket-tfstate-727646470302"
    key    = "registry/terraform.tfstate"
    region = "ap-northeast-2"
  }
}
