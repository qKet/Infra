# ElastiCache도 private-data 서브넷에만 배치.
# 보안그룹은 이 모듈이 만들지 않고 modules/security_group에서 받아옴
resource "aws_elasticache_subnet_group" "this" {
  name       = "${var.project_name}-redis-subnet-group-${var.environment}"
  subnet_ids = var.private_data_subnet_ids
}

resource "aws_elasticache_replication_group" "this" {
  replication_group_id = "${var.project_name}-redis-${var.environment}"
  description           = "${var.project_name} redis (${var.environment})"
  engine                = "redis"
  engine_version         = var.redis_engine_version
  node_type              = var.redis_node_type
  num_cache_clusters     = var.num_cache_clusters
  parameter_group_name   = "default.redis7"
  port                   = 6379

  automatic_failover_enabled = var.automatic_failover_enabled
  multi_az_enabled           = var.multi_az_enabled

  at_rest_encryption_enabled = true
  transit_encryption_enabled = false # TODO: 백엔드 TLS 지원 추가 후 true로 전환

  subnet_group_name  = aws_elasticache_subnet_group.this.name
  security_group_ids = [var.security_group_id]
}
