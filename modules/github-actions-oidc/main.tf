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
# sub claim 하나로만 조건을 검. repository/ref/job_workflow_ref 커스텀 claim으로
# 조건을 걸었을 때는 CloudTrail상 원인 불명의 AccessDenied가 계속 났고(Not authorized),
# sub 하나로 좁히니 바로 성공했음 — 이유는 명확히 못 밝혔지만 실증적으로 sub만 안정적으로
# 동작함을 확인(2026-08-07). qKet 조직이 GitHub의 "Customize subject claims" 옵션을
# 켜둬서 sub가 기본 형식이 아니라 "repo:qKet@<org_id>/backend@<repo_id>:ref:refs/heads/<branch>"처럼
# 불변 숫자 ID가 섞인 형식으로 나옴 — 처음엔 이 ID 부분을 와일드카드(@*)로 열어뒀었는데,
# 그러면 "qKet 조직을 지우고 다른 사람이 같은 이름으로 새로 만들어도 매칭되는" 이름 재사용
# 취약점이 다시 열려버림(불변 ID를 쓰는 이유 자체를 무력화). 그래서 와일드카드 대신
# github_owner_id/repository_id로 실제 값을 정확히 박아넣음.
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

    # job_workflow_ref 단독 테스트(2026-08-07)도 Not authorized로 실패해서 sub로 복구함.
    # aud/sub 말고 다른 claim은 뭘 걸든(repository/ref/job_workflow_ref, 단독이든 조합이든)
    # 전부 실패 — troubleshooting/github-actions-oidc-not-authorized.md 참고.
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

# 2026-08-11: frontend CI가 빌드 직전에 NEXT_PUBLIC_TOSS_CLIENT_KEY를 Secrets Manager에서
# 직접 가져가야 해서, frontend role에만 이 권한을 추가함(backend는 시크릿을 CI에서 안 씀 —
# ESO가 런타임에 대신 처리하므로). 정확한 시크릿 ARN 대신 이름 prefix + 와일드카드를 쓴 이유:
# 이 시크릿은 04_data(다른 root, workspace별로 release/prod 두 번 생성됨)가 만드는데,
# 03_registry가 04_data의 상태를 직접 참조하면 새로운 root 간 의존관계가 생기고 release/prod
# 중 뭘 참조할지도 애매해짐. Secrets Manager ARN은 이름 뒤에 AWS가 무작위 6자리를 붙이는
# 형식이라("team5-qket-external-api-release-AbCdEf"), 이름 prefix 와일드카드로 release/prod
# 둘 다 정확히, 그리고 딱 이 용도의 시크릿만 커버 가능(다른 시크릿엔 접근 불가).
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
