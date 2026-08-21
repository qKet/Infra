# 2026-08-10: ESO(External Secrets Operator) 재활성화하면서 kubectl provider 추가함
# (module.eso가 kubectl_manifest를 씀 — sync.tf 참고). helm provider는 2026-08-21 ESO 컨트롤러가
# 02_k8s-addon(공유 singleton, module.eso_controller)으로 옮겨가면서 이 root엔 더 이상 helm_release를
# 쓰는 리소스가 없어져서 제거함.
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
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Team        = var.team_tag
      Environment = local.environment
    }
  }
}

# infrastructure root가 만든 EKS 클러스터에 인증 — exec 방식(그때그때 aws eks get-token)이라
# apply가 오래 걸려도 토큰(유효기간 ~15분) 만료 문제가 없음.
provider "kubernetes" {
  host                   = data.terraform_remote_state.infrastructure.outputs.eks_cluster_endpoint
  cluster_ca_certificate = base64decode(data.terraform_remote_state.infrastructure.outputs.eks_cluster_certificate_authority)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    # --role-arn 없이 plain 신원으로 인증하면 EKS Access Entry가 role한테만 등록돼있어서 Unauthorized남.
    args = ["eks", "get-token", "--cluster-name", data.terraform_remote_state.infrastructure.outputs.eks_cluster_name, "--region", var.aws_region, "--role-arn", data.terraform_remote_state.infrastructure.outputs.cluster_admin_role_arn]
  }
}

# kubectl_manifest용(module.eso의 SecretStore/ExternalSecret) — kubernetes_manifest와 달리
# plan 시점에 클러스터를 라이브로 조회하지 않아서, ESO 설치와 그 위 CRD 리소스를 한 번의 apply로 처리 가능.
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
