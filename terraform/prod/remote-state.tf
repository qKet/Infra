data "terraform_remote_state" "platform" {
  backend = "s3"

  config = {
    bucket = "team5-qket-tfstate-727646470302"
    key    = "platform/terraform.tfstate"
    region = "ap-northeast-2"
  }
}
