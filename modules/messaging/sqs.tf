# 이메일 인증번호 발송 요청을 담는 큐 — backend가 여기 메시지를 넣으면 Lambda가 트리거되어 SES로 발송.
resource "aws_sqs_queue" "email_verification" {
  name = "${var.project_name}-email-verification-${var.environment}"

  # 발송 실패(예: SES 오류)가 반복되면 무한 재시도로 쌓이지 않게 DLQ로 격리
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.email_verification_dlq.arn
    maxReceiveCount     = 3
  })

  # Lambda 처리 시간(SES 호출 등) 감안 — Lambda 타임아웃(lambda.tf)보다 넉넉하게
  visibility_timeout_seconds = 60
}

resource "aws_sqs_queue" "email_verification_dlq" {
  name                      = "${var.project_name}-email-verification-dlq-${var.environment}"
  message_retention_seconds = 1209600 # 14일 — 실패 원인 조사할 시간 확보
}
