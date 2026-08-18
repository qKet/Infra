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

output "ses_identity_arn" {
  description = "예매 오픈 알림 발신 도메인 identity ARN — 04_data가 remote_state로 읽어서 Lambda 발송 권한에 씀"
  value       = module.ses.identity_arn
}

output "argocd_notifications_secret_arn" {
  description = "ArgoCD 알림 Gmail 자격증명 Secrets Manager ARN — 02_k8s-addon이 remote_state로 읽어서 ESO(ExternalSecret)에 씀"
  value       = aws_secretsmanager_secret.argocd_notifications.arn
}