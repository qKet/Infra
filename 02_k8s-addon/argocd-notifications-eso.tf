# ArgoCD 알림용 Gmail 자격증명을 ESO로 동기화 — SecretStore/ExternalSecret 정의는
# modules/addons/argocd-notifications-secrets 참고.
#
# 2026-08-20: kubectl_manifest 2개(argocd_notifications_secret_store/_external_secret)에서
# helm_release 기반 모듈로 전환 — kubectl_manifest는 plan 시점에 external-secrets.io CRD가
# 클러스터에 이미 있는지 확인하는데, 그 CRD는 04_data(다른 root)의 module.eso가 설치해서
# 확립된 apply 순서(infrastructure→k8s-addon→data)상 순서가 어긋나 매번 실패했었다(2일 연속
# 재현, CLAUDE_LLM_WIKI troubleshooting/crd-not-yet-installed-on-fresh-apply 참고).
#
# ⚠️ helm_release로 바꿔도 04_data의 module.eso를 먼저 apply해야 하는 런북 절차
# (daily-infrastructure-toggle) 자체는 여전히 필요하다 — ESO가 "다른 root"에 있는 cross-root
# 순서 문제까지 없애주진 않는다. 이번 전환으로 없어지는 건 "ESO가 아직 없으면 02_k8s-addon
# 전체 plan/apply가 통째로 막히던 것"뿐 — 이제는 이 helm_release 하나만 실패하고 나머지 무관한
# 리소스는 정상 적용된다. 자세한 내용은 modules/addons/argocd-notifications-secrets/chart/
# Chart.yaml 참고.
module "argocd_notifications_secrets" {
  source = "../modules/addons/argocd-notifications-secrets"

  aws_region = var.aws_region
  secret_arn = data.terraform_remote_state.registry.outputs.argocd_notifications_secret_arn

  depends_on = [helm_release.argocd]
}
