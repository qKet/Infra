output "ecr_repository_url" {
  description = "ECR 저장소 URI (CI가 docker push할 대상)"
  value       = module.ecr.repository_url
}

output "ecr_repository_name" {
  description = "ECR 저장소 이름"
  value       = module.ecr.repository_name
}

output "ecr_repository_arn" {
  description = "ECR 저장소 ARN"
  value       = module.ecr.repository_arn
}

output "github_actions_role_arns" {
  description = "GitHub Actions CI가 assume할 role ARN — 각 레포 GitHub Secrets(AWS_GITHUB_ACTIONS_ROLE_ARN)에 등록"
  value       = module.github_actions_oidc.role_arns
}

output "amp_workspace_arn" {
  description = "AMP workspace ARN — Grafana 쿼리 권한(IAM policy resource)에 사용"
  value       = aws_prometheus_workspace.this.arn
}

output "amp_remote_write_endpoint" {
  description = "Prometheus remoteWrite 설정에 넣을 AMP 엔드포인트 (module.monitoring values용)"
  value       = "${aws_prometheus_workspace.this.prometheus_endpoint}api/v1/remote_write"
}

output "amp_query_endpoint" {
  description = "Grafana가 AMP를 Prometheus 데이터소스로 조회할 때 쓸 엔드포인트"
  value       = aws_prometheus_workspace.this.prometheus_endpoint
}
