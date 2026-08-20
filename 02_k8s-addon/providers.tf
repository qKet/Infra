terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.14"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.0"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# module.alb_controller가 aws_iam_role/aws_iam_role_policy를 만들어서 aws provider 필요
# (namespace/ArgoCD만 있을 땐 kubernetes/helm provider만으로 충분했음).
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = "shared"
    }
  }
}

# 01_infrastructure가 만든 EKS 클러스터에 인증 — exec 방식(그때그때 aws eks get-token)이라
# apply가 오래 걸려도 토큰(유효기간 ~15분) 만료 문제가 없음. 01_infrastructure/providers.tf와
# 완전히 동일한 패턴, module.eks.xxx 대신 terraform_remote_state로 값을 받아온다는 것만 다름.
provider "kubernetes" {
  host                   = data.terraform_remote_state.infrastructure.outputs.eks_cluster_endpoint
  cluster_ca_certificate = base64decode(data.terraform_remote_state.infrastructure.outputs.eks_cluster_certificate_authority)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    # --role-arn 없이 plain 신원으로 인증하면 EKS Access Entry가 cluster_admin role한테만 등록돼있어서 Unauthorized남.
    args = ["eks", "get-token", "--cluster-name", data.terraform_remote_state.infrastructure.outputs.eks_cluster_name, "--region", var.aws_region, "--role-arn", data.terraform_remote_state.infrastructure.outputs.cluster_admin_role_arn]
  }
}

provider "helm" {
  kubernetes {
    host                   = data.terraform_remote_state.infrastructure.outputs.eks_cluster_endpoint
    cluster_ca_certificate = base64decode(data.terraform_remote_state.infrastructure.outputs.eks_cluster_certificate_authority)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", data.terraform_remote_state.infrastructure.outputs.eks_cluster_name, "--region", var.aws_region, "--role-arn", data.terraform_remote_state.infrastructure.outputs.cluster_admin_role_arn]
    }
  }
}

# kubectl_manifest용(ArgoCD Application) — kubernetes_manifest와 달리 plan 시점에 클러스터를
# 라이브로 조회하지 않아서, ArgoCD 설치(helm_release.argocd가 Application CRD를 등록)와 그 위에
# Application 오브젝트를 만드는 걸 한 번의 apply로 처리 가능. 04_data가 ESO의 SecretStore/
# ExternalSecret에 쓰는 것과 완전히 같은 이유 — argocd-apps.tf 참고.
provider "kubectl" {
  host                   = data.terraform_remote_state.infrastructure.outputs.eks_cluster_endpoint
  cluster_ca_certificate = base64decode(data.terraform_remote_state.infrastructure.outputs.eks_cluster_certificate_authority)
  load_config_file       = false

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", data.terraform_remote_state.infrastructure.outputs.eks_cluster_name, "--region", var.aws_region, "--role-arn", data.terraform_remote_state.infrastructure.outputs.cluster_admin_role_arn]
  }
}
