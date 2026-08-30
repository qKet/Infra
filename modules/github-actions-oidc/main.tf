# GitHub Actions가 고정 AWS 키 없이 OIDC로 인증할 수 있게 하는 IAM 리소스.
data "tls_certificate" "github" {
  url = "https://token.actions.githubusercontent.com/.well-known/openid-configuration"
}

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github.certificates[0].sha1_fingerprint]
}

# 레포 하나당 Role 하나 — for_each로 backend/frontend 등을 한 번에 관리.
#
# sub claim 하나로만 조건을 검(repository/ref/job_workflow_ref 등 다른 claim은 전부 Not
# authorized로 실패, troubleshooting/github-actions-oidc-not-authorized.md 참고). qKet 조직이
# "Customize subject claims"를 켜둬서 sub에 불변 숫자 ID가 섞여 나옴 — 와일드카드(@*) 대신
# github_owner_id/repository_id 실제 값을 박아넣어 조직 이름 재사용 취약점을 막음.
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
      values = [
        for branch in each.value.allowed_branches :
        "repo:${split("/", each.value.repo)[0]}@${var.github_owner_id}/${split("/", each.value.repo)[1]}@${each.value.repository_id}:ref:refs/heads/${branch}"
      ]
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

# frontend CI가 빌드 직전에 NEXT_PUBLIC_TOSS_CLIENT_KEY를 Secrets Manager에서 직접 가져감
# (backend는 ESO가 런타임에 처리해서 불필요). 정확한 ARN 대신 이름 prefix 와일드카드를 쓴 이유:
# 이 시크릿은 04_data(release/prod 두 번 생성)가 만들어서 03_registry가 직접 참조하면 root 간
# 의존관계가 생김 — prefix로 release/prod 둘 다, 이 용도 시크릿만 커버.
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

data "aws_iam_policy_document" "frontend_secrets_read" {
  statement {
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
    ]
    resources = [
      "arn:aws:secretsmanager:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:secret:${var.project_name}-external-api-*",
    ]
  }
}

resource "aws_iam_role_policy" "frontend_secrets_read" {
  name   = "${var.project_name}-gha-frontend-secrets-read"
  role   = aws_iam_role.ci["frontend"].id
  policy = data.aws_iam_policy_document.frontend_secrets_read.json
}
