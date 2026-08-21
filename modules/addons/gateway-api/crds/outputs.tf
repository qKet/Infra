output "release_name" {
  description = "gateway-api-crds Helm 릴리즈 이름"
  value       = helm_release.gateway_api_crds.name
}

output "release_status" {
  description = "gateway-api-crds Helm 릴리즈 상태"
  value       = helm_release.gateway_api_crds.status
}
