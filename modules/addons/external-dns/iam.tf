# ── ExternalDNS용 IRSA 역할 ──
# kube-system 네임스페이스의 external-dns 서비스어카운트만 이 역할을 assume 가능
data "aws_iam_policy_document" "external_dns_assume" {
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
      values   = ["system:serviceaccount:kube-system:external-dns"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(var.oidc_provider_url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "external_dns" {
  name               = "${var.project_name}-external-dns-role"
  assume_role_policy = data.aws_iam_policy_document.external_dns_assume.json
}

# 공유 AWS 계정이라(다른 팀들 도메인도 같은 계정에 있음) ChangeResourceRecordSets는
# 우리 zone(var.hosted_zone_id) 하나로만 정확히 좁힘 — 다른 팀 도메인 레코드를 실수로도
# 못 건드리게. List* 계열은 Route53 자체가 리소스 단위 스코프를 지원 안 해서 "*"로 둠
# (조회만 가능, 아무것도 못 바꿈 — ExternalDNS가 기존 레코드 목록을 알아야 sync 가능하므로 필요).
data "aws_iam_policy_document" "external_dns" {
  statement {
    effect    = "Allow"
    actions   = ["route53:ChangeResourceRecordSets"]
    resources = ["arn:aws:route53:::hostedzone/${var.hosted_zone_id}"]
  }

  statement {
    effect = "Allow"
    actions = [
      "route53:ListHostedZones",
      "route53:ListResourceRecordSets",
      "route53:ListTagsForResource",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "external_dns" {
  name   = "${var.project_name}-external-dns-policy"
  role   = aws_iam_role.external_dns.id
  policy = data.aws_iam_policy_document.external_dns.json
}
