variable "pilot_enabled" {
  description = "이 환경의 Gateway/HTTPRoute 등 오브젝트 생성 여부 — 검증 끝나면 false로 끄고 정리 가능"
  type        = bool
  default     = true
}

variable "env" {
  description = "release/prod 같은 환경 키 — Helm 릴리즈 이름을 env별로 유일하게 만드는 데만 씀 (02_k8s-addon/main.tf에서 for_each로 이 모듈을 env별로 인스턴스화)"
  type        = string
}

variable "namespace" {
  description = "Gateway/HTTPRoute 등을 만들 네임스페이스 (qket-release/qket-prod)"
  type        = string
}

variable "hostname" {
  description = "이 Gateway가 서빙할 실제 도메인(예: dev.jun979.click) — local.ingress_config에서 가져와 전달"
  type        = string
}

variable "certificate_arn" {
  description = "HTTPS 리스너용 ACM 인증서 ARN. 빈 문자열이면 TLS 없이 HTTP:80만 뜬다(1단계 파일럿처럼 테스트용)."
  type        = string
  default     = ""
}

variable "load_balancer_name" {
  description = "이 Gateway가 만들 ALB 이름 — 기존 Ingress가 쓰는 team5-qket-alb와 겹치면 안 됨(Gateway API는 별도 ALB로 뜸)"
  type        = string
}
