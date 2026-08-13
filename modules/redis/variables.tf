variable "project_name" {
  description = "리소스 이름 접두사"
  type        = string
}

variable "environment" {
  description = "환경 구분 (release/prod) — terraform.workspace 값을 그대로 넘겨받음"
  type        = string
}

variable "private_data_subnet_ids" {
  description = "ElastiCache를 배치할 private-data 서브넷 ID 목록"
  type        = list(string)
}

variable "security_group_id" {
  description = "Redis에 붙일 보안그룹 ID (modules/security_group 출력값)"
  type        = string
}

variable "redis_node_type" {
  description = "ElastiCache 노드 타입"
  type        = string
}

variable "redis_engine_version" {
  description = "ElastiCache Redis 엔진 버전"
  type        = string
}
