variable "project_name" {
  description = "리소스 이름 접두사"
  type        = string
}

variable "environment" {
  description = "환경 구분 (release/prod)"
  type        = string
}

variable "aws_region" {
  description = "AWS 리전"
  type        = string
}

variable "namespace" {
  description = "큐 URL을 전달할 ConfigMap을 생성할 쿠버네티스 네임스페이스"
  type        = string
}

variable "from_email" {
  description = "SES 발신자 주소 — ses_domain에 속한 주소여야 함(예: noreply@jun979.click)"
  type        = string
}

variable "ses_domain" {
  description = "SES 발송에 쓸 인증된 도메인 — 실제 인증(aws_ses_domain_identity)은 03_registry에서 함"
  type        = string
  default     = "jun979.click"
}
