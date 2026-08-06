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

output "private_data_subnet_ids" {
  description = "프라이빗-데이터(DB/Redis) 서브넷 ID 목록"
  value       = [for idx, s in aws_subnet.private : s.id if idx % 2 == 1]
}
