variable "admin_allowed_cidrs" {
  description = "grafana/argocd/dev 셋 다 공유하는 팀원 IP 허용목록 (기존 admin-ingress.tf의 local.admin_allowed_cidrs)"
  type        = list(string)
}

variable "grafana_hostname" {
  type    = string
  default = "grafana.jun979.click"
}

variable "grafana_certificate_arn" {
  description = "grafana 인증서 ARN — 03_registry가 만든 걸 호출부가 remote_state로 읽어서 넘김"
  type        = string
}

variable "argocd_hostname" {
  type    = string
  default = "cd.jun979.click"
}

variable "argocd_certificate_arn" {
  description = "argocd 인증서 ARN — 03_registry가 만든 걸 호출부가 remote_state로 읽어서 넘김"
  type        = string
}

variable "dev_hostname" {
  description = "release 환경 도메인 — local.ingress_config.release.host"
  type        = string
}

variable "dev_certificate_arn" {
  description = "release 환경 인증서 ARN — local.ingress_config.release.certificate_arn"
  type        = string
}
