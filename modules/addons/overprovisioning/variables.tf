variable "namespace" {
  description = "풍선 파드가 뜰 네임스페이스 — preemption은 namespace를 안 가리므로 실제 효과는 클러스터 전역에 적용되지만, qket-prod로 둬서 '이건 prod 버스트 대비용'이라는 의도를 이름으로 드러냄"
  type        = string
}

variable "replicas" {
  # 2026-08-25: 1개(1700m/6500Mi, 노드 하나를 통째로)에서 4개로 쪼갬 — 실제 부하테스트에서
  # "풍선 하나가 통째로 노드를 차지하고 있으면, 그 노드에 딱 맞는 규모(노드 전체)로 스케일업이
  # 안 일어나는 한 preemption 자체가 안 걸리고 죽은 공간이 된다"는 게 드러남(round 62 2000명
  # 재검증, CLAUDE_LLM_WIKI troubleshooting/backend-cold-start-cpu-contention-during-rollout
  # 참고). 작은 파드 여러 개로 쪼개면 backend 파드 하나(request 500m)가 필요할 때마다 풍선
  # 하나만 밀어내면 되므로 preemption 단위가 실제 필요 단위에 훨씬 가까워짐 — 같은 노드에
  # 몰려 떠도(anti-affinity 없음, 비용 동일) 개별 preemption은 그대로 가능.
  description = "풍선 파드 개수 — 합쳐서 '여유 노드 1개분'을 유지하되, preemption이 파드 단위로 잘게 일어나도록 여러 개로 쪼갬"
  type        = number
  default     = 4
}

variable "cpu_request" {
  description = "풍선 파드 하나(전체 replicas 중 1개)의 CPU request — replicas × 이 값 ≈ 목표 노드 타입(t3.large) allocatable에서 kube-system 데몬셋 몫을 뺀 값"
  type        = string
  default     = "425m"
}

variable "memory_request" {
  description = "풍선 파드 하나의 메모리 request — cpu_request와 같은 비율로 4등분"
  type        = string
  default     = "1600Mi"
}

variable "priority_class_value" {
  description = "풍선 파드 PriorityClass의 value — 실제 워크로드(기본 priority 0)보다 반드시 낮아야 preemption 대상이 됨"
  type        = number
  default     = -1
}
