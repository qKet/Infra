# grafana.jun979.click/cd.jun979.click/dev.jun979.click 공유 admin Gateway. dev(release)는
# "개발 서버는 관리자만" 방침에 따라 공개 ALB가 아닌 여기로 옮겨옴.
#
# gateway_api_crds/alb_controller/gateway_api_faro 다음에 있어야 함(GatewayClass, LB/TG
# Configuration CRD, alloy-faro ReferenceGrant 필요) — 호출부에서 depends_on으로 강제.
#
# 인증서는 여기서 안 만듦 — 03_registry(영구)가 만든 걸 remote_state로 읽어서 넘김. 이 모듈은
# 매일 밤 재생성돼서 여기서 만들면 매일 DNS 검증을 새로 거쳐야 함.
resource "helm_release" "gateway_api_admin" {
  name      = "gateway-api-admin"
  chart     = "${path.module}/chart"
  namespace = "kube-system"

  set_list {
    name  = "admin.allowedCidrs"
    value = var.admin_allowed_cidrs
  }

  set {
    name  = "admin.grafana.hostname"
    value = var.grafana_hostname
  }

  set {
    name  = "admin.grafana.certificateArn"
    value = var.grafana_certificate_arn
  }

  set {
    name  = "admin.argocd.hostname"
    value = var.argocd_hostname
  }

  set {
    name  = "admin.argocd.certificateArn"
    value = var.argocd_certificate_arn
  }

  set {
    name  = "admin.dev.hostname"
    value = var.dev_hostname
  }

  set {
    name  = "admin.dev.certificateArn"
    value = var.dev_certificate_arn
  }
}
