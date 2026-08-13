variable "project_name" {
  description = "리소스 이름 접두사"
  type        = string
}

variable "environment" {
  description = "release/prod — 04_data workspace 값 그대로 전달받음"
  type        = string
}

variable "source_dir" {
  description = "Lambda 소스 디렉토리 절대/상대경로 — apply 전에 여기서 npm install --production 완료돼 있어야 함"
  type        = string
}

variable "queue_arn" {
  description = "이 Lambda가 구독할 SQS 큐 ARN"
  type        = string
}

variable "ses_domain" {
  description = "SES SendEmail 권한을 줄 도메인 — 03_registry/ses.tf가 인증해둔 도메인이어야 함 (예: jun979.click)"
  type        = string
}

variable "from_email" {
  description = "발신자 이메일 주소 (SES identity 도메인 소속이어야 함, 예: noreply@jun979.click)"
  type        = string
}
