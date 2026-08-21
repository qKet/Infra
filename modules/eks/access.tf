# 클러스터 admin 접근을 위한 공유 IAM Role.
# 팀원 추가/제거는 이 그룹 멤버십만 바꾸면 되고(IAM 콘솔/CLI), Role 자체는 안 건드리니
# terraform apply가 필요 없다.
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
