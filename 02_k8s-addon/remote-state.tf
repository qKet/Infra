# 01_infrastructure가 backend-s3에 올린 공개해둔 output값(EKS 엔드포인트/CA/cluster_admin role 등) 불러오는 파일
data "terraform_remote_state" "infrastructure" {
  backend = "s3"

  config = {
    bucket = "team5-qket-tfstate-727646470302"
    key    = "infrastructure/terraform.tfstate"
    region = "ap-northeast-2"
  }
}

# 03_registry가 만든 ArgoCD 알림용 Gmail 시크릿 ARN을 읽어오기 위함
data "terraform_remote_state" "registry" {
  backend = "s3"

  config = {
    bucket = "team5-qket-tfstate-727646470302"
    key    = "registry/terraform.tfstate"
    region = "ap-northeast-2"
  }
}