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

variable "environment" {
  description = "환경 구분 — 이 root는 항상 release"
  type        = string
  default     = "release"
}

/*******************
*     RDS (MySQL)
*******************/
variable "db_name" {
  description = "RDS에 생성할 기본 데이터베이스 이름"
  type        = string
  default     = "qket"
}

variable "db_username" {
  description = "RDS 마스터 계정 이름"
  type        = string
  default     = "admin"
}

variable "db_instance_class" {
  description = "RDS 인스턴스 타입 — release는 싱글 AZ, 최소 사양"
  type        = string
  default     = "db.t3.micro"
}

variable "db_allocated_storage" {
  description = "RDS 초기 스토리지(GB)"
  type        = number
  default     = 20
}

variable "db_max_allocated_storage" {
  description = "RDS 자동 확장 최대 스토리지(GB) — 이 값까지는 추가 요청 없이 자동으로 늘어남"
  type        = number
  default     = 100
}

/*******************
*     ElastiCache (Redis)
*******************/
variable "redis_node_type" {
  description = "ElastiCache 노드 타입 — release는 싱글 노드, 최소 사양"
  type        = string
  default     = "cache.t3.micro"
}

variable "redis_engine_version" {
  description = "ElastiCache Redis 엔진 버전"
  type        = string
  default     = "7.1"
}
