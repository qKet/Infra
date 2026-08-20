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



# AWS Load Balancer Controller — Ingress 오브젝트를 보고 실제 ALB를 만들어주는 컨트롤러.
# 이게 없으면 Ingress를 아무리 apply해도 AWS에 ALB 자체가 안 생김(K8s 오브젝트만 있고 실체가 없음).
# 2026-08-10: backup/modules/alb-controller에서 여기로 이전 — Ingress Controller가 만드는
# ALB/타겟그룹/전용SG는 Terraform이 모르는 리소스라, destroy할 땐 반드시 helm uninstall(이 root의
# destroy)이 EKS가 살아있는 동안 먼저 끝나야 함. 그래서 01_infrastructure가 아니라 여기(Layer 2,
# k8s-addon)에 둠 — 자세한 이유는 CLAUDE_LLM_WIKI의 eks-destroy-layer-separation 문서 참고.
module "alb_controller" {
  source = "../modules/addons/alb-controller"

  project_name = var.project_name
  aws_region   = var.aws_region

  vpc_id       = data.terraform_remote_state.infrastructure.outputs.vpc_id
  cluster_name = data.terraform_remote_state.infrastructure.outputs.eks_cluster_name

  oidc_provider_arn = data.terraform_remote_state.infrastructure.outputs.oidc_provider_arn
  oidc_provider_url = data.terraform_remote_state.infrastructure.outputs.oidc_provider_url
}

# Cluster Autoscaler — EKS 노드그룹(modules/eks)의 desired_size를 min~max(01_infrastructure/
# variables.tf, 지금 1~3) 사이에서 자동 조절. KEDA(파드 오토스케일링)가 replica를 늘려도 이게
# 없으면 그 파드들이 노드 부족으로 Pending에 멈춤 — 2026-08-18 대용량 트래픽 용량 분석에서 발견
# (CLAUDE_LLM_WIKI decisions/2026-08-18-capacity-planning-large-traffic-readiness 참고).
# Karpenter 대신 이걸 고른 이유는 modules/addons/cluster-autoscaler/main.tf 주석 참고.
module "cluster_autoscaler" {
  source = "../modules/addons/cluster-autoscaler"

  project_name = var.project_name
  aws_region   = var.aws_region
  cluster_name = data.terraform_remote_state.infrastructure.outputs.eks_cluster_name
  eks_version  = data.terraform_remote_state.infrastructure.outputs.eks_version

  oidc_provider_arn = data.terraform_remote_state.infrastructure.outputs.oidc_provider_arn
  oidc_provider_url = data.terraform_remote_state.infrastructure.outputs.oidc_provider_url

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

