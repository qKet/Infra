output "cluster_role_arn" {
  description = "EKS 클러스터(컨트롤 플레인) IAM 역할 ARN"
  value       = aws_iam_role.eks_cluster.arn
}

output "cluster_name" {
  description = "EKS 클러스터 이름"
  value       = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  description = "EKS 클러스터 API 엔드포인트"
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_certificate_authority" {
  description = "EKS 클러스터 CA 인증서 (kubeconfig 구성용)"
  value       = aws_eks_cluster.this.certificate_authority[0].data
}

output "cluster_oidc_issuer_url" {
  description = "IRSA(OIDC 프로바이더) 설정에 쓰는 클러스터 OIDC 발급자 URL"
  value       = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

output "oidc_provider_arn" {
  description = "IRSA용 OIDC 프로바이더 ARN"
  value       = aws_iam_openid_connect_provider.this.arn
}

output "oidc_provider_url" {
  description = "IRSA용 OIDC 프로바이더 URL"
  value       = aws_iam_openid_connect_provider.this.url
}

output "cluster_security_group_id" {
  description = "EKS가 자동 생성한 클러스터 보안 그룹 ID"
  value       = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

output "node_group_status" {
  description = "노드그룹 상태"
  value       = aws_eks_node_group.this.status
}

output "node_role_arn" {
  description = "워커 노드 IAM 역할 ARN"
  value       = aws_iam_role.eks_node.arn
}

output "cluster_admin_role_arn" {
  description = "클러스터 admin 접근용 공유 IAM Role ARN — kubectl에서 이 role을 assume해서 접속"
  value       = aws_iam_role.cluster_admin.arn
}

output "cluster_admins_group_name" {
  description = "이 그룹에 팀원을 추가하면 위 role을 assume할 수 있게 됨 (IAM 콘솔/CLI에서, terraform 안 건드림)"
  value       = aws_iam_group.cluster_admins.name
}
