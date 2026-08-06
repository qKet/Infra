output "security_group_ids" {
  description = "생성된 보안그룹의 {key => id} 맵"
  value       = { for k, sg in aws_security_group.this : k => sg.id }
}
