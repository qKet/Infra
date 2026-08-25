# 오버프로비저닝("풍선 파드") — Karpenter의 노드 생성 리드타임 자체를 없애는 버퍼.
#
# 배경: KEDA가 backend/frontend replica를 늘려야 하는 순간, 기존 노드에 여유가 없으면
# Karpenter가 새 EC2를 프로비저닝하는 동안(수십 초~분 단위) 그 파드들은 Pending으로 대기하고,
# 노드가 뜨면 한꺼번에 그 노드로 몰려서 뜨며 콜드스타트 CPU 경합을 겪는다
# (CLAUDE_LLM_WIKI troubleshooting/backend-cold-start-cpu-contention-during-rollout 참고).
# topologySpreadConstraints로 "몰림"만 막으려 하면 오히려 신규 노드 여러 개를 동시에 기다리느라
# 스케일업 자체가 늦어지는 더 나쁜 트레이드오프가 났다(같은 문서, 2026-08-21~24 재현) — 즉
# "몰림 방지"와 "빠른 스케일업"은 스케줄링 정책만으로는 양립이 안 됐다.
#
# 이 모듈은 그 트레이드오프의 원인(노드가 없어서 급하게 기다려야 하는 것) 자체를 없앤다:
# 아무 일도 안 하는 낮은 우선순위 파드("풍선")를 평소에 띄워서 노드 한 대 분량의 여유를
# 미리 점유해둔다. 진짜 workload 파드가 스케일업돼야 할 때 K8s 스케줄러가 이 풍선을
# 즉시 preempt(강제 축출)하므로, 그 자리를 Karpenter의 새 노드를 기다릴 필요 없이 곧바로
# 쓸 수 있다. 축출된 풍선은 나중에 Karpenter가 새 노드를 마저 만들면 그때 다시 재배치된다
# (이건 백그라운드에서 느긋하게 진행돼도 무방 — 실제 트래픽을 막는 게 아니므로).

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
