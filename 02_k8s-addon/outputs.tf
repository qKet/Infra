output "argocd_namespace" {
  description = "ArgoCD가 설치된 네임스페이스"
  value       = module.argocd.namespace
}

output "qket_namespaces" {
  description = "생성된 qket-release/qket-prod 네임스페이스 이름 목록"
  value       = [for ns in kubernetes_namespace.qket : ns.metadata[0].name]
}

output "alb_controller_role_arn" {
  description = "ALB Controller IRSA IAM 역할 ARN"
  value       = module.alb_controller.role_arn
}

output "external_dns_role_arn" {
  description = "ExternalDNS IRSA IAM 역할 ARN"
  value       = module.external_dns.role_arn
}

output "grafana_role_arn" {
  description = "Grafana IRSA IAM 역할 ARN (CloudWatch 읽기 전용)"
  value       = module.monitoring.grafana_role_arn
}

output "eso_role_name" {
  description = "공유 ESO 컨트롤러 IRSA IAM 역할 이름 — 04_data(release/prod)의 module.eso가 여기에 정책을 추가로 붙일 때 씀"
  value       = module.eso_controller.role_name
}
