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
  description = "프라이빗(일반 워크로드) 서브넷 CIDR 목록 — data의 rds/redis SG가 SG-ID 대신 이걸로 ingress를 검"
  value       = module.subnet.private_general_subnet_cidrs
}

output "private_data_subnet_ids" {
  description = "프라이빗-데이터(DB/Redis) 서브넷 ID 목록"
  value       = module.subnet.private_data_subnet_ids
}

output "security_group_ids" {
  description = "이 root가 만든 보안그룹 ID 맵(현재 bastion 하나) — 항상 존재하는 영구 root라 try() 없이 그대로 인덱싱해도 안전"
  value       = module.security_group.security_group_ids
}
