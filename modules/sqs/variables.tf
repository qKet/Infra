variable "project_name" {
  description = "리소스 이름 접두사"
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
