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

# monitoring 모듈(Grafana/Prometheus)처럼 클러스터에 하나만 두는 애드온이라
# release/prod별로 나누지 않음 — 로그도 한 Grafana 화면에서 같이 보는 게 목적.
variable "force_destroy" {
  description = "S3 버킷 안에 로그가 남아있어도 destroy를 허용할지 (release는 자주 재생성하니 true 권장, 로그는 재생성 가능한 데이터라 posters 버킷과 달리 true로 둬도 안전)"
  type        = bool
  default     = true
}
