# IRSA(서비스어카운트별 IAM Role) 범용 팩토리 
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
