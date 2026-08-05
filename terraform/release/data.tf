module "data_release" {
  source = "../modules/data"

  project_name = var.project_name
  environment  = "release"

  vpc_id                        = data.terraform_remote_state.platform.outputs.vpc_id
  private_data_subnet_ids       = data.terraform_remote_state.platform.outputs.private_data_subnet_ids
  eks_cluster_security_group_id = data.terraform_remote_state.platform.outputs.eks_cluster_security_group_id
  bastion_security_group_id     = data.terraform_remote_state.platform.outputs.bastion_security_group_id

  db_name                  = var.db_name
  db_username              = var.db_username
  db_instance_class        = var.db_instance_class
  db_allocated_storage     = var.db_allocated_storage
  db_max_allocated_storage = var.db_max_allocated_storage

  redis_node_type      = var.redis_node_type
  redis_engine_version = var.redis_engine_version
}
