# Karpenter 인터럽션 큐 — 스팟 회수/유지보수/인스턴스 상태 변화 이벤트를 미리 받아서
# 노드가 실제로 죽기 전에 파드를 안전하게 다른 노드로 빼줄 수 있게 함(graceful drain).
# 이 큐가 없으면 스팟 인스턴스는 2분 경고 없이 그냥 죽는 것과 동일하게 처리됨.

resource "aws_sqs_queue" "karpenter_interruption" {
  name                      = "${var.project_name}-karpenter-interruption"
  message_retention_seconds = 300 # 5분 — 인터럽션 이벤트는 최신 상태만 의미 있음, 오래 쌓아둘 이유 없음

  sqs_managed_sse_enabled = true
}

# EventBridge가 이 큐로 메시지를 보낼 수 있게 허용 — 큐 자체의 리소스 정책
data "aws_iam_policy_document" "karpenter_interruption_queue" {
  statement {
    sid    = "AllowEventBridgeSend"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com", "sqs.amazonaws.com"]
    }

    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.karpenter_interruption.arn]
  }
}

resource "aws_sqs_queue_policy" "karpenter_interruption" {
  queue_url = aws_sqs_queue.karpenter_interruption.id
  policy    = data.aws_iam_policy_document.karpenter_interruption_queue.json
}

# ── EventBridge 규칙 4종 — 각 이벤트를 인터럽션 큐로 라우팅 ──

resource "aws_cloudwatch_event_rule" "karpenter_spot_interruption" {
  name = "${var.project_name}-karpenter-spot-interruption"
  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["EC2 Spot Instance Interruption Warning"]
  })
}

resource "aws_cloudwatch_event_rule" "karpenter_rebalance" {
  name = "${var.project_name}-karpenter-rebalance-recommendation"
  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["EC2 Instance Rebalance Recommendation"]
  })
}

resource "aws_cloudwatch_event_rule" "karpenter_instance_state_change" {
  name = "${var.project_name}-karpenter-instance-state-change"
  event_pattern = jsonencode({
    source      = ["aws.ec2"]
    detail-type = ["EC2 Instance State-change Notification"]
  })
}

resource "aws_cloudwatch_event_rule" "karpenter_scheduled_change" {
  name = "${var.project_name}-karpenter-scheduled-change"
  event_pattern = jsonencode({
    source      = ["aws.health"]
    detail-type = ["AWS Health Event"]
  })
}

resource "aws_cloudwatch_event_target" "karpenter_spot_interruption" {
  rule = aws_cloudwatch_event_rule.karpenter_spot_interruption.name
  arn  = aws_sqs_queue.karpenter_interruption.arn
}

resource "aws_cloudwatch_event_target" "karpenter_rebalance" {
  rule = aws_cloudwatch_event_rule.karpenter_rebalance.name
  arn  = aws_sqs_queue.karpenter_interruption.arn
}

resource "aws_cloudwatch_event_target" "karpenter_instance_state_change" {
  rule = aws_cloudwatch_event_rule.karpenter_instance_state_change.name
  arn  = aws_sqs_queue.karpenter_interruption.arn
}

resource "aws_cloudwatch_event_target" "karpenter_scheduled_change" {
  rule = aws_cloudwatch_event_rule.karpenter_scheduled_change.name
  arn  = aws_sqs_queue.karpenter_interruption.arn
}
