# kube-prometheus-stack — Prometheus + Grafana + Alertmanager + node-exporter +
# kube-state-metrics를 한 번에 설치하는 커뮤니티 표준 차트. alb_controller/external_dns/eso랑
# 같은 패턴(IRSA + helm_release)으로 여기 모듈에 묶음.
#
# depends_on = [module.alb_controller]는 여기(모듈 안)가 아니라 이 모듈을 호출하는 쪽
# (02_k8s-addon/main.tf)에 걸어야 함 — 모듈 안에서는 다른 모듈을 참조할 수 없음. 그 depends_on이
# 필요한 이유: Prometheus/Grafana/Alertmanager/node-exporter가 전부 자기 Service를 만드는데,
# ALB Controller의 admission webhook이 아직 준비 안 된 타이밍에 걸리면 "no endpoints available
# for aws-load-balancer-webhook-service"로 실패한다(helm_release.argocd에서 실제로 겪은 문제와 동일).
resource "helm_release" "monitoring" {
  name             = "monitoring"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  namespace        = "monitoring"
  create_namespace = true

  # Grafana 서비스어카운트 이름을 release 이름에 안 묶이게 고정("grafana") — iam.tf의 IRSA
  # trust policy(sub 조건)가 이 이름을 정확히 참조하므로, 릴리스 이름이 바뀌어도 안 깨지게 함.
  set {
    name  = "grafana.serviceAccount.name"
    value = "grafana"
  }

  set {
    name  = "grafana.serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.grafana.arn
  }
}
