output "redis_endpoint" {
  description = "ElastiCache Redis 엔드포인트 (REDIS_HOST) — replication_group의 primary endpoint"
  value       = aws_elasticache_replication_group.this.primary_endpoint_address
}

output "redis_port" {
  description = "ElastiCache Redis 포트 (REDIS_PORT)"
  value       = aws_elasticache_replication_group.this.port
}
