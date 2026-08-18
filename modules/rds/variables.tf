variable "project_name" {
  description = "리소스 이름 접두사"
  type        = string
}

variable "environment" {
  description = "환경 구분 (release/prod) — terraform.workspace 값을 그대로 넘겨받음"
  type        = string
}

variable "private_data_subnet_ids" {
  description = "RDS를 배치할 private-data 서브넷 ID 목록"
  type        = list(string)
}

variable "security_group_id" {
  description = "RDS에 붙일 보안그룹 ID (modules/security_group 출력값)"
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

variable "multi_az" {
  description = "Multi-AZ 여부 — release는 false(비용 절반), prod는 true 권장"
  type        = bool
  default     = false
}

variable "skip_final_snapshot" {
  description = "삭제 시 최종 스냅샷 생략 여부 — release는 true(자주 재생성), prod는 false 권장"
  type        = bool
  default     = true
}

variable "deletion_protection" {
  description = "삭제 방지 — release는 false, prod는 true 권장"
  type        = bool
  default     = false
}

variable "storage_encrypted" {
  description = <<-EOT
    저장 암호화(KMS) 여부 — 기본 true로 새로 만드는 인스턴스는 항상 암호화됨.
    주의: 이미 떠 있는 미암호화 인스턴스에 이 값을 true로 바꾸면 AWS 제약상 in-place 변경이
    안 되어 Terraform이 destroy 후 재생성으로 처리함 — skip_final_snapshot=true인 환경(release)은
    스냅샷 없이 바로 삭제되므로 데이터가 통째로 날아감. 반드시 스냅샷 생성 → 새 인스턴스로
    복원(snapshot restore) 절차를 먼저 밟고 나서 이 값을 켤 것.
  EOT
  type        = bool
  default     = true
}
