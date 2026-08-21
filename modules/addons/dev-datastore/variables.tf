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

variable "mysql_root_password" {
  description = "MySQL root 비밀번호 — 03_registry의 영구 시크릿(random_password.dev_mysql_root)에서 받아옴. 여기서 자체 생성하지 않는 이유: 이 모듈(02_k8s-addon)은 매일 밤 destroy/재생성되는데, MySQL 데이터 자체(EBS 볼륨)는 영구 보존이라 컨테이너가 둘째 날부터는 MYSQL_ROOT_PASSWORD 환경변수를 다시 안 읽음 — 매번 새로 생성하면 Terraform이 아는 값과 실제 MySQL 비밀번호가 어긋나는 드리프트가 생김"
  type        = string
  sensitive   = true
}
