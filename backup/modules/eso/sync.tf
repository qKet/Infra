# ── ESO가 실제로 뭘 어디서 어디로 동기화할지 정의 (SecretStore + ExternalSecret) ──
# kubectl_manifest는 kubernetes_manifest와 달리 plan 시점에 클러스터를 라이브 조회하지 않아서,
# 클러스터 생성 + helm_release(ESO 설치) + 이 CRD 리소스들을 전부 한 번의 apply로 처리할 수 있음.

resource "kubectl_manifest" "secret_store" {
  yaml_body = yamlencode({
    apiVersion = "external-secrets.io/v1"
    kind       = "SecretStore"
    metadata = {
      name      = "aws-secrets-manager"
      namespace = var.namespace
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

  depends_on = [helm_release.external_secrets]
}

resource "kubectl_manifest" "external_secret_db" {
  yaml_body = yamlencode({
    apiVersion = "external-secrets.io/v1"
    kind       = "ExternalSecret"
    metadata = {
      name      = "db-secrets"
      namespace = var.namespace
    }
    spec = {
      refreshInterval = "1h"
      secretStoreRef = {
        name = "aws-secrets-manager"
        kind = "SecretStore"
      }
      target = {
        name           = "db-secrets"
        creationPolicy = "Owner"
      }
      data = [
        {
          secretKey = "DB_HOST"
          remoteRef = {
            key      = aws_secretsmanager_secret.connection.arn
            property = "DB_HOST"
          }
        },
        {
          secretKey = "DB_USERNAME"
          remoteRef = {
            key      = var.rds_master_user_secret_arn
            property = "username"
          }
        },
        {
          secretKey = "DB_PASSWORD"
          remoteRef = {
            key      = var.rds_master_user_secret_arn
            property = "password"
          }
        },
      ]
    }
  })

  depends_on = [kubectl_manifest.secret_store]
}

resource "kubectl_manifest" "external_secret_redis" {
  yaml_body = yamlencode({
    apiVersion = "external-secrets.io/v1"
    kind       = "ExternalSecret"
    metadata = {
      name      = "redis-secrets"
      namespace = var.namespace
    }
    spec = {
      refreshInterval = "1h"
      secretStoreRef = {
        name = "aws-secrets-manager"
        kind = "SecretStore"
      }
      target = {
        name           = "redis-secrets"
        creationPolicy = "Owner"
      }
      data = [
        {
          secretKey = "REDIS_HOST"
          remoteRef = {
            key      = aws_secretsmanager_secret.connection.arn
            property = "REDIS_HOST"
          }
        },
      ]
    }
  })

  depends_on = [kubectl_manifest.secret_store]
}
