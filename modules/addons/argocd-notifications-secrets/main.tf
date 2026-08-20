# ArgoCD 알림용 SecretStore/ExternalSecret을 kubectl_manifest 대신 helm_release로 설치.
#
# 예전엔 kubectl_manifest.argocd_notifications_secret_store/_external_secret이었는데, 이
# 리소스 타입도 kubernetes_manifest와 마찬가지로 terraform plan 시점에 CRD(external-secrets.io)가
# 클러스터에 이미 있는지 확인한다. ESO는 04_data(다른 root)가 설치하는데, 확립된 apply 순서
# (infrastructure→k8s-addon→data)상 k8s-addon이 먼저 돌아서 이 확인이 매번 실패했다(2일 재현,
# CLAUDE_LLM_WIKI troubleshooting/crd-not-yet-installed-on-fresh-apply 참고).
#
# helm_release로 바꾼다고 이 cross-root 순서 문제 자체가 없어지진 않는다 — ESO가 04_data라는
# "다른 root"에 있어서, 같은 root 안에서만 유효한 "Helm이 crds/를 templates/보다 먼저 설치"
# 보장이 여기엔 적용 안 됨. 그래도 바꾸는 이유: kubectl_manifest는 plan 단계에서 확인하다 실패해서
# "02_k8s-addon 전체 plan/apply가 통째로 막힘"이었는데, helm_release는 plan 단계 확인이 아예
# 없어서 ESO가 아직 없어도 plan은 항상 성공하고, apply 시에도 이 helm_release 하나만 실패할 뿐
# 나머지 무관한 리소스는 정상 적용된다 — 실패 범위가 훨씬 좁아짐. 04_data의 module.eso를 먼저
# apply해야 하는 런북 절차(daily-infrastructure-toggle) 자체는 여전히 필요하다.
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
