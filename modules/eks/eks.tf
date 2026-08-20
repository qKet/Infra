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

# 워커 노드 그룹 — 2026-08-20 Karpenter 마이그레이션 3단계로 완전히 제거함(방식 A: 전면 교체).
# 기존에는 여기서 관리형 노드그룹(aws_eks_node_group.this)을 직접 만들었으나, 이제 노드 생성/
# 삭제는 02_k8s-addon/module.karpenter가 전담. IAM Role(eks_node, iam.tf)은 과거 노드가 이미
# assume했던 역할이라 흔적 정리 차원에서 일단 남겨둠(3-4 정리 단계에서 필요 여부 재검토 예정).
# 과거 코드는 git history(이 커밋 이전)에서 확인 가능.
