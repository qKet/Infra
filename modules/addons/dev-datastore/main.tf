# 개발용 자체호스팅 MySQL/Redis — RDS/ElastiCache(운영, 04_data)와는 완전히 별개.
# "앱이 도는지 눈으로 보는" 용도라 비용이 훨씬 저렴한 EBS 기반 StatefulSet으로 대신함.
#
# StatefulSet을 쓰는 이유: 일반 Deployment는 파드가 재시작될 때마다 새 파드로 취급돼서
# 볼륨 재연결이 보장되지 않음 — StatefulSet은 파드 이름(mysql-0 등)과 그 파드 전용 PVC를
# 고정으로 짝지어줘서, 재시작해도 항상 자기 데이터로 다시 붙는 걸 보장함.
#
# ⚠️ 볼륨은 "동적 프로비저닝"이 아니라 "정적 프로비저닝"을 씀 — StorageClass로 매번 새
# EBS 볼륨을 만드는 대신, 03_registry가 미리 만들어둔 영구 볼륨(aws_ebs_volume.dev_mysql/
# dev_redis)을 PersistentVolume이 volume_handle로 직접 가리킴. 이유: 이 02_k8s-addon 자체는
# 매일 밤 destroy되는데(EKS 클러스터가 통째로 사라짐), StatefulSet/PVC 같은 쿠버네티스
# 오브젝트는 그게 어디 정의돼있든 클러스터가 없으면 존재할 수 없음 — 그래서 클러스터와
# 무관하게 영구히 살아있는 "EBS 볼륨 자체"만 03_registry(순수 AWS 리소스 레이어)에 두고,
# 매일 새로 뜨는 StatefulSet이 "같은" 볼륨을 다시 붙여서 데이터가 실제로 유지되게 함.
# (처음엔 StorageClass 동적 프로비저닝을 썼다가, 이러면 매일 새 빈 볼륨만 계속 쌓이고
# 예전 볼륨은 고아로 남아 비용만 샌다는 걸 확인하고 이 방식으로 변경함.)

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

# --- MySQL ---

resource "kubernetes_persistent_volume" "mysql" {
  metadata {
    name = "dev-mysql-pv"
  }
  spec {
    capacity                        = { storage = var.mysql_storage_size }
    access_modes                    = ["ReadWriteOnce"]
    persistent_volume_reclaim_policy = "Retain" # 안전장치 — PVC가 실수로 지워져도 볼륨(데이터)은 안 날아가게
    storage_class_name              = ""        # 빈 문자열 = 정적 프로비저닝(동적 StorageClass 매칭 안 함)

    persistent_volume_source {
      csi {
        driver        = "ebs.csi.aws.com"
        volume_handle = var.mysql_ebs_volume_id
        fs_type       = "ext4"
      }
    }

    node_affinity {
      required {
        node_selector_term {
          match_expressions {
            key      = "topology.kubernetes.io/zone"
            operator = "In"
            values   = [var.availability_zone]
          }
        }
      }
    }
  }
}

resource "kubernetes_persistent_volume_claim" "mysql" {
  metadata {
    name      = "dev-mysql-data"
    namespace = var.namespace
  }
  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = ""
    volume_name        = kubernetes_persistent_volume.mysql.metadata[0].name
    resources {
      requests = { storage = var.mysql_storage_size }
    }
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
        volume {
          name = "data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.mysql.metadata[0].name
          }
        }
      }
    }
  }
}

# --- Redis ---

resource "kubernetes_persistent_volume" "redis" {
  metadata {
    name = "dev-redis-pv"
  }
  spec {
    capacity                        = { storage = var.redis_storage_size }
    access_modes                    = ["ReadWriteOnce"]
    persistent_volume_reclaim_policy = "Retain"
    storage_class_name              = ""

    persistent_volume_source {
      csi {
        driver        = "ebs.csi.aws.com"
        volume_handle = var.redis_ebs_volume_id
        fs_type       = "ext4"
      }
    }

    node_affinity {
      required {
        node_selector_term {
          match_expressions {
            key      = "topology.kubernetes.io/zone"
            operator = "In"
            values   = [var.availability_zone]
          }
        }
      }
    }
  }
}

resource "kubernetes_persistent_volume_claim" "redis" {
  metadata {
    name      = "dev-redis-data"
    namespace = var.namespace
  }
  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = ""
    volume_name        = kubernetes_persistent_volume.redis.metadata[0].name
    resources {
      requests = { storage = var.redis_storage_size }
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
        volume {
          name = "data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.redis.metadata[0].name
          }
        }
      }
    }
  }
}
