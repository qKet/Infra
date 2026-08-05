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
