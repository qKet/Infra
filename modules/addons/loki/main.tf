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
      }

      # 2026-08-19: 원래 위 loki{} 블록 안에 넣었었는데 grafana/loki 차트는
      # serviceAccount 설정을 최상위 키로만 인식함(loki.serviceAccount는 차트가 그냥 무시).
      # 그래서 annotations가 실제 ServiceAccount 오브젝트에 하나도 안 붙어서
      # IRSA가 작동 안 하고 파드가 "NoCredentialProviders"로 S3 접근을 계속 실패했었음.
      # IRSA로 인증하므로 access key/secret 불필요 — 서비스어카운트가 그대로 AWS 권한을 가짐
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
          # 2026-08-19: singleBinary 모드는 EBS(PVC) 아니면 볼륨 없음 둘 중 하나만 지원함
          # (emptyDir 전용 모드는 write/backend 컴포넌트에만 있고 singleBinary엔 없음 —
          # `helm show values grafana/loki`로 직접 확인함). 그래서 EBS로 감.
          #
          # storageClass를 명시하는 이유: 클러스터에 "gp2" StorageClass는 있지만 기본(default)로
          # 지정돼 있지 않아서(kubectl get storageclass에 (default) 표시 없음), 비워두면 PVC가
          # 매칭될 클래스를 못 찾아 영원히 Pending으로 남음.
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
