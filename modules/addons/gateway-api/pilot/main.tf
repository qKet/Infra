# Gateway API 실제 서비스 오브젝트(Gateway/HTTPRoute/LoadBalancerConfiguration/
# TargetGroupConfiguration) — 02_k8s-addon/main.tf에서 env별로 for_each 인스턴스화. crds와
# 반대로 alb_controller 다음에 있어야 함(그 차트가 LB/TG Configuration CRD를 제공).
#
# Helm 릴리즈 이름에 env를 넣는 이유 — release/prod 둘 다 kube-system이라 이름이 같으면 충돌.
resource "helm_release" "gateway_api_pilot" {
  name      = "gateway-api-app-${var.env}"
  chart     = "${path.module}/chart"
  namespace = "kube-system"

  set {
    name  = "pilot.enabled"
    value = var.pilot_enabled
  }

  set {
    name  = "pilot.env"
    value = var.env
  }

  set {
    name  = "pilot.namespace"
    value = var.namespace
  }

  set {
    name  = "pilot.hostname"
    value = var.hostname
  }

  set {
    name  = "pilot.certificateArn"
    value = var.certificate_arn
  }

  set {
    name  = "pilot.loadBalancerName"
    value = var.load_balancer_name
  }
}
