# ── External Secrets Operator(ESO)용 IRSA 역할 ──
# 기본 Helm 차트 기준 네임스페이스/서비스어카운트 이름: external-secrets / external-secrets
data "aws_iam_policy_document" "eso_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(var.oidc_provider_url, "https://", "")}:sub"
      values   = ["system:serviceaccount:external-secrets:external-secrets"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(var.oidc_provider_url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eso" {
  name               = "${var.project_name}-eso-role"
  assume_role_policy = data.aws_iam_policy_document.eso_assume.json
}

# RDS 자동 생성 시크릿 + connection + external_api, 딱 이 세 개만 읽기 허용 (최소 권한)
data "aws_iam_policy_document" "eso_secrets_read" {
  statement {
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]
    resources = concat([
      var.rds_master_user_secret_arn,
      aws_secretsmanager_secret.connection.arn,
      aws_secretsmanager_secret.external_api.arn,
    ], var.extra_secret_arns)
  }
}

resource "aws_iam_role_policy" "eso_secrets_read" {
  name   = "${var.project_name}-eso-secrets-read"
  role   = aws_iam_role.eso.id
  policy = data.aws_iam_policy_document.eso_secrets_read.json
}