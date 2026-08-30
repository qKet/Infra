# Loki — 로그 저장소. SingleBinary 모드로 설치(파드 1개가 다 처리) — 지금 규모엔 충분하고,
# 나중에 로그량이 늘면 SimpleScalable 모드로 전환 가능.
# 실제 로그는 S3(loki_logs 버킷, s3.tf)에 저장돼서 파드가 재생성돼도 과거 로그가 안 사라짐.
resource "helm_release" "loki" {
  name             = "loki"
  repository       = "https://grafana.github.io/helm-charts"
  chart            = "loki"
  namespace        = "monitoring"
  create_namespace = true
  version          = "~> 6.16"

  values = [
    yamlencode({
      deploymentMode = "SingleBinary"

      loki = {
        auth_enabled = false

        commonConfig = {
          replication_factor = 1
        }

        storage = {
          type = "s3"
          bucketNames = {
            chunks = aws_s3_bucket.loki_logs.bucket
            ruler  = aws_s3_bucket.loki_logs.bucket
            admin  = aws_s3_bucket.loki_logs.bucket
          }
          s3 = {
            region = var.aws_region
          }
        }

        schemaConfig = {
          configs = [
            {
              from         = "2026-01-01"
              store        = "tsdb"
              object_store = "s3"
              schema       = "v13"
              index = {
                prefix = "index_"
                period = "24h"
              }
            }
          ]
        }
      }

      # grafana/loki 차트는 serviceAccount 설정을 최상위 키로만 인식(loki.serviceAccount는 무시됨) —
      # loki{} 블록 안에 넣으면 annotations가 안 붙어서 IRSA가 작동 안 함.
      serviceAccount = {
        create = true
        name   = "loki"
        annotations = {
          "eks.amazonaws.com/role-arn" = aws_iam_role.loki.arn
        }
      }

      singleBinary = {
        replicas = 1
        persistence = {
          # singleBinary 모드는 EBS(PVC) 아니면 볼륨 없음만 지원해서 EBS로 감. storageClass를
          # 명시하는 이유 — "gp2"가 기본(default)으로 지정 안 돼 있어서 비워두면 PVC가 Pending.
          enabled      = true
          size         = "10Gi"
          storageClass = "gp2"
        }
      }

      # SimpleScalable 모드 전용 컴포넌트라 SingleBinary에서는 다 꺼둠
      read = {
        replicas = 0
      }
      write = {
        replicas = 0
      }
      backend = {
        replicas = 0
      }

      # 클러스터 안에서만 Grafana/Promtail이 접근하면 되므로 외부 노출용 게이트웨이는 불필요
      gateway = {
        enabled = false
      }

      # 90일 지난 로그는 위 s3.tf의 라이프사이클 규칙이 지우지만, Loki 자체 보존기간도
      # 같이 맞춰둬야 조회 시 "있어야 할 로그가 없다"는 혼란이 없음
      limits_config = {
        retention_period = "2160h" # 90일
      }
    })
  ]
}
