output "queue_url" {
  description = "이메일 인증 요청 큐 URL — backend가 메시지 넣을 때 씀"
  value       = aws_sqs_queue.email_verification.id
}

output "queue_arn" {
  description = "이메일 인증 요청 큐 ARN"
  value       = aws_sqs_queue.email_verification.arn
}

output "lambda_function_arn" {
  description = "이메일 인증 발송 Lambda ARN"
  value       = aws_lambda_function.email_verification.arn
}
