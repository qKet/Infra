variable "project_name" {
  description = "리소스 이름 접두사"
  type        = string
}

variable "environment" {
  description = "환경 구분 (dev/prod)"
  type        = string
}

variable "vpc_id" {
  description = "보안그룹을 만들 VPC ID"
  type        = string
}

variable "private_data_subnet_ids" {
  description = "RDS/ElastiCache를 배치할 private-data 서브넷 ID 목록"
  type        = list(string)
}

variable "eks_cluster_security_group_id" {
  description = "RDS/Redis 접속을 허용할 EKS 클러스터 보안그룹 ID"
  type        = string
}

variable "bastion_security_group_id" {
  description = "RDS/Redis 접속을 허용할 SSM bastion 보안그룹 ID"
  type        = string
}

variable "db_name" {
  description = "RDS에 생성할 기본 데이터베이스 이름"
  type        = string
}

variable "db_username" {
  description = "RDS 마스터 계정 이름"
  type        = string
}

variable "db_instance_class" {
  description = "RDS 인스턴스 타입"
  type        = string
}

variable "db_allocated_storage" {
  description = "RDS 초기 스토리지(GB)"
  type        = number
}

variable "db_max_allocated_storage" {
  description = "RDS 자동 확장 최대 스토리지(GB)"
  type        = number
}

variable "redis_node_type" {
  description = "ElastiCache 노드 타입"
  type        = string
}

variable "redis_engine_version" {
  description = "ElastiCache Redis 엔진 버전"
  type        = string
}
