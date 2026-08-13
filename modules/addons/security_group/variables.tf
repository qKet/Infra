variable "project_name" {
  description = "리소스 이름 접두사"
  type        = string
}

variable "vpc_id" {
  description = "보안그룹을 만들 VPC ID"
  type        = string
}

variable "security_groups" {
  description = <<-EOT
    생성할 보안그룹 정의 맵. key가 이름 suffix(예: "bastion", "rds-release").
    ingress가 빈 리스트면 인바운드 없이 아웃바운드만 여는 그룹이 됨 (SSM bastion 용도).
  EOT
  type = map(object({
    ingress = list(object({
      description     = string
      from_port       = number
      to_port         = number
      protocol        = string
      security_groups = optional(list(string), [])
      cidr_blocks     = optional(list(string), [])
    }))
  }))
}
