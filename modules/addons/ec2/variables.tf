variable "project_name" {
  description = "리소스 이름 접두사"
  type        = string
}

variable "subnet_id" {
  description = "bastion 인스턴스를 배치할 서브넷 ID (private-general 권장)"
  type        = string
}

variable "security_group_id" {
  description = "bastion 인스턴스에 붙일 보안그룹 ID (modules/security_group 출력값)"
  type        = string
}

variable "bastion_instance_type" {
  description = "bastion 인스턴스 타입 — 터널링 용도라 최소 사양"
  type        = string
}
