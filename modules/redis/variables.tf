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

# 2026-08-19: 단일 장애점(SPOF) 이슈 대응 — 노드 개수/자동 failover를 환경별로 켜고 끌 수 있게 함.
# release에서 먼저 켜서 실제로 failover가 잘 동작하는지 검증하고, prod는 준비되면 값만 바꿔서 켜면 됨
# (04_data/main.tf의 env_config_map 참고).
variable "num_cache_clusters" {
  description = "Redis 노드 개수 (1=복제본 없음, 2 이상=primary+replica로 자동 failover 가능)"
  type        = number
  default     = 1
}

variable "automatic_failover_enabled" {
  description = "primary 장애 시 replica를 자동으로 승격시킬지 여부 — num_cache_clusters가 2 이상이어야 의미 있음"
  type        = bool
  default     = false
}

variable "multi_az_enabled" {
  description = "replica를 primary와 다른 AZ에 강제 배치할지 여부 — AZ 단위 장애까지 대응하려면 true 필요"
  type        = bool
  default     = false
}
