output "rds_endpoint" {
  description = "RDS 엔드포인트 (DB_HOST)"
  value       = aws_db_instance.this.address
}

output "rds_port" {
  description = "RDS 포트 (DB_PORT)"
  value       = aws_db_instance.this.port
}

output "rds_db_name" {
  description = "RDS 데이터베이스 이름 (DB_NAME)"
  value       = aws_db_instance.this.db_name
}

output "rds_master_user_secret_arn" {
  description = "RDS 마스터 비밀번호가 저장된 Secrets Manager ARN"
  value       = aws_db_instance.this.master_user_secret[0].secret_arn
}
