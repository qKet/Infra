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

# 알림 "수신자"는 여기(Terraform 변수)가 아니라 Infra/argocd/qket-cd-app.yaml의
# notifications.argoproj.io/subscribe.* annotation에서 직접 관리함 — Application별로 수신자가
# 다를 수 있어서(qket-cd 말고 다른 Application이 생기면 그건 또 다른 사람이 받을 수도 있음)
# Terraform 변수보다 Application manifest에 두는 게 더 맞음.
