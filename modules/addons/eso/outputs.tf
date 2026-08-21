output "connection_secret_arn" {
  description = "DB_HOST/REDIS_HOST를 담은 커스텀 Secrets Manager ARN — manage_db_redis_secrets=false면 null"
  value       = try(aws_secretsmanager_secret.connection[0].arn, null)
}