  depends_on = [module.alb_controller]
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
# release 환경만 우선 커버. backend Service(qket-backend-service)에 포트 이름이 없어서
# port(이름) 대신 targetPort(번호)로 참조함 — Service에 `name: http`를 붙이면 더 표준적인
# port 참조로 바꿀 수 있음.
#
# targetPort=8081, path=/actuator/prometheus (앱 메인 포트 8080/context-path `/api`와 다름) —
# actuator가 보안상 별도 관리 포트(8081)로 분리되어 있고, management 포트는 server.servlet.context-path를
# 상속하지 않아 `/api` 접두어가 안 붙음. 예전엔 8080 + `/api/actuator/prometheus`로 잘못 설정돼 있었는데,
# 그때는 우연히 앱과 actuator가 같은 포트를 썼어서 동작하다가 actuator가 8081로 분리되면서 조용히 깨짐
# (Prometheus up=0, 404) — 부하테스트 도중 발견.
resource "kubernetes_manifest" "backend_service_monitor" {
  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "ServiceMonitor"
    metadata = {
      name      = "qket-backend"
      namespace = "monitoring"
      labels    = { release = "monitoring" }
    }
    spec = {
      namespaceSelector = { matchNames = ["qket-release"] }
      selector          = { matchLabels = { app = "qket-backend" } }
      endpoints = [
        { targetPort = 8081, path = "/actuator/prometheus", interval = "15s" }
      ]
    }
  }

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

# 환경별 Ingress 설정 — 원래 CD/helm/templates/ingress.yaml(ArgoCD가 배포)이 갖고 있었는데,
# Terraform(alb_controller가 있는 이 root)으로 옮김: destroy 시 "Ingress가 alb_controller보다
# 먼저 없어져야 한다"는 순서를 같은 state 안에서 depends_on으로 직접 강제하기 위해서.
# (namespace cascade-delete에 기대던 이전 방식 대신 — 2026-08-10, eks-destroy-layer-separation 참고)
# host는 CD/helm/values.yaml에도 그대로 남아있음(backend의 APP_BASE_URL이 참조) — 두 군데 다
# "이 환경의 프론트 도메인"이라는 같은 사실을 나타내는 것뿐이라 굳이 하나로 합칠 필요는 없음.
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

# 헬스체크를 위하여 두개로 나누기
# 백엔드 k8s-ingress 
resource "kubernetes_ingress_v1" "app_ingress_backend" {
  for_each = local.ingress_config

  metadata {
    name      = "app-alb-ingress-backend"
    namespace = kubernetes_namespace.qket[each.key].metadata[0].name

    annotations = {
      "alb.ingress.kubernetes.io/group.name"         = "qket"
      "alb.ingress.kubernetes.io/group.order"        = "10"
      "alb.ingress.kubernetes.io/tags"               = "Team=team5,Project=qket"
      "alb.ingress.kubernetes.io/load-balancer-name" = "team5-qket-alb"
      "alb.ingress.kubernetes.io/scheme"             = "internet-facing"
      "alb.ingress.kubernetes.io/target-type"        = "ip"
      "alb.ingress.kubernetes.io/certificate-arn"    = each.value.certificate_arn
      "alb.ingress.kubernetes.io/ssl-redirect"       = "443"
      "alb.ingress.kubernetes.io/listen-ports"       = "[{\"HTTP\":80},{\"HTTPS\":443}]"
      "alb.ingress.kubernetes.io/healthcheck-port"   = "8081"
      "alb.ingress.kubernetes.io/healthcheck-path"   = "/actuator/health"
    }
  }

  spec {
    ingress_class_name = "alb"

    rule {
      host = each.value.host

      http {
        path {
          path      = "/api"
          path_type = "Prefix"

          backend {
            service {
              name = "qket-backend-service"
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }

  wait_for_load_balancer = false

  depends_on = [module.alb_controller]
}

#프론트앤드 k8s-ingress
resource "kubernetes_ingress_v1" "app_ingress_frontend" {
  for_each = local.ingress_config

  metadata {
    name      = "app-alb-ingress-frontend"
    namespace = kubernetes_namespace.qket[each.key].metadata[0].name

    annotations = {
      "alb.ingress.kubernetes.io/group.name"         = "qket"
      "alb.ingress.kubernetes.io/group.order"        = "20"
      "alb.ingress.kubernetes.io/tags"               = "Team=team5,Project=qket"
      "alb.ingress.kubernetes.io/load-balancer-name" = "team5-qket-alb"
      "alb.ingress.kubernetes.io/scheme"             = "internet-facing"
      "alb.ingress.kubernetes.io/target-type"        = "ip"
      "alb.ingress.kubernetes.io/certificate-arn"    = each.value.certificate_arn
      "alb.ingress.kubernetes.io/ssl-redirect"       = "443"
      "alb.ingress.kubernetes.io/listen-ports"       = "[{\"HTTP\":80},{\"HTTPS\":443}]"
      "alb.ingress.kubernetes.io/healthcheck-path" = "/healthz"
    }
  }

  spec {
    ingress_class_name = "alb"

    rule {
      host = each.value.host

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = "qket-frontend-service"
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }

  # false로 둠 — ALB가 실제로 잘 떴는지는 aws elbv2 describe-load-balancers로 필요할 때 확인.
  wait_for_load_balancer = false

  depends_on = [module.alb_controller]
}

# 브라우저(Faro SDK)가 dev.jun979.click/faro-collector, app.jun979.click/faro-collector로
# 이벤트를 보내면 monitoring 네임스페이스의 alloy-faro 서비스로 라우팅 — 같은 ALB group("qket")에
# 묶어서 백엔드/프론트엔드랑 로드밸런서 하나를 같이 씀(비용 절감, alb_controller 모듈 주석 참고 패턴과 동일).
resource "kubernetes_ingress_v1" "faro_ingress" {
  for_each = local.ingress_config

  metadata {
    # release/prod 둘 다 같은 네임스페이스(monitoring, alloy-faro가 있는 곳)를 쓰기 때문에
    # backend/frontend Ingress처럼 네임스페이스로 구분이 안 됨 — 이름 자체에 환경을 붙여서 구분.
    name      = "app-alb-ingress-faro-${each.key}"
    namespace = "monitoring"

    annotations = {
      "alb.ingress.kubernetes.io/group.name"         = "qket"
      "alb.ingress.kubernetes.io/group.order"        = "5"
      "alb.ingress.kubernetes.io/tags"               = "Team=team5,Project=qket"
      "alb.ingress.kubernetes.io/load-balancer-name" = "team5-qket-alb"
      "alb.ingress.kubernetes.io/scheme"             = "internet-facing"
      "alb.ingress.kubernetes.io/target-type"        = "ip"
      "alb.ingress.kubernetes.io/certificate-arn"    = each.value.certificate_arn
      "alb.ingress.kubernetes.io/ssl-redirect"       = "443"
      "alb.ingress.kubernetes.io/listen-ports"       = "[{\"HTTP\":80},{\"HTTPS\":443}]"
    }
  }

  spec {
    ingress_class_name = "alb"

    rule {
      host = each.value.host

      http {
        path {
          # 2026-08-19: 원래 "/faro-collector"였는데, Grafana Alloy의 faro.receiver는
          # 요청 경로를 정확히 "/collect"로만 받음(다른 경로는 전부 404). ALB는 nginx와
          # 달리 경로 rewrite 기능이 없어서, 브라우저가 보내는 실제 경로를 "/collect"로
          # 맞춰야 함(프론트 NEXT_PUBLIC_FARO_COLLECTOR_URL도 같이 맞춰야 함, CI-release.yml 참고).
          path      = "/collect"
          path_type = "Prefix"

          backend {
            service {
              name = "alloy-faro"
              port {
                number = 12347
              }
            }
          }
        }
      }
    }
  }

  wait_for_load_balancer = false

  depends_on = [module.alb_controller, module.alloy_faro]
}

# 개발용 자체호스팅 MySQL/Redis (RDS/ElastiCache와 별개, "앱 동작 확인용")
# 2026-08-20: 팀 요청 — 운영(release)은 지금 그대로 RDS/ElastiCache 유지, 개발 확인용으로
# EBS 기반 StatefulSet을 추가로 띄움. 자세한 트레이드오프(매일 밤 destroy 시 데이터도 같이
# 사라짐)는 modules/addons/dev-datastore/main.tf 상단 주석 참고.
module "dev_datastore" {
  source = "../modules/addons/dev-datastore"

  namespace = "qket-release"

  depends_on = [kubernetes_namespace.qket]
}
