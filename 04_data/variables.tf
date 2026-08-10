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
*     RDS (MySQL) — environment(workspace)와 무관하게 공통인 값만
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

/*******************
*     ElastiCache (Redis)
*******************/
variable "redis_engine_version" {
  description = "ElastiCache Redis 엔진 버전"
  type        = string
  default     = "7.1"
}
