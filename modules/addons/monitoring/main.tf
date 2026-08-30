# kube-prometheus-stack — Prometheus + Grafana + Alertmanager + node-exporter +
# kube-state-metrics를 한 번에 설치하는 커뮤니티 표준 차트.
# depends_on = [module.alb_controller]는 호출부(02_k8s-addon/main.tf)에 걸어야 함 — 각 컴포넌트가
# 자기 Service를 만들어서 ALB Controller webhook 레이스(helm_release.argocd와 동일 이슈)가 있음.
resource "helm_release" "monitoring" {
  name             = "monitoring"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  namespace        = "monitoring"
  create_namespace = true

  # 서비스어카운트 이름 고정("grafana") — iam.tf의 IRSA trust policy가 이 이름을 참조함.
  set {
    name  = "grafana.serviceAccount.name"
    value = "grafana"
  }

  set {
    name  = "grafana.serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.grafana.arn
  }

  # 대시보드를 git(ConfigMap)에서 자동으로 읽어오게 함 — sidecar가 grafana_dashboard=1 라벨
  # 붙은 ConfigMap(아래 kubernetes_config_map.grafana_dashboards)을 감지해 자동 로드.
  set {
    name  = "grafana.sidecar.dashboards.enabled"
    value = "true"
  }

  set {
    name  = "grafana.sidecar.dashboards.label"
    value = "grafana_dashboard"
  }

  # Prometheus 지표를 AMP(Amazon Managed Prometheus)로 원격 저장 — EKS destroy/재생성에도
  # 히스토리가 안 사라지게 함(일반 EBS는 클러스터와 같이 삭제됨).
  set {
    name  = "prometheus.serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.prometheus.arn
  }

  set {
    name  = "prometheus.prometheusSpec.remoteWrite[0].url"
    value = var.amp_remote_write_endpoint
  }

  set {
    name  = "prometheus.prometheusSpec.remoteWrite[0].sigv4.region"
    value = var.aws_region
  }

  # Grafana가 AMP를 직접 조회하게 함(위 remoteWrite는 "보내는" 쪽일 뿐) — 범용 "prometheus"
  # 타입+sigV4Auth 조합은 AWS가 서비스명 불일치로 거부해서, AMP 전용 플러그인
  # (grafana-amazonprometheus-datasource)으로 교체함(iam.tf의 grafana_amp_query 정책 필요).
  set {
    name  = "grafana.grafana\\.ini.auth.sigv4_auth_enabled"
    value = "true"
  }

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

  # 서버 sigv4_auth_enabled만으로는 부족 — jsonData에도 명시해야 실제 서명이 붙음.
  set {
    name  = "grafana.additionalDataSources[0].jsonData.sigV4Auth"
    value = "true"
  }

  set {
    name  = "grafana.additionalDataSources[0].jsonData.sigV4Region"
    value = var.aws_region
  }

  # RDS/Redis 지표는 백엔드가 직접 노출 안 해서(HikariCP 제외) CloudWatch 데이터소스로 봄.
  set {
    name  = "grafana.additionalDataSources[1].name"
    value = "CloudWatch"
  }

  set {
    name  = "grafana.additionalDataSources[1].type"
    value = "cloudwatch"
  }

  set {
    name  = "grafana.additionalDataSources[1].jsonData.authType"
    value = "default"
  }

  set {
    name  = "grafana.additionalDataSources[1].jsonData.defaultRegion"
    value = var.aws_region
  }

  # Loki(로그 저장소) — 클러스터 내부 서비스라 IAM/인증 불필요, 내부 주소로 바로 연결.
  set {
    name  = "grafana.additionalDataSources[2].name"
    value = "Loki"
  }

  set {
    name  = "grafana.additionalDataSources[2].type"
    value = "loki"
  }

  set {
    name  = "grafana.additionalDataSources[2].url"
    value = "http://loki.monitoring.svc.cluster.local:3100"
  }

  set {
    name  = "grafana.additionalDataSources[2].access"
    value = "proxy"
  }
}

# Grafana 대시보드 정의를 git에 저장 — sidecar가 grafana_dashboard=1 라벨로 자동 로드.
# JSON은 Grafana UI의 dashboard settings > JSON Model에서 export한 것.
resource "kubernetes_config_map" "grafana_dashboards" {
  metadata {
    name      = "qket-grafana-dashboards"
    namespace = "monitoring"
    labels = {
      grafana_dashboard = "1"
    }
  }

  data = {
    # release/prod로 분리 — release는 dev-datastore로 옮겨가서 RDS/Redis CloudWatch 패널 제거.
    "qket-monitoring-release.json" = file("${path.module}/dashboards/qket-monitoring-release.json")
    "qket-monitoring-prod.json"    = file("${path.module}/dashboards/qket-monitoring-prod.json")
    # 백엔드/프론트(SSR)/브라우저(Faro) 로그를 패널로 한 화면에 고정. Browser Events 패널은
    # alloy-faro가 release/prod 이벤트를 환경 구분 라벨 없이 받아서 release에만 남김.
    "qket-logs-release.json" = file("${path.module}/dashboards/qket-logs-release.json")
    "qket-logs-prod.json"    = file("${path.module}/dashboards/qket-logs-prod.json")
  }

  depends_on = [helm_release.monitoring]
}

# Grafana 관리자 비밀번호를 Secrets Manager로 미러링 — 콘솔/CLI로 바로 조회 가능하게 함.
# 매일 밤 재생성되니 값도 매번 최신으로 덮어써짐(ignore_changes 없음).
data "kubernetes_secret" "grafana_admin" {
  metadata {
    name      = "monitoring-grafana"
    namespace = "monitoring"
  }

  depends_on = [helm_release.monitoring]
}

resource "aws_secretsmanager_secret" "grafana_admin" {
  name                    = "${var.project_name}-grafana-admin"
  recovery_window_in_days = 0 # 매일 재생성되는 값 — 대기기간 있으면 이름 충돌 남
}

resource "aws_secretsmanager_secret_version" "grafana_admin" {
  secret_id = aws_secretsmanager_secret.grafana_admin.id
  secret_string = jsonencode({
    username = data.kubernetes_secret.grafana_admin.data["admin-user"]
    password = data.kubernetes_secret.grafana_admin.data["admin-password"]
  })
}
