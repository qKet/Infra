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
