# Loki — 로그 저장소. Prometheus가 "지표"를 저장하는 것과 같은 역할을 "로그"에 대해 함.
# SingleBinary 모드로 설치(파드 1개가 다 처리) — 지금 트래픽 규모(개발/QA 단계)엔 이걸로 충분하고,
# 나중에 로그량이 많아지면 SimpleScalable 모드(read/write/backend 파드 분리)로 전환 가능.
#
# 실제 로그 데이터는 파드가 아니라 S3(loki_logs 버킷, s3.tf)에 저장돼서, 파드가 재시작/재생성돼도
# 과거 로그가 안 사라짐 — release 환경을 매일 밤 destroy/재생성하는 이 프로젝트 운영 방식과 맞물려
# 중요한 부분(RDS/Redis 암호화 작업 때와 같은 이유로, 상태는 항상 관리형/영구 저장소 쪽에 둠).
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

        # IRSA로 인증하므로 access key/secret 불필요 — 서비스어카운트가 그대로 AWS 권한을 가짐
        serviceAccount = {
          create = true
          name   = "loki"
          annotations = {
            "eks.amazonaws.com/role-arn" = aws_iam_role.loki.arn
          }
        }
      }

      singleBinary = {
        replicas = 1
        persistence = {
          # 2026-08-19: 처음엔 EBS(PVC)로 시도했는데, 스케줄러와 EBS 프로비저너 사이에서
          # "PVC가 동시에 수정됨" 경합이 계속 반복돼서 파드가 영원히 Pending에 머무름
          # (재시도/재생성으로도 안 풀림 — 일회성 버그가 아니라 이 클러스터 환경에서 반복 재현됨).
          # 여기 로컬 디스크는 어차피 WAL(임시 버퍼)일 뿐이고 실제 로그는 위 S3에 저장되니,
          # EBS 없이 파드 안 임시 디스크(emptyDir)로 대체 — 파드가 재시작되면 최근 몇 분치
          # WAL만 유실될 수 있지만, S3에 이미 쓰인 로그는 영향 없음.
          enabled = false
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
