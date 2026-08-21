variable "project_name" {
  description = "리소스 이름 접두사"
  type        = string
}

variable "eks_version" {
  description = "EKS 클러스터 쿠버네티스 버전"
  type        = string
}

variable "cluster_subnet_ids" {
  description = "EKS 컨트롤 플레인 ENI가 배치될 서브넷 (퍼블릭 + 프라이빗-일반)"
  type        = list(string)
}

# 2026-08-21 재도입: Karpenter 컨트롤러 자신도, CoreDNS/EBS CSI 같은 kube-system 파드도
# "뜰 노드가 하나도 없으면" 영원히 Pending에 멈추는 데드락이 실제로 발생함(관리형 노드그룹을
# 완전히 없앤 뒤, 완전히 빈 계정에서 처음 apply할 때 재현) — Karpenter가 노드를 만들려면
# 먼저 Karpenter 자신이 뜰 곳이 있어야 하는데, 그 "최초의 곳"이 없었던 게 원인. 그래서 최소
# 부트스트랩용 노드 1개(고정, 오토스케일 안 함 — 그 역할은 전부 Karpenter가 전담)를 다시 둠.
variable "node_subnet_ids" {
  description = "부트스트랩 노드가 배치될 서브넷 (프라이빗-일반)"
  type        = list(string)
}

variable "node_instance_types" {
  description = "부트스트랩 노드그룹 EC2 인스턴스 타입"
  type        = list(string)
}

variable "node_desired_size" {
  description = "부트스트랩 노드 수 — Karpenter가 뜰 때까지 필요한 최소 floor라 1 고정"
  type        = number
}

variable "node_min_size" {
  description = "부트스트랩 노드 최소 수 — 1 고정(오토스케일링은 Karpenter가 전담)"
  type        = number
}

variable "node_max_size" {
  description = "부트스트랩 노드 최대 수 — 1 고정(오토스케일링은 Karpenter가 전담)"
  type        = number
}
