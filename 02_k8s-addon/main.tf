# qket-release/qket-prod 네임스페이스 — 원래 04_data(구 workload, kubernetes_namespace.this, workspace별)가
# 만들었었는데, 04_data는 release/prod를 나눠서 두 번 apply해야 하고(workspace), 그마저도 namespace를
# ArgoCD가 YAML(Infra/kubernetes/{release,prod}/namespace_qKet.yaml)로 관리하도록 바꾸면서 04_data에서
# 제거했었음. 근데 그 ArgoCD Application(infra-manifests)이 아직 안 만들어져서, 새 클러스터에서는
# 네임스페이스가 하나도 없는 채로 04_data apply를 시도하게 되고 kubernetes_config_map/kubernetes_service_account가
# "namespace not found"로 실패함. 여기(k8s-addon)가 01_infrastructure 다음, 04_data보다 먼저 apply되므로,
# 여기서 release/prod 네임스페이스를 둘 다 미리 만들어두면 04_data가 항상 그 존재를 전제할 수 있음.
# networkpolicy는 여전히 Infra/kubernetes/*.yaml + ArgoCD가 관리 — namespace/ingress는 예외적으로
# Terraform(k8s-addon)이 갖고 감(ingress를 여기로 옮긴 이유는 아래 app_ingress 리소스 주석 참고).
# Infra/kubernetes/{release,prod}/namespace_qKet.yaml은 이제 중복이라 정리 대상 — CLAUDE_LLM_WIKI 참고.
#
# 2026-08-10: 01_infrastructure에서 이 리소스와 helm_release.argocd를 여기(k8s-addon)로 이전함 —
# kubernetes/helm provider를 쓰는 리소스가 순수 AWS root(01_infrastructure)와 같은 state에 있으면
# destroy 순서 문제(Access Entry가 먼저 지워져서 Unauthorized)가 재발했었음. 자세한 내용은
# CLAUDE_LLM_WIKI의 eks-destroy-layer-separation 문서 참고.
resource "kubernetes_namespace" "qket" {
  for_each = toset(["release", "prod"])

  metadata {
    name = "qket-${each.key}"
    labels = {
      name = "qket-${each.key}"
    }
  }
}

