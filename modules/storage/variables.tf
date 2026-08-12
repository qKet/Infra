variable "project_name" {
  description = "리소스 이름 접두사"
  type        = string
}

variable "environment" {
  description = "환경 구분 (dev/prod)"
  type        = string
}

variable "namespace" {
  description = "백엔드 ServiceAccount/ConfigMap을 생성할 쿠버네티스 네임스페이스"
  type        = string
}

variable "oidc_provider_arn" {
  description = "IRSA용 OIDC 프로바이더 ARN (module.eks 출력값)"
  type        = string
}

variable "oidc_provider_url" {
  description = "IRSA용 OIDC 프로바이더 URL (module.eks 출력값)"
  type        = string
}

variable "force_destroy" {
  description = "버킷에 파일이 있어도 destroy 허용할지 — release는 true, prod는 false 권장"
  type        = bool
  default     = true
}

variable "cancel_alert_queue_arn" {
  description = "NOTI01_ALERT01(취소표 알림) SQS 큐 ARN — backend IRSA에 sqs:SendMessage 권한을 줄 때 씀 (modules/sqs.queue_arn)"
  type        = string
}
