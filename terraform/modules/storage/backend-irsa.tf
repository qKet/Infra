# 백엔드 파드가 S3에 포스터 이미지를 업로드(PutObject)할 때 쓰는 IRSA.
# 코드(S3Config.java)가 S3Client에 자격증명을 직접 안 넣고 SDK 기본 체인을 쓰고 있어서,
# 이 서비스어카운트로만 떠주면 코드 수정 없이 바로 적용됨.
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

# 딱 이 버킷에 PutObject만 — 실제 코드(CommonServiceImpl)가 쓰는 딱 그 동작만 허용 (최소 권한)
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
