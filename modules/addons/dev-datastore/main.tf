# 개발용 자체호스팅 MySQL/Redis — RDS/ElastiCache(운영, 04_data)와는 완전히 별개.
# "앱이 도는지 눈으로 보는" 용도라 비용이 훨씬 저렴한 EBS 기반 StatefulSet으로 대신함.
#
# StatefulSet을 쓰는 이유: 일반 Deployment는 파드가 재시작될 때마다 새 파드로 취급돼서
# 볼륨 재연결이 보장되지 않음 — StatefulSet은 파드 이름(mysql-0 등)과 그 파드 전용 PVC를
# 고정으로 짝지어줘서, 재시작해도 항상 자기 데이터로 다시 붙는 걸 보장함.
#
# ⚠️ 이 모듈이 02_k8s-addon에 있는 한, 매일 밤 destroy될 때 이 StatefulSet도 같이 사라짐.
# StorageClass "gp2"의 reclaimPolicy가 기본값 Delete라 EBS 볼륨도 같이 삭제되고, 다음날
# 재생성되면 빈 DB로 새로 시작함 — "개발 중 잠깐 켜놓고 보는 용도"에는 문제없지만, 데이터를
# 계속 유지하고 싶다면 이 모듈을 03_registry(영구 레이어)로 옮기거나 StorageClass를
# reclaimPolicy=Retain으로 바꿔야 함 (그 경우 사람이 다음날 PV를 수동으로 재연결해야 함 —
# AMP를 03_registry로 옮겼던 것과 같은 트레이드오프).

resource "random_password" "mysql_root" {
  length  = 20
  special = false
}

resource "kubernetes_secret" "mysql" {
  metadata {
    name      = "dev-mysql-secret"
    namespace = var.namespace
  }
  data = {
    MYSQL_ROOT_PASSWORD = random_password.mysql_root.result
  }
}

resource "kubernetes_service" "mysql" {
  metadata {
    name      = "dev-mysql"
    namespace = var.namespace
    labels    = { app = "dev-mysql" }
  }
  spec {
    selector   = { app = "dev-mysql" }
    cluster_ip = "None" # headless — StatefulSet 표준 패턴, 파드별 고정 DNS(dev-mysql-0.dev-mysql)로 접근 가능
    port {
      port        = 3306
      target_port = 3306
    }
  }
}

resource "kubernetes_stateful_set_v1" "mysql" {
  metadata {
    name      = "dev-mysql"
    namespace = var.namespace
    labels    = { app = "dev-mysql" }
  }
  spec {
    service_name = kubernetes_service.mysql.metadata[0].name
    replicas     = 1
    selector {
      match_labels = { app = "dev-mysql" }
    }
    template {
      metadata {
        labels = { app = "dev-mysql" }
      }
      spec {
        container {
          name  = "mysql"
          image = "mysql:8.0"
          port {
            container_port = 3306
          }
          env {
            name = "MYSQL_ROOT_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.mysql.metadata[0].name
                key  = "MYSQL_ROOT_PASSWORD"
              }
            }
          }
          env {
            name  = "MYSQL_DATABASE"
            value = "qket"
          }
          # 로컬 docker-compose.yml과 동일한 이유(README 참고) — TZ 없으면 컨테이너가 UTC로 떠서
          # NOW()/CURRENT_TIMESTAMP가 호스트(KST)보다 9시간 느리게 찍힘
          env {
            name  = "TZ"
            value = "Asia/Seoul"
          }
          volume_mount {
            name       = "data"
            mount_path = "/var/lib/mysql"
          }
          resources {
            requests = { cpu = "250m", memory = "512Mi" }
            limits   = { cpu = "1", memory = "1Gi" }
          }
        }
      }
    }
    volume_claim_template {
      metadata {
        name = "data"
      }
      spec {
        access_modes       = ["ReadWriteOnce"]
        storage_class_name = "gp2"
        resources {
          requests = { storage = var.mysql_storage_size }
        }
      }
    }
  }
}

resource "kubernetes_service" "redis" {
  metadata {
    name      = "dev-redis"
    namespace = var.namespace
    labels    = { app = "dev-redis" }
  }
  spec {
    selector   = { app = "dev-redis" }
    cluster_ip = "None"
    port {
      port        = 6379
      target_port = 6379
    }
  }
}

resource "kubernetes_stateful_set_v1" "redis" {
  metadata {
    name      = "dev-redis"
    namespace = var.namespace
    labels    = { app = "dev-redis" }
  }
  spec {
    service_name = kubernetes_service.redis.metadata[0].name
    replicas     = 1
    selector {
      match_labels = { app = "dev-redis" }
    }
    template {
      metadata {
        labels = { app = "dev-redis" }
      }
      spec {
        container {
          name  = "redis"
          image = "redis:7-alpine"
          port {
            container_port = 6379
          }
          volume_mount {
            name       = "data"
            mount_path = "/data"
          }
          resources {
            requests = { cpu = "100m", memory = "128Mi" }
            limits   = { cpu = "500m", memory = "512Mi" }
          }
        }
      }
    }
    volume_claim_template {
      metadata {
        name = "data"
      }
      spec {
        access_modes       = ["ReadWriteOnce"]
        storage_class_name = "gp2"
        resources {
          requests = { storage = var.redis_storage_size }
        }
      }
    }
  }
}
