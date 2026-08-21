# Gateway API 실제 서비스 오브젝트(Gateway/HTTPRoute/LoadBalancerConfiguration/
# TargetGroupConfiguration) — release/prod 각 환경마다 02_k8s-addon/main.tf에서 이 모듈을
# for_each로 하나씩 인스턴스화한다. module.gateway_api_crds와 반대로, 이 모듈은
# module.alb_controller "다음"에 있어야 한다(그 컨트롤러 자신의 Helm 차트가
# LoadBalancerConfiguration/TargetGroupConfiguration CRD를 제공하기 때문 —
# modules/addons/gateway-api-crds/main.tf 주석 참고).
#
# Helm 릴리즈 이름에 env를 넣는 이유 — for_each로 이 모듈이 release/prod 두 번 인스턴스화되는데,
# 릴리즈 이름이 같으면(둘 다 kube-system 네임스페이스) Helm이 같은 릴리즈로 착각해서 충돌한다.
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
