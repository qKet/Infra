output "vpc_id" {
  description = "생성된 VPC ID"
  value       = module.network.vpc_id
}

output "vpc_cidr" {
  description = "생성된 VPC CIDR"
  value       = module.network.vpc_cidr
}

output "public_subnet_ids" {
  description = "퍼블릭 서브넷 ID 목록"
  value       = module.network.public_subnet_ids
}

output "private_subnet_ids" {
  description = "프라이빗 서브넷 ID 목록 (일반 + 데이터 전체)"
  value       = module.network.private_subnet_ids
}

output "private_general_subnet_ids" {
  description = "프라이빗(일반 워크로드) 서브넷 ID 목록"
  value       = module.network.private_general_subnet_ids
}

output "private_data_subnet_ids" {
  description = "프라이빗-데이터(DB/Redis) 서브넷 ID 목록"
  value       = module.network.private_data_subnet_ids
}

output "igw_id" {
  description = "인터넷 게이트웨이 ID"
  value       = module.network.igw_id
}

output "public_route_table_id" {
  description = "퍼블릭 라우팅 테이블 ID"
  value       = module.network.public_route_table_id
}

output "private_route_table_ids" {
  description = "프라이빗(일반) 라우팅 테이블 ID 목록 (AZ별)"
  value       = module.network.private_route_table_ids
}

output "private_data_route_table_id" {
  description = "프라이빗-데이터 라우팅 테이블 ID"
  value       = module.network.private_data_route_table_id
}

output "nat_gateway_ids" {
  description = "NAT Gateway ID 목록 (AZ별)"
  value       = module.network.nat_gateway_ids
}

output "nat_gateway_public_ips" {
  description = "NAT Gateway에 붙은 고정 IP 목록"
  value       = module.network.nat_gateway_public_ips
}

output "eks_cluster_role_arn" {
  description = "EKS 클러스터(컨트롤 플레인) IAM 역할 ARN"
  value       = module.eks.cluster_role_arn
}

output "eks_cluster_name" {
  description = "EKS 클러스터 이름"
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "EKS 클러스터 API 엔드포인트"
  value       = module.eks.cluster_endpoint
}

output "eks_cluster_certificate_authority" {
  description = "EKS 클러스터 CA 인증서 (kubeconfig 구성용)"
  value       = module.eks.cluster_certificate_authority
}

output "eks_cluster_security_group_id" {
  description = "EKS가 자동 생성한 클러스터 보안 그룹 ID"
  value       = module.eks.cluster_security_group_id
}

output "eks_node_group_status" {
  description = "노드그룹 상태"
  value       = module.eks.node_group_status
}

output "eks_node_role_arn" {
  description = "워커 노드 IAM 역할 ARN"
  value       = module.eks.node_role_arn
}

output "oidc_provider_arn" {
  description = "EKS 클러스터 OIDC 프로바이더 ARN — release/prod의 IRSA 역할들이 이 값을 참조"
  value       = module.eks.oidc_provider_arn
}

output "oidc_provider_url" {
  description = "EKS 클러스터 OIDC 프로바이더 URL — release/prod의 IRSA 역할들이 이 값을 참조"
  value       = module.eks.oidc_provider_url
}

output "alb_controller_role_arn" {
  description = "ALB Controller IRSA IAM 역할 ARN"
  value       = module.alb_controller.role_arn
}

output "ssm_bastion_instance_id" {
  description = "SSM 세션 연결에 쓸 bastion 인스턴스 ID (aws ssm start-session --target <이값>)"
  value       = module.bastion.instance_id
}

output "bastion_security_group_id" {
  description = "bastion 보안그룹 ID — release/prod RDS/Redis 보안그룹에서 참조"
  value       = module.bastion.security_group_id
}
