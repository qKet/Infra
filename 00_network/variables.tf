variable "project_name" {
  description = "리소스 이름"
  type        = string
  default     = "team5-qket"
}

variable "team_tag" {
  description = "공통 팀 테그(필수)"
  type        = string
  default     = "team5"
}

variable "aws_region" {
  description = "리소스를 생성할 AWS 리전"
  type        = string
  default     = "ap-northeast-2"
}

variable "vpc_cidr" {
  description = "VPC CIDR 대역"
  type        = string
  default     = "10.70.0.0/16"
}

variable "azs" {
  description = "가용영역 목록"
  type        = list(string)
  default     = ["ap-northeast-2a", "ap-northeast-2b"]
}

variable "public_subnet_cidrs" {
  description = "퍼블릭 서브넷 CIDR 목록 — AZ당 1개, azs와 순서 1:1 대응"
  type        = list(string)
  default     = ["10.70.1.0/24", "10.70.4.0/24"]
}

variable "private_subnet_cidrs" {
  description = "프라이빗 서브넷 CIDR 목록 — AZ당 2개씩, azs 순서대로 [a-1, a-2, b-1, b-2] 배치"
  type        = list(string)
  default     = ["10.70.2.0/24", "10.70.3.0/24", "10.70.5.0/24", "10.70.6.0/24"]
}