# ArgoCD
#
# depends_on = [module.alb_controller] — ArgoCD도 자기 Service를 만드는데, ALB Controller는 설치되는
# 순간부터 클러스터 전체의 Service 생성에 mutating webhook(mservice.elbv2.k8s.aws)을 건다. 이 둘이
# depends_on 없이 동시에 apply되면, webhook은 이미 등록됐는데 그걸 처리해줄 컨트롤러 파드는 아직
# Ready가 안 된 타이밍에 ArgoCD의 Service 생성이 걸려서 "no endpoints available for service
# aws-load-balancer-webhook-service"로 실패한다(2026-08-10 실제로 겪음). module.alb_controller의
# helm_release는 wait를 안 껐으니 기본값(true)대로 파드가 Ready될 때까지 기다린 뒤 "생성 완료"로
# 표시되므로, 여기 depends_on만 걸면 그 뒤에 ArgoCD가 안전하게 따라가게 된다.
resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = "argocd"
  create_namespace = true

  # 2026-08-12: cd.jun979.click Ingress를 붙이면서 추가 — ALB가 TLS를 종료하고 뒤로는 평문
  # HTTP로 넘기는데, ArgoCD 서버가 기본값(secure 모드)이면 자체적으로 TLS를 기대해서 핸드셰이크
  # 실패로 이어짐. insecure 모드로 켜서 평문 HTTP로 받게 함(TLS는 이미 ALB가 처리했으므로 안전).
  set {
    name  = "configs.params.server\\.insecure"
    value = "true"
  }

  # ArgoCD Notifications — Out-of-Sync 감지/Sync 실패/Degraded 시 이메일(Gmail SMTP)로 알림.
  # 실제 로그인 계정/비밀번호는 여기 안 넣고 kubernetes_secret.argocd_notifications_secret이
  # 따로 만드는 Secret(argocd-notifications-secret)을 "$키이름" 문법으로 참조하게 함 — 이 파일이
  # git에 커밋돼도 자격증명이 노출되지 않게 하기 위함. secret.create=false로 둬서 차트가 자체
  # Secret을 만들지 않고, 우리가 별도로 만든 Secret을 그대로 쓰게 함.
  #
  # ⚠️ 적용 전 확인할 것: `helm show values argo/argo-cd | grep -A5 notifications`로 이 버전 차트가
  # notifications.notifiers/templates/triggers/secret.create 키를 그대로 쓰는지 확인 — 차트 버전에
  # 따라 값 경로가 다를 수 있음.
  values = [
    <<-YAML
    notifications:
      enabled: true
      secret:
        create: false
      context:
        argocdUrl: https://cd.jun979.click
      notifiers:
        # 커스텀 이름(.gmail 등) 없이 기본 타입명(service.email)만 씀 — 계정 하나만 쓸 거라
        # subscribe 어노테이션도 "on-xxx.email"로 단순하게 걸 수 있음
        service.email: |
          username: $email-username
          password: $email-password
          host: smtp.gmail.com
          port: 587
          from: $email-username
      templates:
                  template.app-out-of-sync: |
                    email:
                      subject: "[ArgoCD] {{.app.metadata.name}} OutOfSync 감지됨"
                    message: |
                      {{.app.metadata.name}} 가 OutOfSync 상태입니다 — Git과 클러스터 상태가 다릅니다.
                      확인 후 수동으로 sync 해주세요: {{.context.argocdUrl}}/applications/{{.app.metadata.name}}
      triggers:
        # 기본 카탈로그엔 "Out-of-Sync 감지" 트리거가 없어서 직접 정의 (on-sync-status-unknown은
        # sync 상태를 "모르는" 경우고 OutOfSync랑 다른 상태라 대신 못 씀)
        trigger.on-out-of-sync: |
          - when: app.status.sync.status == 'OutOfSync'
            send: [app-out-of-sync]
    YAML
  ]

  depends_on = [module.alb_controller]
}



# Gateway API core CRD + GatewayClass — Ingress의 후속 표준으로 전환하는 작업의 1단계
# (release 환경 파일럿, 실 트래픽 영향 없음). module.alb_controller보다 반드시 "먼저" 있어야
# 함(반대 방향 depends_on 없음, 대신 알b_controller 쪽에서 이 모듈을 기다림) — AWS Load Balancer
# Controller가 부팅 시점에 딱 한 번 이 CRD 존재 여부로 자기 ALBGatewayAPI 기능을 켤지 정하기
# 때문. 이유/실제 겪은 증상은 modules/addons/gateway-api-crds/main.tf 주석과 CLAUDE_LLM_WIKI
# decisions/2026-08-2X-ingress-to-gateway-api-migration 참고.
module "gateway_api_crds" {
  source = "../modules/addons/gateway-api-crds"
}

# AWS Load Balancer Controller — Ingress 오브젝트를 보고 실제 ALB를 만들어주는 컨트롤러.
# 이게 없으면 Ingress를 아무리 apply해도 AWS에 ALB 자체가 안 생김(K8s 오브젝트만 있고 실체가 없음).
# 2026-08-10: backup/modules/alb-controller에서 여기로 이전 — Ingress Controller가 만드는
# ALB/타겟그룹/전용SG는 Terraform이 모르는 리소스라, destroy할 땐 반드시 helm uninstall(이 root의
# destroy)이 EKS가 살아있는 동안 먼저 끝나야 함. 그래서 01_infrastructure가 아니라 여기(Layer 2,
# k8s-addon)에 둠 — 자세한 이유는 CLAUDE_LLM_WIKI의 eks-destroy-layer-separation 문서 참고.
#
# depends_on = [module.gateway_api_crds] — 2026-08-20 추가: Gateway API CRD가 이 컨트롤러의
# 부팅 시점에 이미 있어야 ALBGatewayAPI 기능이 켜진다(없으면 "Disabling ALBGatewayAPI: missing
# required CRDs" 로그를 남기고 그 파드가 살아있는 동안 계속 비활성 — kubectl rollout restart로
# 재부팅해야만 정상화됨, 실제로 겪음). 순서를 여기서 강제해두면 매일 아침 이 수동 재시작이 필요 없음.
module "alb_controller" {
  source = "../modules/addons/alb-controller"

