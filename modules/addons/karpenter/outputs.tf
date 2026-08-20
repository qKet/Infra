# 2단계(Helm 설치, EC2NodeClass/NodePool 작성)에서 참조할 값들
output "controller_role_arn" {
  description = "Karpenter 컨트롤러 파드가 assume할 IAM Role ARN — Helm values의 serviceAccount annotation에 사용"
  value       = aws_iam_role.karpenter_controller.arn
}

output "node_role_name" {
  description = "Karpenter가 새로 띄우는 EC2가 assume할 Role 이름 — EC2NodeClass의 role 필드에 사용"
  value       = aws_iam_role.karpenter_node.name
}

output "node_instance_profile_name" {
  description = "Node IAM Role을 감싼 Instance Profile 이름"
  value       = aws_iam_instance_profile.karpenter_node.name
}

output "interruption_queue_name" {
  description = "인터럽션 SQS 큐 이름 — Helm values의 settings.interruptionQueue에 사용"
  value       = aws_sqs_queue.karpenter_interruption.name
}
