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

variable "roles" {
  description = <<-EOT
    생성할 IRSA Role 정의 맵. key가 이름 suffix(예: "backend", "alb-controller").
    각 Role은 특정 네임스페이스의 특정 ServiceAccount만 assume할 수 있게 제한됨.

    이 모듈은 IAM Role만 만들고 쿠버네티스 ServiceAccount는 만들지 않는다 — Helm 차트가
    자체적으로 SA를 만드는 애드온(annotation만 role_arn으로 넘기면 됨)과, Terraform이
    직접 SA를 만들어야 하는 경우(예: 앱 자체 백엔드)가 섞여있어서, SA 생성은 호출부 책임으로 둔다.
  EOT
  type = map(object({
    namespace       = string
    service_account = string
    policy_json     = string
  }))
}
