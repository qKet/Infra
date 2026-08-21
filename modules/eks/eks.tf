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

# 부트스트랩용 관리형 노드그룹 — 2026-08-20 Karpenter 마이그레이션 3단계로 완전히 제거했다가,
# 2026-08-21 최소 1개(고정)로 재도입함(variables.tf 상단 주석 참고). Karpenter/CoreDNS 등
# kube-system 파드가 뜰 최초의 노드가 없으면 클러스터 전체가 데드락에 빠지는 걸 실제로 겪음.
# 이후 실제 워크로드 스케일링은 전부 Karpenter(02_k8s-addon/module.karpenter)가 전담 — 이
# 노드그룹은 desired/min/max를 전부 1로 고정해서 순수 부트스트랩 floor로만 씀.
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
