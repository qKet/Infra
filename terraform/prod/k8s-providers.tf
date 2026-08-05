locals {
  eks_cluster_name                  = data.terraform_remote_state.platform.outputs.eks_cluster_name
  eks_cluster_endpoint               = data.terraform_remote_state.platform.outputs.eks_cluster_endpoint
  eks_cluster_certificate_authority = data.terraform_remote_state.platform.outputs.eks_cluster_certificate_authority
}

provider "kubernetes" {
  host                   = local.eks_cluster_endpoint
  cluster_ca_certificate = base64decode(local.eks_cluster_certificate_authority)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", local.eks_cluster_name, "--region", var.aws_region]
  }
}

provider "helm" {
  kubernetes {
    host                   = local.eks_cluster_endpoint
    cluster_ca_certificate = base64decode(local.eks_cluster_certificate_authority)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", local.eks_cluster_name, "--region", var.aws_region]
    }
  }
}

provider "kubectl" {
  host                   = local.eks_cluster_endpoint
  cluster_ca_certificate = base64decode(local.eks_cluster_certificate_authority)
  load_config_file       = false

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", local.eks_cluster_name, "--region", var.aws_region]
  }
}
