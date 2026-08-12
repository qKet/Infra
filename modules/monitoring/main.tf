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

  # 대시보드를 git(ConfigMap)에서 자동으로 읽어오게 함 — sidecar 컨테이너가
  # grafana_dashboard=1 라벨 붙은 ConfigMap을 감지해서 자동 로드. EKS를 destroy/재생성해도
  # 이 helm_release만 다시 apply하면 대시보드가 그대로 돌아옴(02_k8s-addon/main.tf의
  # kubernetes_config_map.grafana_dashboards가 실제 ConfigMap을 공급).
  set {
    name  = "grafana.sidecar.dashboards.enabled"
    value = "true"
  }

  set {
    name  = "grafana.sidecar.dashboards.label"
    value = "grafana_dashboard"
  }

  # Prometheus가 수집한 지표를 AMP(Amazon Managed Prometheus)로 원격 저장 — EKS를
  # destroy/재생성해도 지표 히스토리가 안 없어지게 함(일반 EBS는 PVC가 클러스터랑 같이
  # 삭제되면서 볼륨도 같이 지워져서 이 문제를 못 풂 — 01_infrastructure/monitoring.tf 참고).
  set {
    name  = "prometheus.serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = var.prometheus_irsa_role_arn
  }

  set {
    name  = "prometheus.prometheusSpec.remoteWrite[0].url"
    value = var.amp_remote_write_endpoint
  }

  set {
    name  = "prometheus.prometheusSpec.remoteWrite[0].sigv4.region"
    value = var.aws_region
  }

  # Grafana가 AMP를 직접 조회하게 함 — 위 remoteWrite는 "보내는" 설정일 뿐이고, 이게 없으면
  # Grafana는 여전히 로컬(클러스터 안) Prometheus만 봐서 EKS 재생성 시 과거 그래프가 끊겨 보임
  # (iam.tf의 grafana_amp_query 정책이 필요 권한 부여).
  #
  # 범용 "prometheus" 타입 + sigV4Auth 조합으로 처음 시도했다가 AWS가
  # "Credential should be scoped to correct service: 'aps'"로 거부하는 문제를 겪음(2026-08-12)
  # — Grafana의 범용 SigV4 서명 미들웨어가 AMP(aps) 서비스명을 못 알아봄. 대신 AWS가 공식으로
  # 만든 AMP 전용 플러그인(grafana-amazonprometheus-datasource)으로 교체 — 이건 서비스명을
  # 하드코딩해서 알고 있어서 이 문제 자체가 없음.
  set {
    name  = "grafana.plugins[0]"
    value = "grafana-amazonprometheus-datasource"
  }

  set {
    name  = "grafana.additionalDataSources[0].name"
    value = "AMP"
  }

  set {
    name  = "grafana.additionalDataSources[0].type"
    value = "grafana-amazonprometheus-datasource"
  }

  set {
    name  = "grafana.additionalDataSources[0].url"
    value = var.amp_query_endpoint
  }

  set {
    name  = "grafana.additionalDataSources[0].access"
    value = "proxy"
  }

  set {
    name  = "grafana.additionalDataSources[0].jsonData.authType"
    value = "default"
  }

  set {
    name  = "grafana.additionalDataSources[0].jsonData.defaultRegion"
    value = var.aws_region
  }
}
