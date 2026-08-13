variable "project_name" {
  description = "리소스 이름 접두사"
  type        = string
}

variable "vpc_id" {
  description = "서브넷을 만들 VPC ID (modules/vpc 출력값)"
  type        = string
}

variable "azs" {
  description = "가용영역 목록"
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "퍼블릭 서브넷 CIDR 목록 — AZ당 1개, azs와 순서 1:1 대응"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "프라이빗 서브넷 CIDR 목록 — AZ당 2개씩, azs 순서대로 [a-1, a-2, b-1, b-2] 배치"
  type        = list(string)
}
