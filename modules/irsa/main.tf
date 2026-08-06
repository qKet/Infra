# IRSA(서비스어카운트별 IAM Role) 범용 팩토리 — modules/security_group과 같은 for_each 패턴.
# EKS 클러스터/노드 role(modules/eks), EC2 instance role(modules/ec2)처럼 assume 방식 자체가
# 다른(서비스 프린시펄 assume, OIDC 아님) 것들은 여기 안 들어감 — 각자 모듈에 그대로 둠.
# 이 모듈은 sts:AssumeRoleWithWebIdentity + OIDC로 "특정 네임스페이스의 특정 ServiceAccount만"
# assume 가능한 Role만 다룬다.
data "aws_iam_policy_document" "assume" {
  for_each = var.roles

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
      values   = ["system:serviceaccount:${each.value.namespace}:${each.value.service_account}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(var.oidc_provider_url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  for_each = var.roles

  name               = "${var.project_name}-${each.key}-role"
  assume_role_policy = data.aws_iam_policy_document.assume[each.key].json
}

resource "aws_iam_role_policy" "this" {
  for_each = var.roles

  name   = "${var.project_name}-${each.key}-policy"
  role   = aws_iam_role.this[each.key].id
  policy = each.value.policy_json
}
