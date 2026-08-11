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

  depends_on = [module.alb_controller]
}

# AWS Load Balancer Controller — Ingress 오브젝트를 보고 실제 ALB를 만들어주는 컨트롤러.
# 이게 없으면 Ingress를 아무리 apply해도 AWS에 ALB 자체가 안 생김(K8s 오브젝트만 있고 실체가 없음).
# 2026-08-10: backup/modules/alb-controller에서 여기로 이전 — Ingress Controller가 만드는
# ALB/타겟그룹/전용SG는 Terraform이 모르는 리소스라, destroy할 땐 반드시 helm uninstall(이 root의
# destroy)이 EKS가 살아있는 동안 먼저 끝나야 함. 그래서 01_infrastructure가 아니라 여기(Layer 2,
# k8s-addon)에 둠 — 자세한 이유는 CLAUDE_LLM_WIKI의 eks-destroy-layer-separation 문서 참고.
module "alb_controller" {
  source = "../modules/alb-controller"

  project_name = var.project_name
  aws_region   = var.aws_region

  vpc_id       = data.terraform_remote_state.infrastructure.outputs.vpc_id
  cluster_name = data.terraform_remote_state.infrastructure.outputs.eks_cluster_name

  oidc_provider_arn = data.terraform_remote_state.infrastructure.outputs.oidc_provider_arn
  oidc_provider_url = data.terraform_remote_state.infrastructure.outputs.oidc_provider_url
}

# ExternalDNS — ALB Controller가 만든 ALB의 주소를 Route53에 자동으로 연결
#
# depends_on = [module.alb_controller] — helm_release.argocd와 같은 이유(위 주석 참고): 이 차트도
# 자기 Service를 만들 수 있어서, ALB Controller의 webhook이 아직 준비 안 된 타이밍에 걸리면
# 같은 "no endpoints available" 에러가 날 수 있음. 방어적으로 동일하게 걸어둠.
module "external_dns" {
  source = "../modules/external-dns"

  project_name = var.project_name
  aws_region   = var.aws_region

  oidc_provider_arn = data.terraform_remote_state.infrastructure.outputs.oidc_provider_arn
  oidc_provider_url = data.terraform_remote_state.infrastructure.outputs.oidc_provider_url

  hosted_zone_id = "Z0111999JD2RHOSHTM8A" # jun979.click
  domain_filter  = "jun979.click"

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
      host            = "dev.jun979.click" # dev 쪽 Route53 추가 필요
      certificate_arn = "arn:aws:acm:ap-northeast-2:727646470302:certificate/5e9cef50-c07b-4988-8317-88a1c5fa8e1c"
    }
    prod = {
      host            = "app.jun979.click"
      certificate_arn = "arn:aws:acm:ap-northeast-2:727646470302:certificate/a9789e71-7453-43d9-b0db-ad2ac973f4c0"
    }
  }
}

