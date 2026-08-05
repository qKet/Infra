# prod용 RDS/Redis/ESO/S3 — 아직 실제로 켜지 않음(release 검증 끝나면 이 주석을 풀 것).
# environment만 "prod"로 다르고 나머지는 release root(../release)와 완전히 같은 모양.
# network/eks는 platform root(../platform)를 공유해서 씀 — data.terraform_remote_state.platform 참조.

# module "data_prod" {
#   source = "../modules/data"
#
#   project_name = var.project_name
#   environment  = "prod"
#
#   vpc_id                        = data.terraform_remote_state.platform.outputs.vpc_id
#   private_data_subnet_ids       = data.terraform_remote_state.platform.outputs.private_data_subnet_ids
#   eks_cluster_security_group_id = data.terraform_remote_state.platform.outputs.eks_cluster_security_group_id
#   bastion_security_group_id     = data.terraform_remote_state.platform.outputs.bastion_security_group_id
#
#   db_name                  = var.db_name
#   db_username              = var.db_username
#   db_instance_class        = var.db_instance_class
#   db_allocated_storage     = var.db_allocated_storage
#   db_max_allocated_storage = var.db_max_allocated_storage
#
#   redis_node_type      = var.redis_node_type
#   redis_engine_version = var.redis_engine_version
# }
#
# module "eso_prod" {
#   source = "../modules/eso"
#
#   project_name = var.project_name
#   environment  = "prod"
#   aws_region   = var.aws_region
#   namespace    = kubernetes_namespace.qket_prod.metadata[0].name
#
#   oidc_provider_arn = data.terraform_remote_state.platform.outputs.oidc_provider_arn
#   oidc_provider_url = data.terraform_remote_state.platform.outputs.oidc_provider_url
#
#   rds_master_user_secret_arn = module.data_prod.rds_master_user_secret_arn
#   rds_endpoint                = module.data_prod.rds_endpoint
#   redis_endpoint               = module.data_prod.redis_endpoint
# }
#
# module "storage_prod" {
#   source = "../modules/storage"
#
#   project_name = var.project_name
#   environment  = "prod"
#   namespace    = kubernetes_namespace.qket_prod.metadata[0].name
#
#   oidc_provider_arn = data.terraform_remote_state.platform.outputs.oidc_provider_arn
#   oidc_provider_url = data.terraform_remote_state.platform.outputs.oidc_provider_url
# }
#
# 참고: modules/data 안 multi_az/num_cache_nodes는 지금 release 기준으로 하드코딩(false/1)돼 있어서,
# prod에 Multi-AZ/자동 페일오버를 쓰려면 그 값들도 변수로 빼서 이 블록에서 넘겨줘야 함.
# 그리고 prod를 실제로 켤 때는 modules/data의 prevent_destroy/skip_final_snapshot=false,
# eso의 recovery_window_in_days>=7, storage의 force_destroy=false로 안전장치를 다시 켤 것.
