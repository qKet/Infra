variable "project_name" {
  description = "리소스 이름 접두사"
  type        = string
}

variable "aws_region" {
  description = "AWS 리전"
  type        = string
}

variable "cluster_name" {
  description = "EKS 클러스터 이름 — ASG autodiscovery 태그(k8s.io/cluster-autoscaler/<이 값>)와 IAM 정책 조건에 사용"
  type        = string
}

variable "eks_version" {
  description = "EKS 클러스터 쿠버네티스 버전(예: \"1.35\") — cluster-autoscaler 이미지 태그를 이 버전과 맞추기 위해 사용. 클러스터 버전을 올릴 때 같이 올릴 것"
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
