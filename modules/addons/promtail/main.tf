# Promtail — 각 EKS 노드에 DaemonSet으로 떠서, 그 노드 위 모든 파드의 stdout/stderr 로그를
# 자동으로 긁어 Loki로 보냄(node-exporter의 로그 버전). IAM 권한 불필요 — 클러스터 내부로만 전송.
resource "helm_release" "promtail" {
  name             = "promtail"
  repository       = "https://grafana.github.io/helm-charts"
  chart            = "promtail"
  namespace        = "monitoring"
  create_namespace = true
  version          = "~> 6.16"

  values = [
    yamlencode({
      config = {
        clients = [
          {
            # module.loki(SingleBinary)가 만드는 클러스터 내부 서비스 — 릴리스 이름 그대로 노출됨.
            url = "http://loki.monitoring.svc.cluster.local:3100/loki/api/v1/push"
          }
        ]
      }
    })
  ]
}
