# Grafana Alloy Faro(브라우저 수집 엔드포인트)를 release/prod HTTPRoute가 cross-namespace로
# 참조할 수 있게 하는 ReferenceGrant + TargetGroupConfiguration. env별 module.gateway_api_pilot
# 인스턴스에 안 넣고 여기 한 번만 만드는 이유는 chart/Chart.yaml 참고.
#
# module.alb_controller "다음"에 있어야 한다 — TargetGroupConfiguration CRD를 그 컨트롤러의
# 차트가 제공하기 때문(modules/addons/gateway-api-crds/main.tf 주석과 동일한 이유).
resource "helm_release" "gateway_api_faro" {
  name      = "gateway-api-faro"
  chart     = "${path.module}/chart"
  namespace = "kube-system"

  set_list {
    name  = "faro.allowedNamespaces"
    value = var.allowed_namespaces
  }
}
