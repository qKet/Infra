module "alb_controller" {
  source = "../modules/alb-controller"

  project_name = var.project_name
  aws_region   = var.aws_region
  vpc_id       = module.network.vpc_id
  cluster_name = module.eks.cluster_name

  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url
}
