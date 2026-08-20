variable "aws_region" {
  description = "SecretStore가 Secrets Manager를 조회할 AWS 리전"
  type        = string
}

variable "secret_arn" {
  description = "ArgoCD 알림용 Gmail 자격증명이 담긴 Secrets Manager 시크릿 ARN (03_registry 출력값)"
  type        = string
}
