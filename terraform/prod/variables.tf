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
  description = "환경 구분 — 이 root는 항상 prod"
  type        = string
  default     = "prod"
}

/*******************
*     RDS (MySQL) — prod용 넉넉한 기본값. 실제로 켤 때 필요하면 조정.
*******************/
variable "db_name" {
  type    = string
  default = "qket"
}

variable "db_username" {
  type    = string
  default = "admin"
}

variable "db_instance_class" {
  type    = string
  default = "db.t3.small"
}

variable "db_allocated_storage" {
  type    = number
  default = 50
}

variable "db_max_allocated_storage" {
  type    = number
  default = 200
}

/*******************
*     ElastiCache (Redis)
*******************/
variable "redis_node_type" {
  type    = string
  default = "cache.t3.small"
}

variable "redis_engine_version" {
  type    = string
  default = "7.1"
}
