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

# 2026-08-11: 토스/OAuth 외부 API 키 — db-secrets/redis-secrets랑 같은 패턴이지만 원본이
# aws_secretsmanager_secret.external_api(사람이 직접 발급받은 값, ignore_changes로 보호됨).
# 키 목록을 dynamic으로 뽑은 이유: application.yml이 기대하는 이름(TOSS_SECRET_KEY,
# GOOGLE_CLIENT_ID 등)과 Secrets Manager 쪽 JSON 키가 1:1로 같아서, 하나씩 나열하는 대신
# 리스트 하나로 관리 — 나중에 새 provider 추가할 때 이 리스트에 한 줄만 추가하면 됨.
resource "kubectl_manifest" "external_secret_external_api" {
  yaml_body = yamlencode({
    apiVersion = "external-secrets.io/v1"
    kind       = "ExternalSecret"
    metadata = {
      name      = "external-api-secrets"
      namespace = var.namespace
    }
    spec = {
      refreshInterval = "1h"
      secretStoreRef = {
        name = "aws-secrets-manager"
        kind = "SecretStore"
      }
      target = {
        name           = "external-api-secrets"
        creationPolicy = "Owner"
      }
      data = [
        for key in [
          "TOSS_SECRET_KEY",
          "GOOGLE_CLIENT_ID", "GOOGLE_CLIENT_SECRET",
          "KAKAO_CLIENT_ID", "KAKAO_CLIENT_SECRET",
          "NAVER_CLIENT_ID", "NAVER_CLIENT_SECRET",
          ] : {
          secretKey = key
          remoteRef = {
            key      = aws_secretsmanager_secret.external_api.arn
            property = key
          }
        }
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
