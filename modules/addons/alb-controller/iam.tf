# ── ALB Controller용 IRSA 역할 ──
# kube-system 네임스페이스의 aws-load-balancer-controller 서비스어카운트만 이 역할을 assume 가능
data "aws_iam_policy_document" "alb_controller_assume" {
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
      values   = ["system:serviceaccount:kube-system:aws-load-balancer-controller"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(var.oidc_provider_url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "alb_controller" {
  name               = "${var.project_name}-alb-controller-role"
  assume_role_policy = data.aws_iam_policy_document.alb_controller_assume.json
}

# AWS가 공식 배포하는 ALB Controller용 IAM 정책 — 직접 하드코딩하는 대신 원본을 그대로 받아와서 최신/정확성 보장
# (dev라 main 브랜치 참조, 나중에 안정성 원하면 특정 태그로 고정 권장)
data "http" "alb_controller_iam_policy" {
  url = "https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json"
}

resource "aws_iam_role_policy" "alb_controller" {
  name   = "${var.project_name}-alb-controller-policy"
  role   = aws_iam_role.alb_controller.id
  policy = data.http.alb_controller_iam_policy.response_body
}
