# Gateway API 마이그레이션 1단계 파일럿 오브젝트(Gateway/HTTPRoute/LoadBalancerConfiguration/
# TargetGroupConfiguration) — 이 모듈은 반드시 module.alb_controller와 module.gateway_api_crds
# "이후"에 apply돼야 한다. 호출부(02_k8s-addon/main.tf)에서 depends_on으로 강제한다.
#
# module.gateway_api_crds와 순서를 반대로(먼저 CRD/GatewayClass, 나중에 alb_controller, 그 다음
# 이 모듈) 나눠놓은 이유: ALB Controller는 부팅 시점에 딱 한 번 Gateway API CRD 존재 여부를 확인해서
# ALBGatewayAPI 기능을 켤지 말지 정한다(2026-08-20 실제로 겪음 — CRD가 컨트롤러 부팅 "이후"에
# 설치되니까 "Disabling ALBGatewayAPI: missing required CRDs" 로그를 남기고 그 파드가 살아있는 동안
# 계속 비활성 상태로 남았고, kubectl rollout restart로 재부팅해서야 정상화됨). 그래서 CRD가
# alb_controller보다 먼저 있어야 하고, 이 파일럿 오브젝트는 그 알b_controller가 뜬 "다음"에
# 있어야 한다 — 두 요구사항이 서로 반대 방향이라 모듈을 셋으로 쪼갠 것.
resource "helm_release" "gateway_api_pilot" {
  name      = "gateway-api-pilot"
  chart     = "${path.module}/chart"
  namespace = "kube-system"

  set {
    name  = "pilot.enabled"
    value = var.pilot_enabled
  }
}
