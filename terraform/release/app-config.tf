# DB_PORT/DB_NAME/REDIS_PORT/AWS_REGION — 전부 사람이 GitHub Variables에 따로 입력할 필요 없이
# 이미 Terraform이 RDS/ElastiCache를 만들 때 알고 있는 값이라 직접 ConfigMap으로 관리.
resource "kubernetes_config_map" "app_config_release" {
  metadata {
    name      = "app-config"
    namespace = kubernetes_namespace.qket_release.metadata[0].name
  }

  data = {
    DB_PORT    = tostring(module.data_release.rds_port)
    DB_NAME    = module.data_release.rds_db_name
    REDIS_PORT = tostring(module.data_release.redis_port)
    AWS_REGION = var.aws_region
  }
}
