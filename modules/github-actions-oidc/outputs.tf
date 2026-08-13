output "role_arns" {
  description = "레포별 CI Role ARN — 각 레포의 GitHub Secrets(AWS_GITHUB_ACTIONS_ROLE_ARN)에 등록할 값"
  value       = { for k, r in aws_iam_role.ci : k => r.arn }
}

output "oidc_provider_arn" {
  description = "GitHub Actions OIDC Provider ARN"
  value       = aws_iam_openid_connect_provider.github.arn
}
