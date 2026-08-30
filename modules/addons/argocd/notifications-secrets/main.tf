# ArgoCD 알림용 SecretStore/ExternalSecret을 kubectl_manifest 대신 helm_release로 설치 —
# helm_release는 kubectl_manifest보다 실패 범위가 좁음(이 리소스만 실패해도 나머지는 정상 적용).
resource "helm_release" "argocd_notifications_secrets" {
  name      = "argocd-notifications-secrets"
  chart     = "${path.module}/chart"
  namespace = "argocd"

  set {
    name  = "awsRegion"
    value = var.aws_region
  }

  set {
    name  = "secretArn"
    value = var.secret_arn
  }
}
