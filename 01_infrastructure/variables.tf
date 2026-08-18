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

/*******************
*     NetWork
*******************/
# vpc_cidr/public_subnet_cidrs/private_subnet_cidrs는 2026-08-13에 00_network로 옮겨감(vpc/subnet
# 모듈이 실제로 쓰는 값들이라 여기 남길 이유가 없음). azs는 NAT Gateway/라우팅 테이블 count에
# 여전히 쓰여서 남겨둠 — 00_network/variables.tf에도 같은 값(default)이 중복으로 있음, 서로 다른
# root라 변수 공유가 안 되니 두 곳 다 값을 바꿔야 함(가용영역을 실제로 바꿀 일은 거의 없음).
variable "azs" {
  description = "가용영역 목록"
  type        = list(string)
  default     = ["ap-northeast-2a", "ap-northeast-2b"]
}

/*******************
*     EKS
*******************/
variable "eks_version" {
  description = "EKS 클러스터 쿠버네티스 버전"
  type        = string
  default     = "1.35" # 추후에 1.36으로 버전업 예정
}

variable "node_instance_types" {
  description = "노드그룹 EC2 인스턴스 타입"
  type        = list(string)

  default     = ["t3.xlarge"]

}

variable "node_desired_size" {
  description = "노드그룹 기본 노드 수"
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "노드그룹 최소 노드 수"
  type        = number
  default     = 1
}

variable "node_max_size" {
  description = "노드그룹 최대 노드 수"
  type        = number
  default     = 3
}

/*******************
*     Bastion (SSM)
*******************/
variable "bastion_instance_type" {
  description = "SSM bastion 인스턴스 타입 — 터널링 용도라 최소 사양"
  type        = string
  default     = "t3.micro"
}
