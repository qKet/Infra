output "release_name" {
  description = "backend-servicemonitor Helm 릴리즈 이름"
  value       = helm_release.backend_servicemonitor.name
}
