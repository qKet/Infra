# backend Prometheus 스크랩 설정(ServiceMonitor)을 kubernetes_manifest 대신 helm_release로 설치.
#
# 예전엔 kubernetes_manifest.backend_service_monitor였는데, 이 리소스 타입은 terraform plan
# 시점에 ServiceMonitor CRD가 클러스터에 이미 등록돼 있는지 API 서버에 확인한다. 02_k8s-addon이
# 매일 밤 통째로 destroy→재생성되는 이 프로젝트 구조상 그 확인이 매번 실패해서 3일 연속 겪었다
# (CLAUDE_LLM_WIKI troubleshooting/crd-not-yet-installed-on-fresh-apply 참고, 매일 아침
# `-target=module.monitoring` 선(先)적용으로 우회하던 문제).
#
# helm_release는 plan 단계에서 차트 내용물의 kind/스키마를 전혀 확인하지 않으므로 이 문제 자체가
# 없다 — module.monitoring(kube-prometheus-stack, ServiceMonitor CRD 제공)에 depends_on만
# 걸어두면, 매일 아침 재적용될 때도 targeted apply 없이 그냥 terraform apply 한 번으로 끝난다.
resource "helm_release" "backend_servicemonitor" {
  name      = "backend-servicemonitor"
  chart     = "${path.module}/chart"
  namespace = "monitoring"
}
