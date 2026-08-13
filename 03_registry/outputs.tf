output "ecr_repository_url" {
  description = "ECR 저장소 URI (CI가 docker push할 대상)"
  value       = module.ecr.repository_url
}

output "ecr_repository_name" {
  description = "ECR 저장소 이름"
  value       = module.ecr.repository_name
}

output "ecr_repository_arn" {
  description = "ECR 저장소 ARN"
  value       = module.ecr.repository_arn
}

output "github_actions_role_arns" {
  description = "GitHub Actions CI가 assume할 role ARN — 각 레포 GitHub Secrets(AWS_GITHUB_ACTIONS_ROLE_ARN)에 등록"
  value       = module.github_actions_oidc.role_arns
}
