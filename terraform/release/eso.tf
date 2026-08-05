module "eso_release" {
  source = "../modules/eso"

  project_name = var.project_name
  environment  = "release"
  aws_region   = var.aws_region
  namespace    = kubernetes_namespace.qket_release.metadata[0].name

  oidc_provider_arn = data.terraform_remote_state.platform.outputs.oidc_provider_arn
  oidc_provider_url = data.terraform_remote_state.platform.outputs.oidc_provider_url

  rds_master_user_secret_arn = module.data_release.rds_master_user_secret_arn
  rds_endpoint                = module.data_release.rds_endpoint
  redis_endpoint               = module.data_release.redis_endpoint
}
