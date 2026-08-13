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

# data(rds/redis 보안그룹)가 infrastructure의 SG ID를 직접 참조하지 않고 이 CIDR 대역으로
# ingress를 걸 수 있게 하기 위한 출력 — bastion/EKS 노드가 이 대역에 있으므로 "이 SG에서 오는
# 트래픽만" 대신 "이 대역에서 오는 트래픽"으로 허용해도 실질적으로 같은 대상을 가리킴.
# SG ID 참조를 안 쓰면 infrastructure를 destroy/재생성해도(SG ID가 바뀌어도) data가 전혀
# 영향받지 않음 — 자세한 이유는 CLAUDE_LLM_WIKI의 관련 트러블슈팅 문서 참고.
output "private_general_subnet_cidrs" {
  description = "프라이빗(일반 워크로드) 서브넷 CIDR 목록 — data의 rds/redis SG가 SG-ID 대신 이걸로 ingress를 검"
  value       = [for idx, cidr in var.private_subnet_cidrs : cidr if idx % 2 == 0]
}

output "private_data_subnet_ids" {
  description = "프라이빗-데이터(DB/Redis) 서브넷 ID 목록"
  value       = [for idx, s in aws_subnet.private : s.id if idx % 2 == 1]
}
