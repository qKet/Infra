# 범용 SQS 소비 + SES 발송 Lambda 모듈. 
data "archive_file" "this" {
  type        = "zip"
  source_dir  = var.source_dir
  output_path = "${path.module}/.build/${var.name}.zip"
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
  name               = "${var.project_name}-${var.name}-role-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

# CloudWatch Logs 기본 실행 로그 — AWS 관리형 정책
resource "aws_iam_role_policy_attachment" "logs" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# SES identity ARN 
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
    # IAM Resource 매칭은 SES가 그 순간 어떤 identity를 검사하느냐에 따라 달라짐 — from_email 주소가
    # 그 자체로 별도 identity로 검증돼 있으면 주소 ARN을, 도메인만 검증돼 있으면 도메인 ARN을 검사한다
    # (실제로 SES identity 구성이 바뀌면서 두 경우를 다 겪었음: AccessDeniedException 리소스가
    # identity/noreply@jun979.click ↔ identity/jun979.click 사이를 오갔음). 어느 쪽이 되든 막히지
    # 않게 도메인 ARN과 발신주소 ARN을 둘 다 허용.
    resources = [
      "arn:aws:ses:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:identity/${var.ses_domain}",
      "arn:aws:ses:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:identity/${var.from_email}",
    ]
  }
}

resource "aws_iam_role_policy" "permissions" {
  name   = "${var.project_name}-${var.name}-${var.environment}"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.permissions.json
}

resource "aws_lambda_function" "this" {
  function_name = "${var.project_name}-${var.name}-${var.environment}"
  role          = aws_iam_role.this.arn
  handler       = "index.handler"
  runtime       = var.runtime
  timeout       = var.timeout

  filename         = data.archive_file.this.output_path
  source_code_hash = data.archive_file.this.output_base64sha256

  environment {
    variables = {
      FROM_EMAIL = var.from_email
    }
  }
}

# ReportBatchItemFailures를 쓰면 배치 안에서 실패한 메시지만 재시도됨(전체 배치를 실패 처리하면
# 이미 성공한 메일도 재발송될 수 있음) — 핸들러가 이 응답 형태를 지원할 때만 켜야 함(report_batch_item_failures)
resource "aws_lambda_event_source_mapping" "sqs" {
  event_source_arn        = var.queue_arn
  function_name           = aws_lambda_function.this.arn
  batch_size              = var.batch_size
  function_response_types = var.report_batch_item_failures ? ["ReportBatchItemFailures"] : null
}
