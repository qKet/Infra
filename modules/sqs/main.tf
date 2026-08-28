# 범용 SQS 큐 모듈 — backend가 publish, modules/lambda가 consume하는 알림성 큐에 공용으로 씀(예매 오픈 알림, 개인 알림 등)
# DLQ를 둬서 Lambda가 3번 연속 실패하는 메시지(예: SES 쪽 일시 장애)는 무한 재시도로 숨어있지 않고 눈에 보이는 곳(DLQ)에 쌓이게 함 — 나중에 CloudWatch 알람 붙일 때 이 DLQ 길이를 보면 됨.
resource "aws_sqs_queue" "dlq" {
  name                      = "${var.project_name}-${var.name}-dlq-${var.environment}"
  message_retention_seconds = 1209600 # 14일(SQS 최대치) — 원인 파악할 시간 넉넉히 확보
}

resource "aws_sqs_queue" "this" {
  name = "${var.project_name}-${var.name}-${var.environment}"

  # Lambda 처리 시간(SES 호출 포함)보다 넉넉해야 처리 중에 다른 워커가 같은 메시지를 또 집어가는 걸 막음
  visibility_timeout_seconds = var.visibility_timeout_seconds

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 3
  })
}
