# backend Prometheus 스크랩 설정(ServiceMonitor)을 kubernetes_manifest 대신 helm_release로 설치 —
# kubernetes_manifest는 plan 시점에 CRD 존재를 확인해서, 매일 밤 destroy→재생성되는 구조와
# 안 맞았음. helm_release는 그 문제가 없어서 module.monitoring에 depends_on만 걸면 충분.
resource "helm_release" "backend_servicemonitor" {
  name      = "backend-servicemonitor"
  chart     = "${path.module}/chart"
  namespace = "monitoring"
}
