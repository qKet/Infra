# ArgoCD 알림용 Gmail 자격증명을 ESO로 동기화 — 03_registry에 저장해둔 시크릿을
# 04_data가 설치한 기존 ESO(공유 컨트롤러)가 읽어와서, argocd 네임스페이스에
# "argocd-notifications-secret"이라는 이름의 K8s Secret을 자동으로 만들어준다.
# 이름을 기존과 똑같이 맞춰서 notifications-controller 쪽은 코드 변경 없음.
resource "kubectl_manifest" "argocd_notifications_secret_store" {
  yaml_body = yamlencode({
    apiVersion = "external-secrets.io/v1"
    kind       = "SecretStore"
    metadata = {
      name      = "aws-secrets-manager"
      namespace = "argocd"
    }
    spec = {
      provider = {
        aws = {
          service = "SecretsManager"
          region  = var.aws_region
        }
      }
    }
  })

  depends_on = [helm_release.argocd]
}

resource "kubectl_manifest" "argocd_notifications_external_secret" {
  yaml_body = yamlencode({
    apiVersion = "external-secrets.io/v1"
    kind       = "ExternalSecret"
    metadata = {
      name      = "argocd-notifications-secret"
      namespace = "argocd"
    }
    spec = {
      refreshInterval = "1h"
      secretStoreRef = {
        name = "aws-secrets-manager"
        kind = "SecretStore"
      }
      target = {
        name           = "argocd-notifications-secret"
        creationPolicy = "Owner"
      }
      data = [
        {
          secretKey = "email-username"
          remoteRef = {
            key      = data.terraform_remote_state.registry.outputs.argocd_notifications_secret_arn
            property = "email-username"
          }
        },
        {
          secretKey = "email-password"
          remoteRef = {
            key      = data.terraform_remote_state.registry.outputs.argocd_notifications_secret_arn
            property = "email-password"
          }
        },
      ]
    }
  })

  depends_on = [kubectl_manifest.argocd_notifications_secret_store]
}