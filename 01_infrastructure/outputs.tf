# 아래 network 관련 output들은 00_network(영구 root)의 값을 그대로 통과시킴(passthrough) —
# 이름을 유지해서 이걸 참조하는 다른 root(02_k8s-addon 등)를 안 고쳐도 되게 함.
output "vpc_id" {
  description = "생성된 VPC ID"
  value       = data.terraform_remote_state.network.outputs.vpc_id
}

output "vpc_cidr" {
  description = "생성된 VPC CIDR"
  value       = data.terraform_remote_state.network.outputs.vpc_cidr
}

output "igw_id" {
  description = "인터넷 게이트웨이 ID"
  value       = data.terraform_remote_state.network.outputs.igw_id
}

output "public_subnet_ids" {
  description = "퍼블릭 서브넷 ID 목록"
  value       = data.terraform_remote_state.network.outputs.public_subnet_ids
}

output "private_subnet_ids" {
  description = "프라이빗 서브넷 ID 목록 (일반 + 데이터 전체)"
  value       = data.terraform_remote_state.network.outputs.private_subnet_ids
}

output "private_general_subnet_ids" {
  description = "프라이빗(일반 워크로드) 서브넷 ID 목록"
  value       = data.terraform_remote_state.network.outputs.private_general_subnet_ids
}

output "private_general_subnet_cidrs" {
  description = "프라이빗(일반 워크로드) 서브넷 CIDR 목록 — data의 rds/redis SG가 SG-ID 대신 이걸로 ingress를 검(network destroy/재생성 자체가 이제 없지만, infrastructure destroy/재생성에도 data가 영향 안 받는다는 원래 이유는 여전히 유효)"
  value       = data.terraform_remote_state.network.outputs.private_general_subnet_cidrs
}

output "private_data_subnet_ids" {
  description = "프라이빗-데이터(DB/Redis) 서브넷 ID 목록"
  value       = data.terraform_remote_state.network.outputs.private_data_subnet_ids
}

output "public_route_table_id" {
  description = "퍼블릭 라우팅 테이블 ID"
  value       = aws_route_table.public.id
}

output "private_route_table_ids" {
  description = "프라이빗(일반) 라우팅 테이블 ID 목록 (AZ별)"
  value       = aws_route_table.private[*].id
}

output "private_data_route_table_id" {
  description = "프라이빗-데이터 라우팅 테이블 ID"
  value       = aws_route_table.private_data.id
}

output "nat_gateway_ids" {
  description = "NAT Gateway ID 목록 (AZ별)"
  value       = aws_nat_gateway.this[*].id
}

output "nat_gateway_public_ips" {
  description = "NAT Gateway에 붙은 고정 IP 목록"
  value       = aws_eip.nat[*].public_ip
}

output "eks_cluster_role_arn" {
  description = "EKS 클러스터(컨트롤 플레인) IAM 역할 ARN"
  value       = module.eks.cluster_role_arn
}

output "eks_cluster_name" {
  description = "EKS 클러스터 이름"
  value       = module.eks.cluster_name
}

output "eks_version" {
  description = "EKS 클러스터 쿠버네티스 버전 — module.cluster_autoscaler가 이미지 태그를 여기에 맞춤(02_k8s-addon)"
  value       = var.eks_version
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

output "oidc_provider_arn" {
  description = "EKS 클러스터 OIDC 프로바이더 ARN — release/prod의 IRSA 역할들이 이 값을 참조"
  value       = module.eks.oidc_provider_arn
}

output "oidc_provider_url" {
  description = "EKS 클러스터 OIDC 프로바이더 URL — release/prod의 IRSA 역할들이 이 값을 참조"
  value       = module.eks.oidc_provider_url
}

output "cluster_admin_role_arn" {
  description = "클러스터 admin 접근용 공유 IAM Role ARN"
  value       = module.eks.cluster_admin_role_arn
}

output "cluster_admins_group_name" {
  description = "이 IAM 그룹에 팀원을 추가하면 클러스터 admin 접근 가능 (콘솔/CLI에서 직접, terraform 안 건드림)"
  value       = module.eks.cluster_admins_group_name
}

output "ssm_bastion_instance_id" {
  description = "SSM 세션 연결에 쓸 bastion 인스턴스 ID (aws ssm start-session --target <이값>)"
  value       = module.ec2.instance_id
}

output "bastion_security_group_id" {
  description = "bastion 보안그룹 ID — data root의 RDS/Redis 보안그룹에서 참조"
  # security_group이 00_network(영구 root)에 있어서 try() 방어 불필요.
  value = data.terraform_remote_state.network.outputs.security_group_ids["bastion"]
}
