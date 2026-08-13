# backend/frontend 이미지를 담는 저장소. release/prod가 태그(예: backend-<sha>)로만 구분되고
# 저장소 자체는 공유 — infrastructure root에서 딱 한 번만 생성.
# TODO(2026-08-10): 원래 계획대로면 ECR은 절대 안 지우는 별도 registry root(구상 단계)로 옮겨야 함
# — infrastructure는 매일 켜고 끄는 대상이라 같이 있으면 위험. 아직 이전 안 함.
resource "aws_ecr_repository" "this" {
  name                 = var.repository_name
  image_tag_mutability = var.image_tag_mutability

  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }
}

# 태그 없는(untagged) 이미지만 일정 기간 후 자동 정리 — 태그 붙은 이미지(backend-*, frontend-*)는
# 안 건드림. dangling image가 계속 쌓여서 스토리지 비용/한도를 잡아먹는 걸 방지.
resource "aws_ecr_lifecycle_policy" "this" {
  repository = aws_ecr_repository.this.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "태그 없는 이미지는 ${var.untagged_expire_days}일 후 만료"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = var.untagged_expire_days
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}
