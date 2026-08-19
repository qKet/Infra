# Promtail — 각 EKS 노드에 DaemonSet(노드마다 파드 1개씩)으로 떠서, 그 노드 위 모든 파드가
# stdout/stderr로 찍는 로그를 자동으로 긁어 Loki로 보내는 역할. 앱 코드는 그냥 System.out/
# console.log로 찍기만 하면 되고, "어떻게 Loki까지 전달되는지"는 신경 안 써도 됨 —
# Prometheus의 node-exporter(지표를 노드마다 긁어옴)랑 같은 역할을 로그에 대해 하는 셈.
#
# IAM 권한 불필요 — Loki(클러스터 안 서비스)로만 보내고 AWS API를 직접 호출하지 않음.
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
            # module.loki가 SingleBinary 모드로 설치되면서 만드는 클러스터 내부 서비스.
            # 실제 서비스 이름은 릴리스 이름(loki) 그대로 노출됨 — helm_release.loki 적용 후
            # `kubectl get svc -n monitoring`으로 정확한 이름을 한 번 확인해서, 다르면 여기 endpoint만 바꾸면 됨.
            url = "http://loki.monitoring.svc.cluster.local:3100/loki/api/v1/push"
          }
        ]
      }
    })
  ]
}