# app-alb-ingress — CD/helm/templates/ingress.yaml에 있던 것과 내용 동일(annotation/host/backend
# service 전부). frontend/backend Service는 둘 다 여전히 CD/helm(ArgoCD)이 만듦 — Ingress가
# 그 이름을 문자열로 참조할 뿐, Terraform이 Service의 존재를 보장하진 않음(GitOps가 먼저 떠있다는 전제).
#
# 2026-08-11: /api 경로 규칙 추가 — 원래는 frontend(Next.js)의 next.config.mjs rewrites()가
# /api/*를 backend로 프록시했는데, output:"standalone" 빌드에서 rewrites()가 next build 시점에
# 고정돼버려서 CI가 CLUSTER_IP를 빌드 환경에도 넣어줘야 하는 문제가 있었음(frontend 레포 CI가
# K8s 서비스 이름을 알아야 하는 게 부자연스러움 — 실제로 겪은 버그). ALB가 path로 직접 나누면
# 브라우저→백엔드 경로에 Next.js 서버가 아예 안 끼어서 이 문제 자체가 사라짐. /api가 /보다
# 구체적인 경로라 반드시 먼저 선언 — ALB Ingress는 선언 순서대로 우선순위를 매기지, "더 구체적인
# 경로가 자동으로 이김" 방식이 아니라서 순서를 안 지키면 /가 /api/*까지 먼저 가로채버림.
# (백엔드 Spring Boot의 context-path가 이미 /api라서, ALB는 경로를 안 건드리고 그대로 전달하면 됨 —
# rewrite-target 같은 별도 설정 불필요)
#
# kubectl_manifest가 아니라 네이티브 kubernetes_ingress_v1을 쓴다 — 둘 다 처음엔 후보였는데,
# 2026-08-10에 실제로 kubectl_manifest로 만들어봤다가 destroy 때 사고가 났다: kubectl_manifest는
# 삭제 요청만 던지고 deletionTimestamp가 찍히면 "완료"로 치고 넘어가버려서, ALB Controller의
# finalizer(group.ingress.k8s.aws/qket)가 실제로 다 정리하기 전에 alb_controller가 먼저 지워져버림
# (namespace처럼 finalizer 완전히 사라질 때까지 안 기다림). kubernetes_ingress_v1은 kubernetes_namespace와
# 같은 계열(hashicorp/kubernetes provider의 타입 있는 리소스)이라 삭제 시 실제로 다 사라질 때까지
# polling해서 기다려준다 — Ingress는 CRD가 아니라 표준 K8s 타입이라 이 리소스로 충분히 만들 수 있음
# (kubectl_manifest는 CRD처럼 네이티브 리소스가 없는 것에만 쓰면 됨 — module.eso의 SecretStore/
# ExternalSecret이 그 경우).
#
# namespace를 kubernetes_namespace.qket[each.key]의 실제 output으로 참조 — 문자열로 "qket-release"
# 하드코딩하지 않고 리소스 참조를 쓰면 Terraform이 "namespace 먼저 만들고 그다음 ingress" 순서를
# 자동으로 알아서 챙겨줌(암묵적 의존성).
#
# depends_on = [module.alb_controller] — 명시적으로 필요한 이유는 반대 방향(destroy 순서): ALB
# Controller가 만드는 ALB/타겟그룹/전용 보안그룹은 Terraform이 모르는 리소스라(컨트롤러가 Ingress
# 삭제를 감지하고 자기가 직접 AWS API로 지움), destroy할 때 컨트롤러가 Ingress보다 먼저 사라지면
# 그 정리를 해줄 주체가 없어져서 ALB/SG가 고아로 남고 계속 과금된다(2026-08-10 실제로 겪음 —
# eks-destroy-layer-separation 문서 참고). depends_on을 선언한 쪽(ingress)이 destroy 시 먼저
# 없어지므로, "ingress → alb_controller" 방향이 정확히 우리가 원하는 순서(Ingress 먼저, 컨트롤러
# 나중)와 일치한다.
# 2026-08-11: backend/frontend Ingress를 분리함 — ALB Ingress Controller의 healthcheck-path 같은
# annotation은 "Ingress 오브젝트 전체"에 적용되지, path별로 다르게 못 줌. 근데 backend(Spring Boot,
# context-path=/api)와 frontend(Next.js)는 헬스체크 경로가 다르게 필요함(backend는 "/"에 아무것도
# 없어서 404 — 대신 /api/actuator/health가 200을 줌, frontend는 "/"가 기본값 그대로 정상).
# 하나의 Ingress에 두 path를 같이 넣었더니 healthcheck-path를 하나만 줄 수 있어서 둘 중 하나는
# 항상 비정상으로 뜨는 문제를 실제로 겪음 — group.name을 공유하는 별도 Ingress 두 개로 나눠서 해결.
# group.order로 우선순위 강제(낮은 숫자가 먼저 평가됨) — backend(/api)가 frontend(/)보다 구체적인
# 경로라 반드시 먼저 평가돼야 함(안 그러면 /가 /api/*까지 먼저 가로챔).
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
      "alb.ingress.kubernetes.io/healthcheck-path"   = "/api/actuator/health"
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
      # healthcheck-path 안 줌 — 기본값 "/"이 frontend엔 이미 정상 응답이라 그대로 둠
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

  # 기본값(true)이면 apply가 status.loadBalancer.ingress에 실제 호스트네임이 채워질 때까지
  # 기다림(ALB 프로비저닝 완료 확인 — 몇 분 걸림). 매일 아침 껐다 켜는 루틴이라 속도를 우선해서
  # false로 둠 — ALB가 실제로 잘 떴는지는 aws elbv2 describe-load-balancers로 필요할 때 확인.
  wait_for_load_balancer = false

  depends_on = [module.alb_controller]
}
