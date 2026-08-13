output "role_arns" {
  description = "생성된 IRSA Role의 {key => ARN} 맵"
  value       = { for k, r in aws_iam_role.this : k => r.arn }
}

output "role_names" {
  description = "생성된 IRSA Role의 {key => 이름} 맵"
  value       = { for k, r in aws_iam_role.this : k => r.name }
}