  project_name = var.project_name
  aws_region   = var.aws_region

  vpc_id       = data.terraform_remote_state.infrastructure.outputs.vpc_id
  cluster_name = data.terraform_remote_state.infrastructure.outputs.eks_cluster_name

  oidc_provider_arn = data.terraform_remote_state.infrastructure.outputs.oidc_provider_arn
  oidc_provider_url = data.terraform_remote_state.infrastructure.outputs.oidc_provider_url

  depends_on = [module.gateway_api_crds]
}

# Gateway API — prod 실제 컷오버(Ingress 완전 대체). prod는 아직 실서비스 오픈 전이라(2026-08-20
# 기준) release와 함께 한 번에 진행했었는데, 같은 날 후속으로 release(dev.jun979.click)는
# "개발 서버는 관리자만 들어가야 한다"는 결정에 따라 공개 ALB에서 admin Gateway
# (module.gateway_api_admin)로 옮기고 여기서는 빠짐 — 그래서 for_each가 prod만 남음.
# module.gateway_api_crds와 반대로, 이 모듈은 module.alb_controller "다음"에 있어야 한다(그
# 컨트롤러 자신의 Helm 차트가 LoadBalancerConfiguration/TargetGroupConfiguration CRD를 제공하기
# 때문 — modules/addons/gateway-api-crds/main.tf 주석 참고). alloy-faro Service를
# cross-namespace로 참조하므로 module.gateway_api_faro(ReferenceGrant)에도 의존.
locals {
  ingress_config_public = { for k, v in local.ingress_config : k => v if k != "release" }
}

module "gateway_api_app" {
  source   = "../modules/addons/gateway-api-pilot"
  for_each = local.ingress_config_public

  env                = each.key
  namespace          = kubernetes_namespace.qket[each.key].metadata[0].name
  hostname           = each.value.host
  certificate_arn    = each.value.certificate_arn
  load_balancer_name = "team5-qket-gw-${each.key}-alb"

  depends_on = [
    module.alb_controller,
    module.gateway_api_crds,
    module.gateway_api_faro,
    module.alloy_faro,
    kubernetes_namespace.qket,
  ]
}

# alloy-faro(monitoring 네임스페이스)를 release/prod의 HTTPRoute가 cross-namespace로 참조할 수
# 있게 하는 ReferenceGrant + TargetGroupConfiguration — release/prod가 같은 Service를 공유해서
# env별 module.gateway_api_app/gateway_api_admin 인스턴스에 안 넣고 여기 한 번만 만든다
# (modules/addons/gateway-api-faro/chart/Chart.yaml 참고). release가 이제 gateway_api_admin
# 쪽으로 옮겨가도 namespace 목록(local.ingress_config 전체 키)은 그대로 release/prod 둘 다 필요.
module "gateway_api_faro" {
  source = "../modules/addons/gateway-api-faro"

  allowed_namespaces = [for k in keys(local.ingress_config) : kubernetes_namespace.qket[k].metadata[0].name]

  depends_on = [module.alb_controller, module.gateway_api_crds, kubernetes_namespace.qket]
}

# 관리 도구(Grafana/ArgoCD) + dev(release) 공유 admin Gateway — admin-ingress.tf의
# kubernetes_ingress_v1.grafana/argocd를 대체하고, dev.jun979.click도 여기로 옮겨서 팀원 IP
# 허용목록(local.admin_allowed_cidrs, admin-ingress.tf)을 셋 다 공유하게 함. 인증서는
# admin-ingress.tf가 이미 발급해둔 것(grafana/argocd)과 release용 기존 인증서(dev)를 그대로 재사용.
# module.gateway_api_faro 이후에 있어야 함(dev의 /collect 라우팅이 그 ReferenceGrant를 씀).
module "gateway_api_admin" {
  source = "../modules/addons/gateway-api-admin"

