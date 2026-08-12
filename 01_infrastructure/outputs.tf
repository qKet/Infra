output "vpc_id" {
  description = "생성된 VPC ID"
  value       = module.vpc.vpc_id
}

output "vpc_cidr" {
  description = "생성된 VPC CIDR"
  value       = module.vpc.vpc_cidr
}

output "igw_id" {
  description = "인터넷 게이트웨이 ID"
  value       = module.vpc.igw_id
}

output "public_subnet_ids" {
  description = "퍼블릭 서브넷 ID 목록"
  value       = module.subnet.public_subnet_ids
}

output "private_subnet_ids" {
  description = "프라이빗 서브넷 ID 목록 (일반 + 데이터 전체)"
  value       = module.subnet.private_subnet_ids
}

output "private_general_subnet_ids" {
  description = "프라이빗(일반 워크로드) 서브넷 ID 목록"
  value       = module.subnet.private_general_subnet_ids
}

output "private_general_subnet_cidrs" {
  description = "프라이빗(일반 워크로드) 서브넷 CIDR 목록 — data의 rds/redis SG가 infrastructure SG-ID 대신 이걸로 ingress를 검(infrastructure destroy/재생성에 data가 영향 안 받게)"
  value       = module.subnet.private_general_subnet_cidrs
}

output "private_data_subnet_ids" {
  description = "프라이빗-데이터(DB/Redis) 서브넷 ID 목록"
  value       = module.subnet.private_data_subnet_ids
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

output "cluster_admin_role_arn" {
  description = "클러스터 admin 접근용 공유 IAM Role ARN"
  value       = module.eks.cluster_admin_role_arn
}

output "amp_remote_write_endpoint" {
  description = "Prometheus remoteWrite 설정에 넣을 AMP 엔드포인트 (module.monitoring values용)"
  value       = "${aws_prometheus_workspace.this.prometheus_endpoint}api/v1/remote_write"
}

output "amp_query_endpoint" {
  description = "Grafana가 AMP를 Prometheus 데이터소스로 조회할 때 쓸 엔드포인트"
  value       = aws_prometheus_workspace.this.prometheus_endpoint
}

output "prometheus_irsa_role_arn" {
  description = "Prometheus ServiceAccount에 붙일 IRSA Role ARN (AMP remote_write용)"
  value       = module.irsa.role_arns["prometheus-amp"]
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
  # try()로 감쌈 — 매일 밤 destroy 상태일 땐 module.security_group 자체가 없어서
  # security_group_ids가 빈 맵이 되고, 존재하지 않는 키로 인덱싱하면 하드 에러가 남
  # (2026-08-11 실제로 겪음 — terraform apply -refresh-only가 이 출력값 하나 때문에 통째로 실패).
  # 다른 root가 이 값을 읽을 땐 어차피 04_data가 CIDR 기반 참조로 전환돼있어서 null이어도 안전함.
  value = try(module.security_group.security_group_ids["bastion"], null)
}
