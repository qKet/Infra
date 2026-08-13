# infrastructure(구 platform)가 backend-s3에 올린 공개해둔 output값 불러오는 파일
data "terraform_remote_state" "infrastructure" {
  backend = "s3"

  config = {
    bucket = "team5-qket-tfstate-727646470302"
    key    = "infrastructure/terraform.tfstate"
    region = "ap-northeast-2"
  }
}

# registry(SES identity)가 만든 output값 불러오는 파일 — modules/lambda의 ses:SendEmail 권한 범위를
# 정확히 그 identity ARN 하나로 좁히는 데 씀 (NOTI01_ALERT01)
data "terraform_remote_state" "registry" {
  backend = "s3"

  config = {
    bucket = "team5-qket-tfstate-727646470302"
    key    = "registry/terraform.tfstate"
    region = "ap-northeast-2"
  }
}
