# ElastiCache도 private-data 서브넷에만 배치.
# 보안그룹은 이 모듈이 만들지 않고 modules/security_group에서 받아옴(var.security_group_id).
resource "aws_elasticache_subnet_group" "this" {
  name       = "${var.project_name}-redis-subnet-group-${var.environment}"
  subnet_ids = var.private_data_subnet_ids
}

# 2026-08-18: aws_elasticache_cluster(단일 노드 전용 리소스)는 저장/전송 암호화 옵션을 아예
# 지원하지 않음(AWS API 자체의 제약 — 암호화는 replication_group API에만 있음) — 그래서
# aws_elasticache_replication_group으로 전환. num_cache_clusters=1이라 지금도 자동 페일오버는
# 없음(= SPOF 이슈는 아직 안 풀림, 별도 논의 필요) — 이번엔 암호화만 targeted로 해결.
#
# transit_encryption_enabled는 아직 안 켬 — 켜려면 백엔드의 spring.data.redis 설정에
# TLS(ssl.enabled=true)를 같이 넣어야 하는데 그건 이번 범위 밖. at_rest만 우선 적용.
#
# 주의: aws_elasticache_cluster -> aws_elasticache_replication_group은 리소스 타입 자체가
# 바뀌는 거라(주소가 달라짐) apply 시 기존 클러스터를 지우고 새로 만듦 — Redis가 세션
# 저장소(spring.session.store-type: redis)라 이 apply 순간 전체 로그인 세션이 끊김.
# 트래픽 적은 시간대에 계획해서 apply할 것 (RDS처럼 데이터 영구 손실은 아니고 재로그인만 필요).
resource "aws_elasticache_replication_group" "this" {
  replication_group_id = "${var.project_name}-redis-${var.environment}"
  description           = "${var.project_name} redis (${var.environment})"
  engine                = "redis"
  engine_version         = var.redis_engine_version
  node_type              = var.redis_node_type
  num_cache_clusters     = 1
  parameter_group_name   = "default.redis7"
  port                   = 6379

  at_rest_encryption_enabled = true
  transit_encryption_enabled = false # TODO: 백엔드 TLS 지원 추가 후 true로 전환

  subnet_group_name  = aws_elasticache_subnet_group.this.name
  security_group_ids = [var.security_group_id]
}
