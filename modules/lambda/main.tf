# 예매 오픈 알림 발송 Lambda. 코드는 Infra/lambda/open-alert-mailer에 있고,
# terraform apply 전에 그 디렉토리에서 `npm install --production`을 먼저 돌려둬야 한다 — Lambda
# Node.js 20.x 런타임은 aws-sdk를 더 이상 기본 번들하지 않아서 @aws-sdk/client-sesv2를 직접 담아야 함
# (archive_file이 source_dir을 있는 그대로 zip으로 묶으므로 node_modules가 없으면 그냥 안 담김 → 런타임에 모듈을 못 찾아 즉시 실패).
data "archive_file" "this" {
  type        = "zip"
  source_dir  = var.source_dir
  output_path = "${path.module}/.build/open-alert-mailer.zip"
}

data "aws_iam_policy_document" "assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  name               = "${var.project_name}-open-alert-mailer-role-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

# CloudWatch Logs 기본 실행 로그 — AWS 관리형 정책
resource "aws_iam_role_policy_attachment" "logs" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# SES 도메인 identity ARN — 계정ID+리전+도메인명으로 완전히 결정되는 값(랜덤 접미사 없음)이라
# 데이터소스로 직접 계산 가능. 도메인 자체의 인증(aws_ses_domain_identity)은 03_registry/ses.tf가
# 관리(계정당 도메인 인증은 한 번만 해야 해서 여기 모듈에 따로 안 둠) — modules/messaging/iam.tf와
# 동일 패턴. 03_registry가 이 도메인을 실제로 인증해뒀다는 전제이고, 순서가 어긋나면 apply 시점에
# "그런 identity 없음" 에러로 바로 드러남.
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# 딱 이 큐에서 소비 + 딱 이 SES identity로만 발송 — 최소 권한(backend-irsa.tf의 S3 정책과 같은 원칙)
data "aws_iam_policy_document" "permissions" {
  statement {
    effect    = "Allow"
    actions   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
    resources = [var.queue_arn]
  }

  statement {
    effect  = "Allow"
    actions = ["ses:SendEmail"]
    resources = [
      "arn:aws:ses:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:identity/${var.ses_domain}",
    ]
  }
}

resource "aws_iam_role_policy" "permissions" {
  name   = "${var.project_name}-open-alert-mailer-${var.environment}"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.permissions.json
}

resource "aws_lambda_function" "this" {
  function_name = "${var.project_name}-open-alert-mailer-${var.environment}"
  role          = aws_iam_role.this.arn
  handler       = "index.handler"
  runtime       = "nodejs20.x"
  timeout       = 10

  filename         = data.archive_file.this.output_path
  source_code_hash = data.archive_file.this.output_base64sha256

  environment {
    variables = {
      FROM_EMAIL = var.from_email
    }
  }
}

# SQS 이벤트소스 매핑 — batch_size 10, ReportBatchItemFailures로 배치 안에서 실패한 메시지만 재시도되게 함
# (전체 배치를 실패 처리하면 이미 성공한 메일도 재발송될 수 있음)
resource "aws_lambda_event_source_mapping" "sqs" {
  event_source_arn        = var.queue_arn
  function_name           = aws_lambda_function.this.arn
  batch_size              = 10
  function_response_types = ["ReportBatchItemFailures"]
}
