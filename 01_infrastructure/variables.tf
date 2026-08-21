variable "project_name" {
  description = "리소스 이름"
  type        = string
  default     = "team5-qket"
}

variable "team_tag" {
  description = "공통 팀 테그(필수)"
  type        = string
  default     = "team5"
}

variable "aws_region" {
  description = "리소스를 생성할 AWS 리전"
  type        = string
  default     = "ap-northeast-2"
}

/*******************
*     NetWork
*******************/
variable "azs" {
  description = "가용영역 목록"
  type        = list(string)
  default     = ["ap-northeast-2a", "ap-northeast-2b"]
}

/*******************
*     EKS
*******************/
variable "eks_version" {
  description = "EKS 클러스터 쿠버네티스 버전"
  type        = string
  default     = "1.36"
}


# 2026-08-21 재도입 — Karpenter/CoreDNS 등이 뜰 최초의 노드가 없으면 데드락에 빠지는 걸
# 실제로 겪어서, 부트스트랩용 노드 1개(고정)를 다시 둠(modules/eks/eks.tf 상단 주석 참고).
# desired/min/max를 전부 1로 고정 — 오토스케일링은 이제 karpenter(NodePool)가 전담이라
# 이 노드그룹은 순수 부트스트랩 floor 역할만 함.
variable "node_instance_types" {
  description = "부트스트랩 노드그룹 EC2 인스턴스 타입 — kube-system 파드(CoreDNS/Karpenter/ALB Controller/ArgoCD/ExternalDNS/EBS CSI 등)가 동시에 뜰 수 있어야 함(t3.medium은 부족했던 걸 실측함)"
  type        = list(string)
  default     = ["t3.large"]
}

variable "node_desired_size" {
  description = "부트스트랩 노드 수"
  type        = number
  default     = 1
}

variable "node_min_size" {
  description = "부트스트랩 노드 최소"
  type        = number
  default     = 1
}

variable "node_max_size" {
  description = "부트스트랩 노드 최대 "
  type        = number
  default     = 1
}

/*******************
*     Bastion (SSM)
*******************/
variable "bastion_instance_type" {
  description = "SSM bastion 인스턴스 타입 — 터널링 용도라 최소 사양"
  type        = string
  default     = "t3.micro"
}
