# ── Lambda 실행 역할 ──
data "aws_iam_policy_document" "lambda_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda_email" {
  name               = "${var.project_name}-email-verification-lambda-role-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

# CloudWatch Logs 쓰기(AWS 관리형 기본 정책) — 이게 없으면 로그 자체가 안 남아서 디버깅 불가
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_email.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# SQS 소비 권한 — 이 큐 하나만 (event_source_mapping이 실제로 호출하는 API들)
data "aws_iam_policy_document" "lambda_sqs" {
  statement {
    effect = "Allow"
    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
    ]
    resources = [aws_sqs_queue.email_verification.arn]
  }
}

resource "aws_iam_role_policy" "lambda_sqs" {
  name   = "${var.project_name}-email-verification-lambda-sqs-${var.environment}"
  role   = aws_iam_role.lambda_email.id
  policy = data.aws_iam_policy_document.lambda_sqs.json
}

# SES 발송 권한 — 이 도메인 identity로만 보낼 수 있음(다른 팀이 검증해둔 도메인 도용 불가).
# SES 도메인 인증(aws_ses_domain_identity)은 여기가 아니라 03_registry에 있음 — 도메인 하나당
# 인증은 한 번만 해야 하는데, 이 모듈은 04_data에서 release/prod 두 번 호출되므로 여기 두면
# 같은 도메인을 두 번 인증하려다 충돌함. SES identity ARN은 계정/리전/도메인명으로 완전히
# 결정되는 값(랜덤 접미사 없음)이라, terraform_remote_state 없이 데이터소스로 직접 계산 가능
# (03_registry가 이 도메인을 실제로 인증해뒀다는 전제 — 순서 어긋나면 apply 시점에 그냥
# "그런 identity 없음" 에러로 바로 드러남).
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

data "aws_iam_policy_document" "lambda_ses" {
  statement {
    effect  = "Allow"
    actions = ["ses:SendEmail", "ses:SendRawEmail"]
    resources = [
      "arn:aws:ses:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:identity/${var.ses_domain}",
    ]
  }
}

resource "aws_iam_role_policy" "lambda_ses" {
  name   = "${var.project_name}-email-verification-lambda-ses-${var.environment}"
  role   = aws_iam_role.lambda_email.id
  policy = data.aws_iam_policy_document.lambda_ses.json
}
