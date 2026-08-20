variable "namespace" {
  description = "MySQL/Redis StatefulSet을 배포할 네임스페이스"
  type        = string
}

variable "mysql_storage_size" {
  description = "MySQL 데이터 볼륨(EBS) 크기"
  type        = string
  default     = "10Gi"
}

variable "redis_storage_size" {
  description = "Redis 데이터 볼륨(EBS) 크기"
  type        = string
  default     = "2Gi"
}
