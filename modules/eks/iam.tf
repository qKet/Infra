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

# 부트스트랩 노드그룹(위 eks.tf) 전용 역할 — 2026-08-21 재도입(eks.tf 상단 주석 참고).
# Karpenter가 만드는 노드는 별도로 modules/addons/karpenter/iam.tf의 aws_iam_role.karpenter_node를
# 쓰고, 이 역할은 최초 부트스트랩 노드 1개만을 위한 것 — 순환 의존(karpenter 모듈이 02_k8s-addon
# 소속이라 01_infrastructure가 그 역할을 참조할 수 없음) 없이 여기서 자체적으로 완결시킴.
resource "aws_iam_role" "eks_node" {
  name = "${var.project_name}-eks-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# 노드가 클러스터에 join해서 kubelet으로 동작하는 데 필요한 기본 권한
resource "aws_iam_role_policy_attachment" "eks_node_worker" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

# VPC CNI 플러그인이 파드에 ENI/IP를 붙여주는 데 필요한 권한
resource "aws_iam_role_policy_attachment" "eks_node_cni" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

# ECR에서 컨테이너 이미지를 pull하는 데 필요한 권한
resource "aws_iam_role_policy_attachment" "eks_node_ecr" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}
