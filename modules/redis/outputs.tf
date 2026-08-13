output "redis_endpoint" {
  description = "ElastiCache Redis 엔드포인트 (REDIS_HOST)"
  value       = aws_elasticache_cluster.this.cache_nodes[0].address
}

output "redis_port" {
  description = "ElastiCache Redis 포트 (REDIS_PORT)"
  value       = aws_elasticache_cluster.this.cache_nodes[0].port
}
