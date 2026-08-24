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
  # 삭제되면서 볼륨도 같이 지워져서 이 문제를 못 풂 — AMP 저장소는 03_registry/main.tf 참고,
  # 이 IRSA Role은 바로 위 iam.tf의 aws_iam_role.prometheus 참고).
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

  # Grafana가 AMP를 직접 조회하게 함 — 위 remoteWrite는 "보내는" 설정일 뿐이고, 이게 없으면
  # Grafana는 여전히 로컬(클러스터 안) Prometheus만 봐서 EKS 재생성 시 과거 그래프가 끊겨 보임
  # (iam.tf의 grafana_amp_query 정책이 필요 권한 부여).
  #
  # 범용 "prometheus" 타입 + sigV4Auth 조합으로 처음 시도했다가 AWS가
  # "Credential should be scoped to correct service: 'aps'"로 거부하는 문제를 겪음(2026-08-12)
  # — Grafana의 범용 SigV4 서명 미들웨어가 AMP(aps) 서비스명을 못 알아봄. 대신 AWS가 공식으로
  # 만든 AMP 전용 플러그인(grafana-amazonprometheus-datasource)으로 교체 — 이건 서비스명을
  # 하드코딩해서 알고 있어서 이 문제 자체가 없음.
  #
  # 그런데 교체 후에도 queryData 호출이 "Missing Authentication Token"으로 계속 실패하던 버그가
  # 있었음(위키 troubleshooting/grafana-amp-datasource-missing-auth-token 참고) — 서버 레벨
  # sigv4_auth_enabled만 켜고 데이터소스 jsonData에 sigV4Auth를 명시적으로 안 켜서 실제 서명이
  # 안 붙었던 게 원인으로 추정됨. GitHub grafana-amazonprometheus-datasource#640 코멘트에서
  # 같은 증상을 겪은 사람이 이 조합(서버 설정 + jsonData.sigV4Auth)으로 해결했다고 확인해줌.
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

  # GitHub #640 워크어라운드의 핵심 필드 — 이게 빠져있어서 지금까지 서명이 안 붙었던 것으로 추정.
  set {
    name  = "grafana.additionalDataSources[0].jsonData.sigV4Auth"
    value = "true"
  }

  set {
    name  = "grafana.additionalDataSources[0].jsonData.sigV4Region"
    value = var.aws_region
  }

  # RDS/Redis 지표는 백엔드가 직접 노출 안 해서(HikariCP는 예외) CloudWatch 데이터소스로 봄.
  # IAM은 iam.tf의 grafana_cloudwatch_read 정책으로 이미 준비돼있음(IRSA, 이 Grafana ServiceAccount 전용).
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

  # Loki(로그 저장소, modules/addons/loki) — 클러스터 내부 서비스라 IAM/인증 불필요,
  # CloudWatch/AMP처럼 access 정보 없이 그냥 내부 주소로 연결.
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

# Grafana 대시보드 정의를 git에 저장 — EKS를 destroy/재생성해도 이 모듈만 다시 apply하면
# 대시보드가 자동으로 돌아옴(위 helm_release의 sidecar.dashboards 설정이 이 ConfigMap을
# grafana_dashboard=1 라벨로 찾아서 자동 로드). JSON은 Grafana UI의 dashboard
# settings > JSON Model에서 export한 것을 그대로 커밋해두면 됨.
resource "kubernetes_config_map" "grafana_dashboards" {
  metadata {
    name      = "qket-grafana-dashboards"
    namespace = "monitoring"
    labels = {
      grafana_dashboard = "1"
    }
  }

  data = {
    # 2026-08-21: 기존 qket-monitoring.json 하나를 release/prod 두 대시보드로 분리 — 지표
    # namespace가 하드코딩("qket-release")돼 있어서 원래도 release 전용이었고, prod를 보려면
    # 그때그때 이 파일을 고쳐야 했음. release 쪽은 RDS/Redis CloudWatch 패널 3개를 제거함
    # (release는 dev-datastore로 옮겨가서 그 RDS/ElastiCache 자체가 이제 없음 — 대시보드에
    # 남겨두면 항상 No data).
    "qket-monitoring-release.json" = file("${path.module}/dashboards/qket-monitoring-release.json")
    "qket-monitoring-prod.json"    = file("${path.module}/dashboards/qket-monitoring-prod.json")
    # 2026-08-19: 백엔드/프론트(SSR)/브라우저(Faro) 로그를 매번 쿼리 바꿔가며 Explore에서
    # 찾아보는 대신, 패널로 한 화면에 고정해둔 대시보드.
    #
    # 2026-08-21: qket-monitoring.json과 같은 이유로 release/prod 두 개로 분리 — 단, 3번째
    # 패널(Browser Events/Faro)은 release/prod로 못 나눔. alloy-faro 컬렉터가 release/prod
    # 프론트가 보내는 이벤트를 하나의 공유 인스턴스로 받으면서 `job="faro",
    # service_name="qket-frontend"`라는 고정 라벨만 붙이고 환경 구분 라벨이 없어서
    # (modules/addons/alloy-faro/main.tf 참고) Loki 단에서 release/prod를 구분할 방법이
    # 없음 — 그래서 이 패널은 release 대시보드에만 남기고 prod에서는 뺌(사용자 판단).
    "qket-logs-release.json" = file("${path.module}/dashboards/qket-logs-release.json")
    "qket-logs-prod.json"    = file("${path.module}/dashboards/qket-logs-prod.json")
  }

  depends_on = [helm_release.monitoring]
}

# Grafana 관리자 비밀번호를 Secrets Manager로 미러링 — 비밀번호 자체는 그대로 차트가 매번
# 새로 자동 생성하게 두고(고정 비밀번호는 보안상 원하지 않음), 그 값을 조회하기 쉽게 AWS
# Secrets Manager에도 똑같이 넣어둠. kubectl로 K8s Secret을 직접 까보는 대신 콘솔/CLI로
# 바로 조회 가능 — 매일 밤 재생성되니 이 시크릿 값도 매번 최신값으로 덮어써짐(ignore_changes 없음).
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
