# GitHub Actions가 고정 AWS 키 없이 OIDC로 인증할 수 있게 하는 IAM 리소스.
# OIDC Provider는 AWS 계정당 하나만 있으면 되고(모든 레포가 공유), 어느 레포/브랜치가
# 실제로 assume 가능한지는 각 Role의 trust policy(assume_role_policy)에서 좁힌다.
data "tls_certificate" "github" {
  url = "https://token.actions.githubusercontent.com/.well-known/openid-configuration"
}

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github.certificates[0].sha1_fingerprint]
}

# 레포 하나당 Role 하나 — for_each로 backend/frontend 등을 한 번에 관리.
# sub 조건이 "repo:<org>/<repo>:ref:refs/heads/<branch>" 형식이라, 지정한 브랜치에서
# 실행된 워크플로우만 이 role을 assume할 수 있음 (다른 레포/브랜치/PR은 거부됨).
data "aws_iam_policy_document" "assume" {
  for_each = var.repos

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [for branch in each.value.allowed_branches : "repo:${each.value.repo}:ref:refs/heads/${branch}"]
    }
  }
}

resource "aws_iam_role" "ci" {
  for_each = var.repos

  name               = "${var.project_name}-gha-${each.key}"
  assume_role_policy = data.aws_iam_policy_document.assume[each.key].json
}

# ECR push 권한만 최소로 — CI가 하는 일은 이제 build+push까지뿐(배포/kubectl은 ArgoCD 담당이라 불필요).
data "aws_iam_policy_document" "ecr_push" {
  for_each = var.repos

  statement {
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
      "ecr:PutImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
    ]
    resources = [var.ecr_repository_arn]
  }
}

resource "aws_iam_role_policy" "ecr_push" {
  for_each = var.repos

  name   = "${var.project_name}-gha-${each.key}-ecr-push"
  role   = aws_iam_role.ci[each.key].id
  policy = data.aws_iam_policy_document.ecr_push[each.key].json
}
