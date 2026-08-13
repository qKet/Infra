# 백엔드 파드가 S3에 포스터 이미지를 업로드(PutObject)할 때 쓰는 IRSA.
data "aws_iam_policy_document" "backend_assume" {
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
      values   = ["system:serviceaccount:${var.namespace}:qket-backend"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(var.oidc_provider_url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "backend" {
  name               = "${var.project_name}-backend-role-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.backend_assume.json
}

# 딱 이 버킷에 PutObject만 
data "aws_iam_policy_document" "backend_s3" {
  statement {
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.posters.arn}/*"]
  }
}

resource "aws_iam_role_policy" "backend_s3" {
  name   = "${var.project_name}-backend-s3-${var.environment}"
  role   = aws_iam_role.backend.id
  policy = data.aws_iam_policy_document.backend_s3.json
}

resource "kubernetes_service_account" "backend" {
  metadata {
    name      = "qket-backend"
    namespace = var.namespace
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.backend.arn
    }
  }
}
