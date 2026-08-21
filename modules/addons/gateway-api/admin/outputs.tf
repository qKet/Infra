output "release_name" {
  description = "gateway-api-admin Helm 릴리즈 이름"
  value       = helm_release.gateway_api_admin.name
}
