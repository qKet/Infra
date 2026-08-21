output "role_name" {
  description = "ESO 컨트롤러 IRSA IAM 역할 이름 — 04_data(release/prod)의 module.eso가 여기에 정책을 추가로 붙일 때 씀"
  value       = aws_iam_role.this.name
}

output "role_arn" {
  description = "ESO 컨트롤러 IRSA IAM 역할 ARN"
  value       = aws_iam_role.this.arn
}

output "namespace" {
  description = "ESO 컨트롤러가 설치된 네임스페이스"
  value       = helm_release.this.namespace
}
