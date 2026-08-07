# helm/kubectl provider는 여기 없음 — ESO(External Secrets Operator)가 backup/modules/eso로 보류돼서
# 지금은 kubernetes provider(namespace/configmap/service account)만 있으면 충분.
# ESO 재활성화 시 backup/README.md 절차대로 되돌리면서 여기도 helm/kubectl을 다시 추가할 것.
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

# platform root가 만든 EKS 클러스터에 인증 — exec 방식(그때그때 aws eks get-token)이라
# apply가 오래 걸려도 토큰(유효기간 ~15분) 만료 문제가 없음.
provider "kubernetes" {
  host                   = data.terraform_remote_state.platform.outputs.eks_cluster_endpoint
  cluster_ca_certificate = base64decode(data.terraform_remote_state.platform.outputs.eks_cluster_certificate_authority)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    # --role-arn 없이 plain 신원으로 인증하면 EKS Access Entry가 role한테만 등록돼있어서 Unauthorized남.
    args = ["eks", "get-token", "--cluster-name", data.terraform_remote_state.platform.outputs.eks_cluster_name, "--region", var.aws_region, "--role-arn", data.terraform_remote_state.platform.outputs.cluster_admin_role_arn]
  }
}
