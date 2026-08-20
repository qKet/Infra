output "release_name" {
  description = "argocd-notifications-secrets Helm 릴리즈 이름"
  value       = helm_release.argocd_notifications_secrets.name
}
