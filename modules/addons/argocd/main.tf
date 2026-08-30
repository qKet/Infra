# ArgoCD 설치 + Application(qket-cd) 등록.
# depends_on(alb_controller)은 호출부(02_k8s-addon/main.tf)에서 걸어야 함 — ALB Controller의
# webhook이 준비 안 된 상태에서 ArgoCD가 자기 Service를 만들면 "no endpoints available" 에러.
resource "helm_release" "this" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = "argocd"
  create_namespace = true

  # ALB가 TLS를 종료하고 뒤로는 평문 HTTP로 넘기므로, ArgoCD 서버도 insecure 모드로 받게 함.
  set {
    name  = "configs.params.server\\.insecure"
    value = "true"
  }

  # ArgoCD Notifications — Out-of-Sync/Sync 실패/Degraded 시 이메일(Gmail SMTP)로 알림.
  # 계정/비밀번호는 여기 안 넣고 module.notifications_secrets가 만드는 Secret을 참조(git 노출 방지).
  # values/notifications.yaml, values/resources.yaml(컴포넌트별 최소 requests)을 그대로 병합.
  values = [
    file("${path.module}/values/notifications.yaml"),
    file("${path.module}/values/resources.yaml"),
  ]
}

# ArgoCD Application 등록 — 02_k8s-addon이 매일 밤 destroy→재생성돼도 이 root apply만으로
# 자동 재등록됨(수동 kubectl apply 불필요). "qket-cd"는 prod(main 브랜치), release는
# "qket-cd-release" — release는 values-release.yaml만, prod는 release 위에 values-prod.yaml을
# 덮어씀(레이어링).
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

resource "kubectl_manifest" "qket_cd_app" {
  for_each = local.cd_applications

  yaml_body = templatefile("${path.module}/manifests/qket-cd-application.yaml.tpl", {
    app_name    = each.value.app_name
    namespace   = each.value.namespace
    value_files = each.value.value_files
  })

  depends_on = [helm_release.this]
}

# prod ArgoCD Application — values-release.yaml + values-prod.yaml을 함께 적용(레이어링).
resource "kubectl_manifest" "qket_cd_app_prod" {
  yaml_body = file("${path.module}/manifests/qket-cd-application-prod.yaml")

  depends_on = [helm_release.this]
}

# ArgoCD 알림용 Gmail 자격증명을 ESO로 동기화 — 하위 모듈(notifications-secrets/)로 분리.
module "notifications_secrets" {
  source = "./notifications-secrets"

  aws_region = var.aws_region
  secret_arn = var.argocd_notifications_secret_arn

  depends_on = [helm_release.this]
}

# ArgoCD 최초 admin 비밀번호를 Secrets Manager로 미러링 — 콘솔/CLI로 바로 조회 가능하게 함.
# 매일 밤 재생성되니 값도 매번 최신으로 덮어써짐(ignore_changes 없음).
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
