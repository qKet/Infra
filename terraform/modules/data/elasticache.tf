# ElastiCache도 private-data 서브넷에만 배치
resource "aws_elasticache_subnet_group" "this" {
  name       = "${var.project_name}-redis-subnet-group-${var.environment}"
  subnet_ids = var.private_data_subnet_ids
}

# EKS 노드/파드, SSM bastion에서만 6379로 접속 허용
resource "aws_security_group" "redis" {
  name_prefix = "${var.project_name}-redis-${var.environment}-"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Redis from EKS nodes/pods"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [var.eks_cluster_security_group_id]
  }

  ingress {
    description     = "Redis from SSM bastion"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [var.bastion_security_group_id]
  }

  tags = {
    Name = "${var.project_name}-redis-${var.environment}-sg"
  }
}

# dev는 싱글 노드(자동 페일오버 없음) — prod 만들 때 aws_elasticache_replication_group + num_cache_clusters>=2 로 전환
resource "aws_elasticache_cluster" "this" {
  cluster_id           = "${var.project_name}-redis-${var.environment}"
  engine               = "redis"
  engine_version       = var.redis_engine_version
  node_type            = var.redis_node_type
  num_cache_nodes      = 1
  parameter_group_name = "default.redis7"
  port                 = 6379

  subnet_group_name  = aws_elasticache_subnet_group.this.name
  security_group_ids = [aws_security_group.redis.id]
}
