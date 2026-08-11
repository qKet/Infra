variable "project_name" {
  description = "리소스 이름 접두사"
  type        = string
}

variable "aws_region" {
  description = "AWS 리전"
  type        = string
}

variable "oidc_provider_arn" {
  description = "IRSA용 OIDC 프로바이더 ARN (infrastructure remote_state 출력값)"
  type        = string
}

variable "oidc_provider_url" {
  description = "IRSA용 OIDC 프로바이더 URL (infrastructure remote_state 출력값)"
  type        = string
}

variable "hosted_zone_id" {
  description = "ExternalDNS가 레코드를 쓸 수 있는 Route53 호스팅 존 ID — 공유 계정이라 이 존 하나로만 권한을 좁힘"
  type        = string
}

variable "domain_filter" {
  description = "ExternalDNS가 관리할 도메인 — hosted_zone_id랑 짝이 맞아야 함(IAM 스코프 + 이 필터, 이중으로 방어)"
  type        = string
}
