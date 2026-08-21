# ── ESO 컨트롤러용 IRSA 역할 ──
# 기본 Helm 차트 기준 네임스페이스/서비스어카운트 이름: external-secrets / external-secrets.
# SecretStore가 serviceAccountRef를 따로 지정하지 않으면 ESO는 컨트롤러 자신의 서비스어카운트
# (=이 역할)로 AWS를 호출함 — 즉 release/prod를 포함해 클러스터 전체의 모든 SecretStore가
# 결국 이 역할 하나의 권한만 사용함. 그래서 각 환경(04_data)이 자기 시크릿 ARN만큼 인라인 정책을
# 이 역할에 추가로 붙이는 구조가 됨(modules/addons/eso/iam.tf의 aws_iam_role_policy 참고, role은
# var.eso_role_name으로 이름만 참조).
data "aws_iam_policy_document" "assume" {
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

resource "aws_iam_role" "this" {
  name               = "${var.project_name}-eso-role"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

# 이 root(02_k8s-addon) 안에서만 필요한 시크릿(예: ArgoCD 알림용 Gmail 자격증명 — 같은 root의
# module.argocd 안 notifications-secrets가 argocd 네임스페이스에서 이 컨트롤러로 동기화함)을
# 위한 자리. 04_data처럼 별도 root가 붙이는 정책과 이름만 겹치지 않으면 되므로, 여기 것과
# modules/addons/eso의 것은 서로 다른 aws_iam_role_policy 리소스로 안전하게 공존함.
data "aws_iam_policy_document" "extra" {
  count = length(var.extra_secret_arns) > 0 ? 1 : 0

  statement {
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]
    resources = var.extra_secret_arns
  }
}

resource "aws_iam_role_policy" "extra" {
  count = length(var.extra_secret_arns) > 0 ? 1 : 0

  name   = "${var.project_name}-eso-secrets-read-k8s-addon"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.extra[0].json
}
