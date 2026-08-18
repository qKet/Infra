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

/*******************
*     SES (예매 오픈 알림)
*******************/
variable "ses_domain" {
  description = "예매 오픈 알림 발신용 SES verify 도메인 — ECR/OIDC와 마찬가지로 release/prod 공용 싱글턴이라 여기 둠"
  type        = string
  default     = "jun979.click"
}

/*******************
*     ArgoCD Notifications (알림 이메일)
*******************/
variable "notification_gmail_username" {
  description = "ArgoCD 알림 발송용 Gmail 계정 — 최초 1회만 TF_VAR로 넘기면 됨(ignore_changes로 보호되어 이후 재적용 시 안 건드림)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "notification_gmail_app_password" {
  description = "위 Gmail 계정의 앱 비밀번호 — 최초 1회만 TF_VAR로 넘기면 됨"
  type        = string
  sensitive   = true
  default     = ""
}