  admin_allowed_cidrs = local.admin_allowed_cidrs

  grafana_certificate_arn = aws_acm_certificate_validation.grafana.certificate_arn
  argocd_certificate_arn  = aws_acm_certificate_validation.argocd.certificate_arn

  dev_hostname        = local.ingress_config.release.host
  dev_certificate_arn = local.ingress_config.release.certificate_arn

  depends_on = [
    module.alb_controller,
    module.gateway_api_crds,
    module.gateway_api_faro,
    module.alloy_faro,
    module.monitoring,
    helm_release.argocd,
    kubernetes_namespace.qket,
  ]
}

# Cluster Autoscaler — 2026-08-20 Karpenter 마이그레이션 3단계로 완전히 제거함(방식 A: 전면
# 교체). 이전에는 EKS 노드그룹(modules/eks)의 desired_size를 min~max(01_infrastructure/
# variables.tf) 사이에서 자동 조절했으나, 이제 module.karpenter가 그 역할을 전담.
# 3-1에서 helm_release만 먼저 destroy(2026-08-20)로 검증 후, 이 단계에서 모듈 전체 제거.
# 과거 코드는 git history(이 커밋 이전)에서 확인 가능.

# Karpenter — cluster-autoscaler를 대체하는 노드 오토스케일러. 1단계(IAM/SQS) → 2단계(Helm/
# EC2NodeClass/NodePool) → 3단계(cluster-autoscaler 제거, 2026-08-20 진행 중)까지 완료.
module "karpenter" {
  source = "../modules/addons/karpenter"

  project_name = var.project_name
  aws_region   = var.aws_region
  cluster_name = data.terraform_remote_state.infrastructure.outputs.eks_cluster_name

  oidc_provider_arn = data.terraform_remote_state.infrastructure.outputs.oidc_provider_arn
  oidc_provider_url = data.terraform_remote_state.infrastructure.outputs.oidc_provider_url

  # 기존 노드그룹과 동일한 서브넷/보안그룹 재사용 — Karpenter 전용 discovery 태그 추가 불필요
  node_subnet_ids           = data.terraform_remote_state.infrastructure.outputs.private_general_subnet_ids
  cluster_security_group_id = data.terraform_remote_state.infrastructure.outputs.eks_cluster_security_group_id

  depends_on = [module.alb_controller]
}

# ExternalDNS — ALB Controller가 만든 ALB의 주소를 Route53에 자동으로 연결
#
# depends_on = [module.alb_controller] — helm_release.argocd와 같은 이유(위 주석 참고): 이 차트도
# 자기 Service를 만들 수 있어서, ALB Controller의 webhook이 아직 준비 안 된 타이밍에 걸리면
# 같은 "no endpoints available" 에러가 날 수 있음. 방어적으로 동일하게 걸어둠.
module "external_dns" {
  source = "../modules/addons/external-dns"

  project_name = var.project_name
  aws_region   = var.aws_region

  oidc_provider_arn = data.terraform_remote_state.infrastructure.outputs.oidc_provider_arn
  oidc_provider_url = data.terraform_remote_state.infrastructure.outputs.oidc_provider_url

  hosted_zone_id = "Z0111999JD2RHOSHTM8A" # jun979.click
  domain_filter  = "jun979.click"

  # module.gateway_api_crds가 먼저 있어야 함 — sources에 gateway-httproute를 켜놨는데
  # (modules/addons/external-dns/main.tf 참고) 그 CRD가 없으면 external-dns 파드가 크래시루프 남.
  depends_on = [module.alb_controller, module.gateway_api_crds]
}

