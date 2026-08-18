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

# SQS SendMessage 권한들(예매 오픈 알림, 개인 알림)은 여기 안 두고 전부 04_data/main.tf에서
# backend_role_name 출력값을 받아 붙임 — 역할을 만드는 이 모듈이 "큐가 몇 개 있는지"까지 알 필요가
# 없게(storage 모듈이 큐 추가/변경 때마다 같이 바뀌는 걸 방지), 큐를 정의하는 쪽이 직접 attach.

resource "kubernetes_service_account" "backend" {
  metadata {
    name      = "qket-backend"
    namespace = var.namespace
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.backend.arn
    }
  }
}
