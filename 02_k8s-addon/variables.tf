variable "aws_region" {
  description = "EKS get-token 호출 시 사용할 AWS 리전"
  type        = string
  default     = "ap-northeast-2"
}

variable "project_name" {
  description = "리소스 이름 접두사 — module.alb_controller가 IAM Role 이름 짓는 데 씀"
  type        = string
  default     = "team5-qket"
}