# 모니터링 스택(Prometheus/Grafana/Alertmanager) — wiki decisions/2026-08-11-monitoring-stack-design 참고.
#
# depends_on = [module.alb_controller] — external_dns와 같은 이유(위 주석 참고): Prometheus/
# Grafana/Alertmanager/node-exporter가 전부 자기 Service를 만들어서 같은 webhook 레이스 위험이 있음.
module "monitoring" {
  source = "../modules/addons/monitoring"

  project_name = var.project_name
  aws_region   = var.aws_region

  oidc_provider_arn = data.terraform_remote_state.infrastructure.outputs.oidc_provider_arn
  oidc_provider_url = data.terraform_remote_state.infrastructure.outputs.oidc_provider_url

  amp_remote_write_endpoint = data.terraform_remote_state.registry.outputs.amp_remote_write_endpoint
  amp_workspace_arn         = data.terraform_remote_state.registry.outputs.amp_workspace_arn
  amp_query_endpoint        = data.terraform_remote_state.registry.outputs.amp_query_endpoint

  depends_on = [module.alb_controller]
}

# 로그 저장소(Loki) — 프론트(Next.js SSR/미들웨어)·백엔드(Spring Boot) 파드가 찍는 로그를
# 모아서 위 Grafana에서 같이 볼 수 있게 함. monitoring 모듈과 같은 네임스페이스(monitoring)에 설치.
module "loki" {
  source = "../modules/addons/loki"

  project_name = var.project_name
  aws_region   = var.aws_region

  oidc_provider_arn = data.terraform_remote_state.infrastructure.outputs.oidc_provider_arn
  oidc_provider_url = data.terraform_remote_state.infrastructure.outputs.oidc_provider_url

  depends_on = [module.alb_controller]
}

# 노드마다 떠서 파드 로그를 Loki로 전송 — module.loki가 먼저 만들어져 있어야 보낼 곳이 있음.
module "promtail" {
  source = "../modules/addons/promtail"

  depends_on = [module.loki]
}

# 브라우저(프론트엔드 Faro SDK)가 보내는 클릭/에러 이벤트를 받아서 Loki로 전달.
module "alloy_faro" {
  source = "../modules/addons/alloy-faro"

  depends_on = [module.loki]
}


# Grafana 대시보드 정의를 git에 저장 — EKS를 destroy/재생성해도 module.monitoring만 다시
# apply하면 대시보드가 자동으로 돌아옴(module.monitoring의 sidecar.dashboards 설정이 이
# ConfigMap을 grafana_dashboard=1 라벨로 찾아서 자동 로드). JSON은 Grafana UI의 dashboard
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
    "qket-monitoring.json" = file("${path.module}/dashboards/qket-monitoring.json")
    # 2026-08-19: 백엔드/프론트(SSR)/브라우저(Faro) 로그를 매번 쿼리 바꿔가며 Explore에서
    # 찾아보는 대신, 패널 3개로 한 화면에 고정해둔 대시보드. 3번째 패널(브라우저 이벤트)의
    # 쿼리는 Alloy faro.receiver가 실제로 붙이는 라벨을 아직 확정 못 해서 임시로 텍스트
    # 필터(|= "qket-frontend")만 걸어둠 — Grafana에서 실제 라벨 확인되면 라벨 매처로 교체 필요.
    "qket-logs.json" = file("${path.module}/dashboards/qket-logs.json")
  }

  depends_on = [module.monitoring]
}

# backend API 지표(응답시간, 요청수, HikariCP, JVM 등)를 Prometheus가 스크랩하게 등록.
# wiki decisions/2026-08-11-monitoring-stack-design 문서상 "2차(나중)" 범위였던 앱 레벨 지표 —
# release 환경만 우선 커버.
#
# 2026-08-20: kubernetes_manifest에서 helm_release 기반 모듈로 전환 — kubernetes_manifest는
# plan 시점에 ServiceMonitor CRD가 클러스터에 이미 있는지 확인하는데, 02_k8s-addon이 매일 밤
# destroy→재생성되는 구조상 이게 매번 실패했음(3일 연속 재현, CLAUDE_LLM_WIKI
# troubleshooting/crd-not-yet-installed-on-fresh-apply). helm_release는 이 문제 자체가 없어서
# 매일 아침 `-target=module.monitoring` 선적용 없이도 그냥 apply 한 번으로 끝남. 실제
# ServiceMonitor 내용/포트 관련 주석은 modules/addons/backend-servicemonitor/chart/templates/
# servicemonitor.yaml 참고.
module "backend_servicemonitor" {
  source = "../modules/addons/backend-servicemonitor"

