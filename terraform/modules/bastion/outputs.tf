output "instance_id" {
  description = "SSM 세션 연결에 쓸 bastion 인스턴스 ID (aws ssm start-session --target <이값>)"
  value       = aws_instance.ssm_bastion.id
}

output "security_group_id" {
  description = "bastion 보안그룹 ID — RDS/Redis 보안그룹에서 이 그룹발 인바운드를 허용해줘야 접속 가능"
  value       = aws_security_group.ssm_bastion.id
}
