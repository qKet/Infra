output "public_subnet_ids" {
  description = "퍼블릭 서브넷 ID 목록"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "프라이빗 서브넷 ID 목록 (일반 + 데이터 전체)"
  value       = aws_subnet.private[*].id
}

# aws_subnet.private 인덱스는 [a-일반, a-데이터, b-일반, b-데이터] 순서 (짝수=일반, 홀수=데이터)
output "private_general_subnet_ids" {
  description = "프라이빗(일반 워크로드) 서브넷 ID 목록 — EKS 노드/파드가 들어갈 자리"
  value       = [for idx, s in aws_subnet.private : s.id if idx % 2 == 0]
}

# data(rds/redis 보안그룹)가 infrastructure의 SG ID 대신 이 CIDR 대역으로 ingress를 검 —
# infrastructure를 destroy/재생성해도(SG ID가 바뀌어도) data가 영향받지 않음.
output "private_general_subnet_cidrs" {
  description = "프라이빗(일반 워크로드) 서브넷 CIDR 목록 — data의 rds/redis SG가 SG-ID 대신 이걸로 ingress를 검"
  value       = [for idx, cidr in var.private_subnet_cidrs : cidr if idx % 2 == 0]
}

output "private_data_subnet_ids" {
  description = "프라이빗-데이터(DB/Redis) 서브넷 ID 목록"
  value       = [for idx, s in aws_subnet.private : s.id if idx % 2 == 1]
}
