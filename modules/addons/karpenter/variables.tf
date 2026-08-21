variable "project_name" {
  description = "리소스 이름 접두사"
  type        = string
}

variable "aws_region" {
  description = "AWS 리전"
  type        = string
}

variable "cluster_name" {
  description = "EKS 클러스터 이름 — Access Entry, SQS/EventBridge 이벤트 필터의 인스턴스 태그 조건 등에 사용"
  type        = string
}

variable "oidc_provider_arn" {
  description = "IRSA용 OIDC 프로바이더 ARN (module.eks 출력값)"
  type        = string
}

variable "oidc_provider_url" {
  description = "IRSA용 OIDC 프로바이더 URL (module.eks 출력값)"
  type        = string
}

variable "node_subnet_ids" {
  description = "Karpenter가 새 노드를 띄울 서브넷 ID 목록 — modules/eks의 기존 노드그룹과 동일한 프라이빗(일반) 서브넷 사용"
  type        = list(string)
}

variable "cluster_security_group_id" {
  description = "EKS가 자동 생성한 클러스터 보안 그룹 ID — Karpenter 노드도 기존 노드그룹과 동일하게 이 SG를 사용"
  type        = string
}

variable "node_instance_types" {
  description = "Karpenter NodePool이 고를 수 있는 인스턴스 타입 후보군 — 넓게 줄수록 워크로드 크기에 맞춰 최적화 여지가 커짐(2026-08-20 결정: t3.medium~xlarge)"
  type        = list(string)
  default     = ["t3.medium", "t3.large", "t3.xlarge"]
}

variable "capacity_types" {
  description = "온디맨드/스팟 중 어떤 용량을 쓸지 — 세션(Redis) 상태를 가진 서비스가 있어 당장은 온디맨드만(2026-08-20 결정), 안정성 확인 후 spot 추가 고려"
  type        = list(string)
  default     = ["on-demand"]
}

variable "consolidation_policy" {
  description = "노드 정리 정책 — WhenEmptyOrUnderutilized(빈 자리 있으면 파드 재배치 후 통합, 비용 최적화 큼) vs WhenEmpty(완전히 빌 때만). 2026-08-20 결정: WhenEmptyOrUnderutilized"
  type        = string
  default     = "WhenEmptyOrUnderutilized"
}

variable "karpenter_chart_version" {
  description = "Karpenter Helm 차트 버전 — 빠르게 릴리즈되는 차트라 apply 전에 helm show chart oci://public.ecr.aws/karpenter/karpenter --version <값>으로 실제 존재하는지 한 번 확인 권장(2026-08-20 기준 최신 1.14.0)"
  type        = string
  default     = "1.14.0"
}
