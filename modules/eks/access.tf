# 클러스터 admin 접근을 위한 공유 IAM Role.
#
# 트러스트 정책은 계정 전체(root)를 신뢰하되, 실제로 assume 가능한 사람은
# ${project_name}-cluster-admins IAM 그룹 멤버십으로 제한한다 — AWS 계정 안에서
# role을 assume하려는 principal은 (1) role의 trust policy가 허용 + (2) 자기 자신의
# identity policy에 sts:AssumeRole 권한이 있어야 하는 이중 게이트라, 그룹 정책으로
# (2)를 관리하면 된다.
#
# 팀원 추가/제거는 이 그룹 멤버십만 바꾸면 되고(IAM 콘솔/CLI), Role 자체는 안 건드리니
# terraform apply가 필요 없다. 개인 IAM ARN이 .tf 코드에 안 남는다는 장점도 있음.
data "aws_caller_identity" "current" {}

resource "aws_iam_role" "cluster_admin" {
  name = "${var.project_name}-cluster-admin"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_group" "cluster_admins" {
  name = "${var.project_name}-cluster-admins"
}

resource "aws_iam_group_policy" "assume_cluster_admin" {
  name  = "${var.project_name}-assume-cluster-admin"
  group = aws_iam_group.cluster_admins.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "sts:AssumeRole"
        Resource = aws_iam_role.cluster_admin.arn
      }
    ]
  })
}

resource "aws_eks_access_entry" "cluster_admin_role" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = aws_iam_role.cluster_admin.arn
}

resource "aws_eks_access_policy_association" "cluster_admin_role" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = aws_iam_role.cluster_admin.arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }
}
