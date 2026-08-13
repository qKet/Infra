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

variable "node_subnet_ids" {
  description = "워커 노드가 배치될 서브넷 (프라이빗-일반)"
  type        = list(string)
}

variable "node_instance_types" {
  description = "노드그룹 EC2 인스턴스 타입"
  type        = list(string)
}

variable "node_desired_size" {
  description = "노드그룹 기본 노드 수"
  type        = number
}

variable "node_min_size" {
  description = "노드그룹 최소 노드 수"
  type        = number
}

variable "node_max_size" {
  description = "노드그룹 최대 노드 수"
  type        = number
}
