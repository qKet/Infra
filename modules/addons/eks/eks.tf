# EKS 클러스터(컨트롤 플레인)
# 서브넷은 퍼블릭 + 프라이빗(일반)만 넘김 — private-data(DB/Redis)는 EKS와 완전히 분리 유지
resource "aws_eks_cluster" "this" {
  name     = "${var.project_name}-cluster"
  role_arn = aws_iam_role.eks_cluster.arn
  version  = var.eks_version

  vpc_config {
    subnet_ids              = var.cluster_subnet_ids
    endpoint_public_access  = true
    endpoint_private_access = true
  }

  # CONFIG_MAP(레거시, aws-auth 수동 편집)만 쓰면 클러스터 재생성될 때마다 접근 권한이
  # 같이 날아감 — API_AND_CONFIG_MAP으로 Access Entry(access.tf)를 같이 쓸 수 있게 함.
  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  depends_on = [aws_iam_role_policy_attachment.eks_cluster]
}

# 워커 노드 그룹 — 프라이빗(일반) 서브넷에만 배치 (private-data는 제외)
resource "aws_eks_node_group" "this" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.project_name}-node-group"
  node_role_arn   = aws_iam_role.eks_node.arn
  subnet_ids      = var.node_subnet_ids

  instance_types = var.node_instance_types

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_node_worker,
    aws_iam_role_policy_attachment.eks_node_cni,
    aws_iam_role_policy_attachment.eks_node_ecr,
  ]
}
