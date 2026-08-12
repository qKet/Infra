# NOTI01_ALERT01(취소표 알림) 큐. backend가 publish, Lambda(cancel-alert-mailer)가 consume.
# DLQ를 둬서 Lambda가 3번 연속 실패하는 메시지(예: SES 쪽 일시 장애)는 무한 재시도로 숨어있지 않고
# 눈에 보이는 곳(DLQ)에 쌓이게 함 — 나중에 CloudWatch 알람 붙일 때 이 DLQ 길이를 보면 됨.
resource "aws_sqs_queue" "dlq" {
  name                      = "${var.project_name}-cancel-alert-dlq-${var.environment}"
  message_retention_seconds = 1209600 # 14일(SQS 최대치) — 원인 파악할 시간 넉넉히 확보
}

resource "aws_sqs_queue" "this" {
  name = "${var.project_name}-cancel-alert-${var.environment}"

  # Lambda 처리 시간(SES 호출 포함)보다 넉넉해야 처리 중에 다른 워커가 같은 메시지를 또 집어가는 걸 막음
  visibility_timeout_seconds = var.visibility_timeout_seconds

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 3
  })
}
