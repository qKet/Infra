# grafana.jun979.click/cd.jun979.click/dev.jun979.click 공유 admin Gateway — 오늘
# admin-ingress.tf의 kubernetes_ingress_v1.grafana/argocd를 대체하고, dev(release)도 공개
# ALB(gateway-api-app)에서 옮겨온다("개발 서버는 관리자만 들어가야 한다", 2026-08-20 결정).
#
# module.gateway_api_crds "다음"(GatewayClass 필요), module.alb_controller "다음"
# (LoadBalancerConfiguration/TargetGroupConfiguration CRD 필요), module.gateway_api_faro
# "다음"(dev의 /collect 라우팅이 쓰는 alloy-faro ReferenceGrant 필요) — 호출부
# (02_k8s-addon/main.tf)에서 depends_on으로 강제한다.
#
# 인증서는 여기서 안 만듦 — 03_registry(영구)가 만든 걸 호출부가 remote_state로 읽어서 넘겨줌.
# 이 모듈(02_k8s-addon 소속)은 매일 밤 destroy/재생성돼서, 여기서 인증서를 만들면 매일 아침
# DNS 검증을 새로 거쳐야 함(수 분간 HTTPS 불가) — 그래서 plain 변수로만 받음.
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
