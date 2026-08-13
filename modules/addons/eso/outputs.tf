output "role_arn" {
  description = "External Secrets Operator IRSA IAM 역할 ARN"
  value       = aws_iam_role.eso.arn
}

output "connection_secret_arn" {
  description = "DB_HOST/REDIS_HOST를 담은 커스텀 Secrets Manager ARN"
  value       = aws_secretsmanager_secret.connection.arn
}
