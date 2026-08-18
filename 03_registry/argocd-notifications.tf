# ArgoCD 알림(이메일) 발신 계정 자격증명 — 02_k8s-addon은 매일 밤 destroy되는 root라 여기
# (03_registry, 절대 안 지워짐)에 Secrets Manager로 저장해두고, 02_k8s-addon에서는
# ESO(ExternalSecret)로 이 값을 읽어와 Kubernetes Secret으로 동기화한다.
# 사람이 직접 발급받은 값이라 external_api_keys와 같은 이유로 lifecycle.ignore_changes로
# 보호 — 재적용 시 값이 빈 문자열로 덮어써지는 사고 방지.

resource "aws_secretsmanager_secret" "argocd_notifications" {
  name = "${var.project_name}-argocd-notifications"
}

resource "aws_secretsmanager_secret_version" "argocd_notifications" {
  secret_id = aws_secretsmanager_secret.argocd_notifications.id
  secret_string = jsonencode({
    email-username = var.notification_gmail_username
    email-password = var.notification_gmail_app_password
  })

  lifecycle {
    ignore_changes = [secret_string]
  }
}