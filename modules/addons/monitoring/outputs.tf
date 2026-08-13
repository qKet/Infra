output "grafana_role_arn" {
  description = "Grafana IRSA IAM 역할 ARN (CloudWatch 읽기 전용)"
  value       = aws_iam_role.grafana.arn
}
