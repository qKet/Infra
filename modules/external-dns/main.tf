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

# ── ExternalDNS 설치 (Helm) ──
resource "helm_release" "external_dns" {
  name       = "external-dns"
  repository = "https://kubernetes-sigs.github.io/external-dns/"
  chart      = "external-dns"
  namespace  = "kube-system"

  set {
    name  = "provider"
    value = "aws"
  }

  set {
    name  = "aws.region"
    value = var.aws_region
  }

  # 이중 방어: IAM이 이미 hosted_zone_id 하나로 권한을 좁혀놨지만, 이 필터도 같이 걸어서
  # 혹시 모를 실수(다른 zone에 있는 레코드 건드리기)를 애초에 후보에서 제외함.
  set {
    name  = "domainFilters[0]"
    value = var.domain_filter
  }

  # upsert-only: Ingress가 지워져도 DNS 레코드는 안 지움 — 공유 계정에서 실수로 남의 레코드까지
  # 건드리는 것보다, 안 쓰는 레코드가 좀 남는 게 안전하다고 판단. 필요해지면 "sync"로 바꿀 것.
  set {
    name  = "policy"
    value = "upsert-only"
  }

  # 같은 zone을 여러 ExternalDNS 인스턴스가 공유할 경우 TXT 레코드로 소유권 구분하는 값.
  set {
    name  = "txtOwnerId"
    value = var.project_name
  }

  set {
    name  = "serviceAccount.create"
    value = "true"
  }

  set {
    name  = "serviceAccount.name"
    value = "external-dns"
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.external_dns.arn
  }

  depends_on = [
    aws_iam_role_policy.external_dns,
  ]
}
