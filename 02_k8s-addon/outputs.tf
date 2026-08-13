output "argocd_namespace" {
  description = "ArgoCD가 설치된 네임스페이스"
  value       = helm_release.argocd.namespace
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
