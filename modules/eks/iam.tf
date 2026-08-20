# EKS 클러스터(컨트롤 플레인)가 다른 AWS 리소스(ENI, ELB 등)를 관리할 때 쓰는 역할
resource "aws_iam_role" "eks_cluster" {
  name = "${var.project_name}-eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# 워커 노드(EC2) IAM 역할 — 2026-08-20 Karpenter 마이그레이션 3-4(정리)로 제거함. 관리형
# 노드그룹(aws_eks_node_group.this, eks.tf에서 3-3에 이미 제거)이 assume하던 역할이라 노드그룹이
# 없어진 이상 완전히 고아(orphaned) 상태였음 — 노드 IAM은 이제 karpenter 모듈의
# aws_iam_role.karpenter_node(modules/addons/karpenter/iam.tf)가 전담. 과거 코드는 git
# history(이 커밋 이전)에서 확인 가능.
