output "namespace" {
  description = "ArgoCD가 설치된 네임스페이스"
  value       = helm_release.this.namespace
}
