# 이 큐에 SendMessage 권한을 줄 역할 — sender_role_name을 안 넘기면 아예 안 만듦(이 큐를누가 쓰는지 몰라도 되는 경우도 있어서 선택적으로 둠).
# var.name(큐 용도 이름)이 이미 유일한 값이라 정책 이름 접미사로 그대로 씀 — 같은 role에 여러 큐 권한을 붙여도 안 겹침.
resource "aws_iam_role_policy" "sender" {
  count = var.sender_role_name != "" ? 1 : 0

  name   = "${var.project_name}-backend-sqs-${var.name}-${var.environment}"
  role   = var.sender_role_name
  policy = data.aws_iam_policy_document.sender[0].json
}

data "aws_iam_policy_document" "sender" {
  count = var.sender_role_name != "" ? 1 : 0

  statement {
    effect    = "Allow"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.this.arn]
  }
}
