# ArgoCD 알림용 SecretStore/ExternalSecret을 kubectl_manifest 대신 helm_release로 설치.
#
# 예전엔 kubectl_manifest.argocd_notifications_secret_store/_external_secret이었는데, 이
# 리소스 타입도 kubernetes_manifest와 마찬가지로 terraform plan 시점에 CRD(external-secrets.io)가
# 클러스터에 이미 있는지 확인한다. 그 시절엔 ESO를 04_data(다른 root)가 설치했는데, 확립된 apply
# 순서(infrastructure→k8s-addon→data)상 k8s-addon이 먼저 돌아서 이 확인이 매번 실패했다(2일 재현,
# CLAUDE_LLM_WIKI troubleshooting/crd-not-yet-installed-on-fresh-apply 참고).
#
# 2026-08-21: ESO 컨트롤러를 module.eso_controller(같은 root인 02_k8s-addon)로 옮기면서 이
# cross-root 순서 문제 자체가 해소됐다 — 이제 module.argocd가 depends_on=[module.eso_controller]로
# 같은 root 안에서 순서를 보장받는다(02_k8s-addon/main.tf 참고). helm_release로 바꿔둔 건 여전히
# 유지 — kubectl_manifest보다 실패 범위가 좁다는 장점(이 리소스 하나만 실패해도 나머지 무관한
# 리소스는 정상 적용됨)은 그대로 유효하다.
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
