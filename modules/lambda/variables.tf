variable "project_name" {
  description = "리소스 이름 접두사"
  type        = string
}

variable "name" {
  description = "Lambda 용도를 나타내는 이름 — 리소스 이름에 project_name 다음으로 들어감 (예: open-alert-mailer, email-verification)"
  type        = string
}

variable "runtime" {
  description = "Lambda 런타임 — nodejs22.x는 aws-sdk(SES 클라이언트 포함)가 기본 번들되어 있어 그대로 배포 가능. nodejs20.x 이하로 내리면 source_dir에 node_modules를 직접 담아야 함"
  type        = string
  default     = "nodejs22.x"
}

variable "timeout" {
  description = "Lambda 타임아웃(초)"
  type        = number
  default     = 10
}

variable "batch_size" {
  description = "SQS 이벤트소스 매핑 배치 크기"
  type        = number
  default     = 10
}

variable "report_batch_item_failures" {
  description = "배치 부분 실패 재시도(ReportBatchItemFailures) 사용 여부 — 핸들러가 { batchItemFailures } 형태로 응답해야 함"
  type        = bool
  default     = true
}

variable "environment" {
  description = "release/prod — 04_data 값 그대로 전달받음"
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
  description = "발신자 이메일 주소 — 03_registry/ses.tf가 인증해둔 도메인 소속이어야 함(예: noreply@jun979.click). SES SendEmail 권한을 도메인 ARN·발신주소 ARN 둘 다 기준으로 부여함(모듈 main.tf 주석 참고)"
  type        = string
}
