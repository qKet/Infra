variable "project_name" {
  description = "리소스 이름 접두사"
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

variable "extra_secret_arns" {
  description = "이 root(02_k8s-addon) 안에서 ESO가 추가로 읽어야 하는 Secrets Manager ARN 목록 (예: ArgoCD 알림용 Gmail 시크릿)"
  type        = list(string)
  default     = []
}
