variable "project_name" {
  description = "리소스 이름 접두사"
  type        = string
}

variable "ecr_repository_arn" {
  description = "CI가 push할 ECR 저장소 ARN"
  type        = string
}

variable "repos" {
  description = <<-EOT
    OIDC Role을 만들 GitHub 레포 목록. key는 아무 식별자(예: "backend"), repo는 "org/name" 형식,
    allowed_branches는 이 role을 assume할 수 있는 브랜치 목록(push 트리거 기준).
  EOT
  type = map(object({
    repo             = string
    allowed_branches = list(string)
  }))
}
