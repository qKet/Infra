variable "namespace" {
  description = "MySQL/Redis StatefulSet을 배포할 네임스페이스"
  type        = string
}

variable "mysql_storage_size" {
  description = "MySQL 데이터 볼륨(EBS) 크기 — 03_registry의 aws_ebs_volume.dev_mysql 크기와 반드시 일치해야 함"
  type        = string
  default     = "10Gi"
}

variable "redis_storage_size" {
  description = "Redis 데이터 볼륨(EBS) 크기 — 03_registry의 aws_ebs_volume.dev_redis 크기와 반드시 일치해야 함"
  type        = string
  default     = "2Gi"
}

variable "mysql_ebs_volume_id" {
  description = "03_registry에서 만든 영구 EBS 볼륨 ID (aws_ebs_volume.dev_mysql) — 매번 새로 안 만들고 이 볼륨을 정적으로 재연결"
  type        = string
}

variable "redis_ebs_volume_id" {
  description = "03_registry에서 만든 영구 EBS 볼륨 ID (aws_ebs_volume.dev_redis) — 매번 새로 안 만들고 이 볼륨을 정적으로 재연결"
  type        = string
}

variable "availability_zone" {
  description = "EBS 볼륨이 있는 AZ — 이 AZ의 노드에만 파드가 뜨도록 강제(nodeAffinity)"
  type        = string
}
