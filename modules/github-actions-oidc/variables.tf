variable "project_name" {
  description = "리소스 이름 접두사"
  type        = string
}

variable "ecr_repository_arn" {
  description = "CI가 push할 ECR 저장소 ARN"
  type        = string
}

variable "github_owner_id" {
  description = <<-EOT
    GitHub 조직(qKet)의 불변 숫자 ID. `curl https://api.github.com/repos/<org>/<repo>`의
    `.owner.id`로 확인 가능. sub claim에 이 ID가 박혀있어서(subject claim 커스터마이징) 와일드카드
    대신 정확히 넣어야 "조직 이름 재사용" 공격을 막을 수 있음 — troubleshooting/github-actions-oidc-not-authorized 참고.
  EOT
  type        = string
}

variable "repos" {
  description = <<-EOT
    OIDC Role을 만들 GitHub 레포 목록. key는 아무 식별자(예: "backend"), repo는 "org/name" 형식,
    repository_id는 그 레포의 불변 숫자 ID(`curl https://api.github.com/repos/<org>/<repo>`의 `.id`),
    allowed_branches는 이 role을 assume할 수 있는 브랜치 목록(push 트리거 기준).
  EOT
  type = map(object({
    repo             = string
    repository_id    = string
    allowed_branches = list(string)
  }))
}
