# variables.rf
# platform 이 backend-s3에 올린 공개해둔 output값 불러오는 파일
data "terraform_remote_state" "platform" {
  backend = "s3"

  config = {
    bucket = "team5-qket-tfstate-727646470302"
    key    = "platform/terraform.tfstate"
    region = "ap-northeast-2"
  }
}
