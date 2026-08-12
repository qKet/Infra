data "archive_file" "email_verification" {
  type        = "zip"
  source_dir  = "${path.module}/lambda-src"
  output_path = "${path.module}/lambda-src.zip"
}

resource "aws_lambda_function" "email_verification" {
  function_name = "${var.project_name}-email-verification-${var.environment}"
  role          = aws_iam_role.lambda_email.arn
  handler       = "index.handler"
  runtime       = "nodejs22.x"
  timeout       = 30

  filename         = data.archive_file.email_verification.output_path
  source_code_hash = data.archive_file.email_verification.output_base64sha256

  # AWS_REGION은 Lambda 예약 환경변수라 직접 설정 불가 — 런타임이 자동으로 채워줌(코드도 이미
  # process.env.AWS_REGION을 그대로 씀). var.aws_region은 iam.tf의 SES ARN 계산에만 씀.
  environment {
    variables = {
      FROM_EMAIL = var.from_email
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_iam_role_policy.lambda_sqs,
    aws_iam_role_policy.lambda_ses,
  ]
}

# SQS에 메시지가 들어오면 자동으로 Lambda 호출 — 폴링 방식(Lambda가 SQS를 주기적으로 들여다봄,
# 별도 알림 인프라 불필요, batch_size만큼 모아서 한 번에 처리 가능하지만 여긴 1개씩 즉시 처리)
resource "aws_lambda_event_source_mapping" "sqs_trigger" {
  event_source_arn = aws_sqs_queue.email_verification.arn
  function_name    = aws_lambda_function.email_verification.arn
  batch_size       = 1
}
