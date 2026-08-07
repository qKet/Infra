terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.14"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Team        = var.team_tag
      Environment = "shared"
    }
  }
}

# helm/kubernetes/kubectl 프로바이더가 EKS 클러스터에 인증하는 방식.
# 토큰을 미리 한 번 받아서 고정(data source)하면 apply가 오래 걸릴 때(클러스터+노드그룹 등)
# 뒷부분 리소스를 처리할 즈음엔 토큰(유효기간 ~15분)이 만료돼버림 — 실제로 겪었음.
# exec 방식은 실제 API 호출하는 "그 순간"마다 aws eks get-token을 새로 실행해서 토큰을 받아오므로
# apply가 아무리 오래 걸려도 만료 문제가 없음.
# --role-arn 없이 plain 신원으로 인증하면 EKS Access Entry가 team5-qket-cluster-admin
# role한테만 등록돼있어서 Unauthorized남 — 세 provider(kubernetes/helm/kubectl) 전부 이 role로 인증.
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.aws_region, "--role-arn", module.eks.cluster_admin_role_arn]
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.aws_region, "--role-arn", module.eks.cluster_admin_role_arn]
    }
  }
}

# kubectl_manifest용 — kubernetes_manifest와 달리 plan 시점에 클러스터를 라이브로 조회하지 않아서
# 클러스터를 만드는 것과 그 위에 CRD 리소스를 올리는 걸 한 번의 apply로 처리 가능
provider "kubectl" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority)
  load_config_file       = false

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.aws_region, "--role-arn", module.eks.cluster_admin_role_arn]
  }
}
