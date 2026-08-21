# ArgoCD 설치 + Application(qket-cd) 등록.
#
# depends_on(alb_controller)은 호출부(02_k8s-addon/main.tf)에서 이 모듈 자체에 걸어야 함 —
# ArgoCD도 자기 Service를 만드는데, ALB Controller는 설치되는 순간부터 클러스터 전체의
# Service 생성에 mutating webhook(mservice.elbv2.k8s.aws)을 건다. 이 둘이 순서 없이 동시에
# apply되면, webhook은 이미 등록됐는데 그걸 처리해줄 컨트롤러 파드는 아직 Ready가 안 된 타이밍에
# ArgoCD의 Service 생성이 걸려서 "no endpoints available for service
# aws-load-balancer-webhook-service"로 실패한다(2026-08-10 실제로 겪음).
resource "helm_release" "this" {
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
  # 실제 로그인 계정/비밀번호는 여기 안 넣고 아래 module.notifications_secrets가 따로 만드는
  # Secret(argocd-notifications-secret)을 "$키이름" 문법으로 참조하게 함 — 이 파일이
  # git에 커밋돼도 자격증명이 노출되지 않게 하기 위함. secret.create=false로 둬서 차트가 자체
  # Secret을 만들지 않고, 우리가 별도로 만든 Secret을 그대로 쓰게 함.
  #
  # ⚠️ 적용 전 확인할 것: `helm show values argo/argo-cd | grep -A5 notifications`로 이 버전 차트가
  # notifications.notifiers/templates/triggers/secret.create 키를 그대로 쓰는지 확인 — 차트 버전에
  # 따라 값 경로가 다를 수 있음.
  #
  # values/notifications.yaml로 분리 — 변수 치환이 전혀 없는 순수 YAML이라 templatefile() 없이
  # file()로 그대로 읽음.
  values = [file("${path.module}/values/notifications.yaml")]
}

# ArgoCD Application 등록 — 예전엔 Infra/argocd/qket-cd-app.yaml을 사람이 매번 수동으로
# `kubectl apply`해야 했음(02_k8s-addon이 매일 밤 destroy→아침 재생성될 때마다 Application
# 등록이 같이 날아가서, 안 하면 ArgoCD가 "텅 비어있는" 상태로 뜸). 이제 이 root를 apply하면
# 자동으로 같이 생성됨 — 더 이상 사람이 따로 기억해서 실행할 필요 없음.
#
# 2026-08-21: prod 도입하면서 release/prod 둘 다 만들게 for_each로 변경. release Application
# 이름은 기존 그대로 "qket-cd"(2026-08-21 이전부터 이미 이 이름으로 실제 운영 중이라 바꾸면
# finalizer 때문에 기존 backend/frontend가 한 번 cascade delete됨 — state mv로 이어붙임).
# CD 레포의 values.yaml → values-release.yaml로 개명(release 값이라는 걸 이름으로 명확히 함,
# prod용 values-prod.yaml과 대칭)했고, Helm은 파일명이 정확히 "values.yaml"일 때만 자동으로
# 읽어서 개명 후에는 valueFiles로 명시해야 함 — prod는 release 값을 베이스로 깔고
# values-prod.yaml로 덮어씀(레이어링).
# 2026-08-21 이름 재정리: "qket-cd"는 prod(main 브랜치)가 가져가고, release는 "qket-cd-release"로
# 개명 — release가 지금 이 이름(qket-cd)으로 이미 떠있어서 개명 시 finalizer 제거 절차 필요함
# (K8s 오브젝트 이름은 불변이라, 그냥 이름만 바꾸면 새 오브젝트가 생기고 기존 건 고아로 남음 —
# 안전한 절차는 CLAUDE_LLM_WIKI 참고).
locals {
  cd_applications = {
    release = {
      app_name    = "qket-cd-release"
      namespace   = "qket-release"
      value_files = ["values-release.yaml"]
    }
    prod = {
      app_name    = "qket-cd"
      namespace   = "qket-prod"
      value_files = ["values-release.yaml", "values-prod.yaml"]
    }
  }
}

# manifests/qket-cd-application.yaml.tpl로 분리 — value_files 리스트만 변수 치환 필요해서
# templatefile() 사용.
resource "kubectl_manifest" "qket_cd_app" {
  for_each = local.cd_applications

  yaml_body = templatefile("${path.module}/manifests/qket-cd-application.yaml.tpl", {
    app_name    = each.value.app_name
    namespace   = each.value.namespace
    value_files = each.value.value_files
  })

  depends_on = [helm_release.this]
}

# ArgoCD 알림용 Gmail 자격증명을 ESO로 동기화 — ArgoCD가 아니면 쓸 일 없는 부속 기능이라
# 별도 하위 모듈(notifications-secrets/)로 두되 이 argocd 모듈 밑에 중첩해서, "ArgoCD 관련된
# 건 전부 이 폴더 밑에 있다"가 한눈에 보이게 함. 메커니즘/실패 격리 이유는 그 모듈 main.tf 참고.
module "notifications_secrets" {
  source = "./notifications-secrets"

  aws_region = var.aws_region
  secret_arn = var.argocd_notifications_secret_arn

  depends_on = [helm_release.this]
}

# ArgoCD 최초 admin 비밀번호를 Secrets Manager로 미러링 — 비밀번호 자체는 그대로 차트가 설치
# 시점마다 새로 자동 생성하게 두고(고정 비밀번호는 보안상 원하지 않음), 그 값을 조회하기 쉽게
# AWS Secrets Manager에도 똑같이 넣어둠. kubectl로 K8s Secret을 직접 까보는 대신 콘솔/CLI로
# 바로 조회 가능 — 매일 밤 재생성되니 이 시크릿 값도 매번 최신값으로 덮어써짐(ignore_changes 없음).
data "kubernetes_secret" "argocd_admin" {
  metadata {
    name      = "argocd-initial-admin-secret"
    namespace = "argocd"
  }

  depends_on = [helm_release.this]
}

resource "aws_secretsmanager_secret" "argocd_admin" {
  name                    = "${var.project_name}-argocd-admin"
  recovery_window_in_days = 0 # 매일 재생성되는 값 — 대기기간 있으면 이름 충돌 남
}

resource "aws_secretsmanager_secret_version" "argocd_admin" {
  secret_id = aws_secretsmanager_secret.argocd_admin.id
  secret_string = jsonencode({
    username = "admin"
    password = data.kubernetes_secret.argocd_admin.data["password"]
  })
}
