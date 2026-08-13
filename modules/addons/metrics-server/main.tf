# metrics-server — kubectl top, HPA/KEDA(CPU/메모리 트리거)가 공통으로 의존하는 CPU/메모리 지표 API
# (metrics.k8s.io). 2026-08-13: 이게 없어서 KEDA ScaledObject(cpu trigger)가 만든 HPA가
# "unable to fetch metrics from resource metrics API" 상태로 영원히 멈춰있던 걸 실측으로 발견 —
# 부하테스트 내내 replica가 4개에서 단 한 번도 안 늘어난 원인이 이거였음.
resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  namespace  = "kube-system"

  # EKS 워커 노드의 kubelet serving 인증서가 metrics-server가 기본적으로 신뢰하는 CA로
  # 서명돼있지 않은 경우가 많아서(EKS 기본 구성의 잘 알려진 제약), 이걸 안 켜면 스크래핑 자체가
  # "x509: cannot validate certificate"로 실패함. 클러스터 내부 통신이라 노출 위험은 없음.
  set {
    name  = "args[0]"
    value = "--kubelet-insecure-tls"
  }
}
