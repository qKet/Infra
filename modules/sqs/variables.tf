variable "project_name" {
  description = "리소스 이름 접두사"
  type        = string
}

variable "name" {
  description = "큐 용도를 나타내는 이름 — 리소스 이름에 project_name 다음으로 들어감 (예: open-alert, email-verification)"
  type        = string
}

variable "environment" {
  description = "release/prod — 04_data workspace 값 그대로 전달받음"
  type        = string
}

variable "visibility_timeout_seconds" {
  description = "Lambda 처리 시간보다 넉넉하게(Lambda timeout의 최소 6배를 AWS가 권장)"
  type        = number
  default     = 60
}
