variable "project_name" {
  description = "리소스 이름 접두사"
  type        = string
}

variable "aws_region" {
  description = "AWS 리전"
  type        = string
}

variable "vpc_id" {
  description = "클러스터가 속한 VPC ID"
  type        = string
}

variable "cluster_name" {
  description = "EKS 클러스터 이름"
  type        = string
}

variable "oidc_provider_arn" {
  description = "IRSA용 OIDC 프로바이더 ARN (module.eks 출력값)"
  type        = string
}

variable "oidc_provider_url" {
  description = "IRSA용 OIDC 프로바이더 URL (module.eks 출력값)"
  type        = string
}
