# ElastiCache도 private-data 서브넷에만 배치.
# 보안그룹은 이 모듈이 만들지 않고 modules/security_group에서 받아옴(var.security_group_id).
resource "aws_elasticache_subnet_group" "this" {
  name       = "${var.project_name}-redis-subnet-group-${var.environment}"
  subnet_ids = var.private_data_subnet_ids
}

# release는 싱글 노드(자동 페일오버 없음) — prod는 aws_elasticache_replication_group +
# num_cache_clusters>=2로 전환하는 게 정석이나, 지금은 environment 무관하게 단일 클러스터로 통일.
resource "aws_elasticache_cluster" "this" {
  cluster_id           = "${var.project_name}-redis-${var.environment}"
  engine               = "redis"
  engine_version       = var.redis_engine_version
  node_type            = var.redis_node_type
  num_cache_nodes      = 1
  parameter_group_name = "default.redis7"
  port                 = 6379

  subnet_group_name  = aws_elasticache_subnet_group.this.name
  security_group_ids = [var.security_group_id]
}
