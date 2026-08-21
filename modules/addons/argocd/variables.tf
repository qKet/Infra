variable "aws_region" {
  description = "notifications-secrets(ESO)가 Secrets Manager를 조회할 AWS 리전"
  type        = string
}

variable "project_name" {
  description = "리소스 이름 접두사 — 관리자 비밀번호 미러링 시크릿 이름에 씀"
  type        = string
}

variable "argocd_notifications_secret_arn" {
  description = "ArgoCD 알림용 Gmail 자격증명이 담긴 Secrets Manager 시크릿 ARN (03_registry 출력값)"
  type        = string
}
