provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Team        = var.team_tag
      Environment = var.environment
    }
  }
}
