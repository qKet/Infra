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

# ── ArgoCD 알림(이메일) ──
# Gmail SMTP를 씀 — AWS SES와 달리 사용량 과금이 전혀 없어서(발송량도 하루 500건 한도로 충분) 완전 무료.
# username/app_password는 절대 기본값에 실제 값을 넣지 말 것 — 이 파일은 git에 커밋됨.
# 실행할 땐 환경변수로 주입: TF_VAR_notification_gmail_username=... TF_VAR_notification_gmail_app_password=...
# app_password는 Gmail 계정 설정 > 보안 > 2단계 인증 켠 뒤 "앱 비밀번호"에서 발급.
variable "notification_gmail_username" {
  description = "ArgoCD 알림 발송용 Gmail 계정 (SMTP 로그인 계정, 예: xxx@gmail.com)"
  type        = string
  sensitive   = true
}

variable "notification_gmail_app_password" {
  description = "위 Gmail 계정의 앱 비밀번호 (일반 로그인 비밀번호 아님, 앱 비밀번호로 발급받은 값)"
  type        = string
  sensitive   = true
}

# 알림 "수신자"는 여기(Terraform 변수)가 아니라 Infra/argocd/qket-cd-app.yaml의
# notifications.argoproj.io/subscribe.* annotation에서 직접 관리함 — Application별로 수신자가
# 다를 수 있어서(qket-cd 말고 다른 Application이 생기면 그건 또 다른 사람이 받을 수도 있음)
# Terraform 변수보다 Application manifest에 두는 게 더 맞음.
