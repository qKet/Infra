output "mysql_service" {
  description = "클러스터 내부에서 MySQL에 붙을 때 쓰는 호스트명"
  value       = "${kubernetes_service.mysql.metadata[0].name}.${var.namespace}.svc.cluster.local"
}

output "redis_service" {
  description = "클러스터 내부에서 Redis에 붙을 때 쓰는 호스트명"
  value       = "${kubernetes_service.redis.metadata[0].name}.${var.namespace}.svc.cluster.local"
}
