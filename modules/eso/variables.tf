variable "project_name" {
  description = "리소스 이름 접두사"
  type        = string
}

variable "environment" {
  description = "환경 구분 (dev/prod)"
  type        = string
}

variable "aws_region" {
  description = "AWS 리전"
  type        = string
}

variable "namespace" {
  description = "db-secrets/redis-secrets를 생성할 쿠버네티스 네임스페이스 (미리 존재해야 함)"
  type        = string
}

variable "oidc_provider_arn" {
  description = "IRSA용 OIDC 프로바이더 ARN (module.eks 출력값)"
  type        = string
}

variable "oidc_provider_url" {
  description = "IRSA용 OIDC 프로바이더 URL (module.eks 출력값)"
  type        = string
}

variable "rds_master_user_secret_arn" {
  description = "RDS가 자동 생성한 마스터 계정 Secrets Manager ARN (건드리지 않고 읽기만 함)"
  type        = string
}

variable "rds_endpoint" {
  description = "RDS 엔드포인트 — connection 시크릿의 DB_HOST 값으로 씀"
  type        = string
}

variable "redis_endpoint" {
  description = "ElastiCache Redis 엔드포인트 — connection 시크릿의 REDIS_HOST 값으로 씀"
  type        = string
}

variable "secret_recovery_window_days" {
  description = "connection 시크릿 삭제 시 대기기간(일) — release는 0(바로 삭제, 재생성 충돌 방지), prod는 7 이상 권장(실수 삭제 대비)"
  type        = number
  default     = 0
}
