variable "project_name" {
  description = "리소스 이름 접두사"
  type        = string
}

variable "aws_region" {
  description = "AWS 리전"
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

variable "amp_remote_write_endpoint" {
  description = "Prometheus가 원격 저장할 Amazon Managed Prometheus(AMP) remote_write 엔드포인트 (03_registry 출력값)"
  type        = string
}

variable "amp_workspace_arn" {
  description = "AMP workspace ARN — Prometheus의 aps:RemoteWrite, Grafana의 aps:QueryMetrics 등 권한 정책 리소스 스코핑에 사용 (03_registry 출력값)"
  type        = string
}

variable "amp_query_endpoint" {
  description = "Grafana가 AMP를 Prometheus 호환 데이터소스로 조회할 엔드포인트 (03_registry 출력값)"
  type        = string
}
