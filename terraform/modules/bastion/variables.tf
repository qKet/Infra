variable "project_name" {
  description = "리소스 이름 접두사"
  type        = string
}

variable "vpc_id" {
  description = "보안그룹을 만들 VPC ID"
  type        = string
}

variable "subnet_id" {
  description = "bastion 인스턴스를 배치할 서브넷 ID (private-general 권장)"
  type        = string
}

variable "bastion_instance_type" {
  description = "bastion 인스턴스 타입 — 터널링 용도라 최소 사양"
  type        = string
}
