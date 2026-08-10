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

# kubernetes/helm/kubectl provider는 2026-08-10부로 여기 없음 — namespace(kubernetes_namespace.qket)와
# ArgoCD(helm_release.argocd)를 ../02_k8s-addon으로 옮기면서, 이 root는 kubernetes API를 전혀 안 쓰는
# 순수 AWS 리소스 전용 root가 됨. 자세한 이유는 CLAUDE_LLM_WIKI의 eks-destroy-layer-separation 문서 참고.
