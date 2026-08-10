variable "project_name" {
  description = "리소스 이름"
  type        = string
  default     = "team5-qket"
}

variable "team_tag" {
  description = "공통 팀 테그(필수)"
  type        = string
  default     = "team5"
}

variable "aws_region" {
  description = "리소스를 생성할 AWS 리전"
  type        = string
  default     = "ap-northeast-2"
}

/*******************
*     ECR
*******************/
variable "ecr_repository_name" {
  description = "backend/frontend 이미지를 담는 ECR 저장소 이름 — 기존 CI/IAM 정책과 이름을 맞춤"
  type        = string
  default     = "team5/ecr/qket"
}
