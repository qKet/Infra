output "role_arn" {
  description = "ExternalDNS IRSA IAM 역할 ARN"
  value       = aws_iam_role.external_dns.arn
}
