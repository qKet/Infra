variable "repository_name" {
  description = "ECR 저장소 이름"
  type        = string
}

variable "image_tag_mutability" {
  description = "이미지 태그 변경 가능 여부 (MUTABLE/IMMUTABLE)"
  type        = string
  default     = "MUTABLE"
}

variable "scan_on_push" {
  description = "push 시 자동 취약점 스캔 여부"
  type        = bool
  default     = false
}

variable "untagged_expire_days" {
  description = "태그 없는 이미지를 며칠 후 만료시킬지"
  type        = number
  default     = 7
}