  depends_on = [module.monitoring]
}

# KEDA — backend 오토스케일링용. 실제 스케일 규칙(ScaledObject)은 CD 레포(Helm)에 있고,
# 여기는 그 규칙을 처리할 컨트롤러(엔진)만 설치. modules/addons/keda/main.tf 주석 참고.
module "keda" {
  source = "../modules/addons/keda"

  depends_on = [module.alb_controller]
}

# metrics-server — KEDA(cpu trigger)가 만드는 HPA가 CPU 사용률을 읽으려면 이게 반드시 있어야 함.
# 이게 없으면 HPA가 "unknown"으로 멈춰서 ScaledObject를 아무리 만들어도 절대 스케일 안 됨 —
# 2026-08-13 부하테스트에서 4개 replica가 끝까지 안 늘어난 원인이 이거였음(modules/addons/metrics-server 참고).
module "metrics_server" {
  source = "../modules/addons/metrics-server"

  depends_on = [module.alb_controller]
}

# 환경별 도메인/인증서 설정 — 예전엔 이 값들로 kubernetes_ingress_v1(app_ingress_backend/
# app_ingress_frontend/faro_ingress) 3개를 만들었는데, 2026-08-20 Gateway API로 완전히
# 대체하면서 그 3개 리소스는 삭제함 — 지금은 module.gateway_api_app(위)이 이 값을 그대로 받아서
# Gateway/HTTPRoute를 만듦. host는 CD/helm/values.yaml에도 그대로 남아있음(backend의
# APP_BASE_URL이 참조) — 두 군데 다 "이 환경의 프론트 도메인"이라는 같은 사실을 나타내는 것뿐이라
# 굳이 하나로 합칠 필요는 없음.
locals {
  ingress_config = {
    release = {
      host            = "dev.jun979.click"
      certificate_arn = "arn:aws:acm:ap-northeast-2:727646470302:certificate/5e9cef50-c07b-4988-8317-88a1c5fa8e1c"
    }
    prod = {
      host            = "app.jun979.click"
      certificate_arn = "arn:aws:acm:ap-northeast-2:727646470302:certificate/a9789e71-7453-43d9-b0db-ad2ac973f4c0"
    }
  }
}

# 개발용 자체호스팅 MySQL/Redis (RDS/ElastiCache와 별개, "앱 동작 확인용")
# 2026-08-20: 팀 요청 — 운영(release)은 지금 그대로 RDS/ElastiCache 유지, 개발 확인용으로
# EBS 기반 StatefulSet을 추가로 띄움. 처음엔 동적 프로비저닝(매번 새 볼륨)으로 만들었다가,
# 이러면 클러스터 재생성마다 예전 볼륨이 고아로 남아 비용만 새고 데이터도 결국 안 이어진다는
# 걸 확인해서, 03_registry가 만든 영구 EBS 볼륨을 정적으로 재연결하는 방식으로 변경함.
# 자세한 이유는 modules/addons/dev-datastore/main.tf 상단 주석 참고.
module "dev_datastore" {
  source = "../modules/addons/dev-datastore"

  namespace = "qket-release"

  mysql_ebs_volume_id = data.terraform_remote_state.registry.outputs.dev_mysql_ebs_volume_id
  redis_ebs_volume_id = data.terraform_remote_state.registry.outputs.dev_redis_ebs_volume_id
  availability_zone   = data.terraform_remote_state.registry.outputs.dev_datastore_availability_zone

  depends_on = [kubernetes_namespace.qket]
}
