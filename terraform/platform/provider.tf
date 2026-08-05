provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Team        = var.team_tag
      Environment = "shared" # network/eks는 release/prod가 공유하는 싱글턴이라 환경 구분이 없음
    }
  }
}
