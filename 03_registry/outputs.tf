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

output "ses_identity_arn" {
  description = "예매 오픈 알림 발신 도메인 identity ARN — 04_data가 remote_state로 읽어서 Lambda 발송 권한에 씀"
  value       = module.ses.identity_arn
}
