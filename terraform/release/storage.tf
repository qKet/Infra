module "storage_release" {
  source = "../modules/storage"

  project_name = var.project_name
  environment  = "release"
  namespace    = kubernetes_namespace.qket_release.metadata[0].name

  oidc_provider_arn = data.terraform_remote_state.platform.outputs.oidc_provider_arn
  oidc_provider_url = data.terraform_remote_state.platform.outputs.oidc_provider_url
}
