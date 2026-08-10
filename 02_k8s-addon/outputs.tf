output "argocd_namespace" {
  description = "ArgoCD가 설치된 네임스페이스"
  value       = helm_release.argocd.namespace
}

output "qket_namespaces" {
  description = "생성된 qket-release/qket-prod 네임스페이스 이름 목록"
  value       = [for ns in kubernetes_namespace.qket : ns.metadata[0].name]
}
