# 오버프로비저닝("풍선 파드") — Karpenter의 노드 생성 리드타임 자체를 없애는 버퍼.
#
# KEDA 스케일업 순간 노드에 여유가 없으면 Karpenter가 새 EC2를 만드는 동안 파드가 Pending으로
# 몰려서 콜드스타트 CPU 경합을 겪는다. topologySpreadConstraints만으로 "몰림"을 막으면 신규
# 노드를 기다리느라 스케일업 자체가 늦어져서, 스케줄링 정책만으론 양립이 안 됐다.
#
# 대신 아무 일도 안 하는 낮은 우선순위 파드("풍선")를 평소에 띄워 노드 여유를 미리 점유—
# 실제 workload가 스케일업될 때 스케줄러가 이 풍선을 즉시 preempt해서 그 자리를 곧바로 쓴다.
# 축출된 풍선은 Karpenter가 새 노드를 마저 만들면 그때 다시 재배치된다(백그라운드로 진행돼도 무방).

resource "kubernetes_priority_class_v1" "overprovisioning" {
  metadata {
    name = "overprovisioning"
  }
  # 기본 priority(0)보다 반드시 낮아야 실제 workload가 스케줄될 때 이 파드부터 축출 대상이 됨.
  value          = var.priority_class_value
  global_default = false
  description    = "노드 여유 용량을 미리 점유해두는 오버프로비저닝(풍선) 파드 전용 — 실제 workload가 뜨면 무조건 먼저 축출됨"
}

resource "kubernetes_deployment_v1" "overprovisioning" {
  metadata {
    name      = "overprovisioning"
    namespace = var.namespace
    labels    = { app = "overprovisioning" }
  }
  spec {
    replicas = var.replicas
    selector {
      match_labels = { app = "overprovisioning" }
    }
    template {
      metadata {
        labels = { app = "overprovisioning" }
      }
      spec {
        priority_class_name = kubernetes_priority_class_v1.overprovisioning.metadata[0].name
        container {
          name  = "pause"
          # 쿠버네티스 인프라 자체가 이미 항상 당겨쓰는 이미지라 별도 pull 지연/장애 리스크가 없음.
          # 아무 일도 안 하고 떠있기만 하면 되므로 이보다 가벼운 이미지는 필요 없음.
          image = "registry.k8s.io/pause:3.9"
          resources {
            # limits는 일부러 안 둠 — 실제로 CPU/메모리를 거의 안 쓰는 파드라 limit 유무가
            # 스케줄링(=여유 용량 점유) 목적엔 영향 없고, request만으로 스케줄러가 이 노드를
            # "찼다"고 보게 하는 게 목적.
            requests = {
              cpu    = var.cpu_request
              memory = var.memory_request
            }
          }
        }
      }
    }
  }
}
