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

# node_subnet_ids/node_instance_types/node_desired_size/node_min_size/node_max_size는
# 2026-08-20 Karpenter 마이그레이션 3-4(정리)로 제거함 — 전부 관리형 노드그룹(3-3에서 제거)
# 전용 변수였음. 노드 크기/서브넷 결정은 이제 02_k8s-addon/module.karpenter의 NodePool/
# EC2NodeClass가 담당.
