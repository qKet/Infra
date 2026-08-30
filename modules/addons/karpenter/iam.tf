# Controller IAM Role(IRSA) + Node IAM Role/Instance Profile.
# Node Role은 modules/eks/iam.tf의 aws_iam_role.eks_node와 거의 동일하되, SSM 정책을 추가로 붙임
# (Karpenter가 새로 띄우는 노드는 SSH 접근 경로가 없어 SSM 세션으로 디버깅).

data "aws_caller_identity" "current" {}

# ── Controller IAM Role — kube-system의 karpenter 서비스어카운트만 assume 가능 ──
data "aws_iam_policy_document" "karpenter_controller_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(var.oidc_provider_url, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:karpenter"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(var.oidc_provider_url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "karpenter_controller" {
  name               = "${var.project_name}-karpenter-controller-role"
  assume_role_policy = data.aws_iam_policy_document.karpenter_controller_assume.json
}

# AWS 공식 Karpenter controller policy 최소 구성.
# - EC2 인스턴스/런치템플릿 생성·삭제·조회: Karpenter가 실제로 노드를 프로비저닝/디프로비저닝하는 부분
# - iam:PassRole: 새로 띄우는 EC2에 Node IAM Role(아래)을 붙여주려면 필요 — Node Role로 범위 제한
# - ssm:GetParameter: 최신 EKS 최적화 AMI ID를 SSM 파라미터에서 조회
# - pricing:GetProducts: 인스턴스 타입별 온디맨드/스팟 가격 비교(최적 조합 산정용)
# - eks:DescribeCluster: 클러스터 엔드포인트/CA 정보 조회
data "aws_iam_policy_document" "karpenter_controller" {
  statement {
    sid    = "Ec2Manage"
    effect = "Allow"
    actions = [
      "ec2:CreateLaunchTemplate",
      "ec2:CreateFleet",
      "ec2:RunInstances",
      "ec2:CreateTags",
      "ec2:TerminateInstances",
      "ec2:DeleteLaunchTemplate",
      "ec2:DescribeLaunchTemplates",
      "ec2:DescribeImages",
      "ec2:DescribeInstances",
      "ec2:DescribeInstanceTypes",
      "ec2:DescribeInstanceTypeOfferings",
      "ec2:DescribeAvailabilityZones",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSubnets",
      "ec2:DescribeSpotPriceHistory",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "PassNodeRole"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.karpenter_node.arn]
  }

  statement {
    sid       = "EksDescribe"
    effect    = "Allow"
    actions   = ["eks:DescribeCluster"]
    resources = ["arn:aws:eks:${var.aws_region}:${data.aws_caller_identity.current.account_id}:cluster/${var.cluster_name}"]
  }

  statement {
    sid       = "PricingRead"
    effect    = "Allow"
    actions   = ["pricing:GetProducts"]
    resources = ["*"]
  }

  statement {
    sid       = "SsmAmiLookup"
    effect    = "Allow"
    actions   = ["ssm:GetParameter"]
    resources = ["arn:aws:ssm:${var.aws_region}::parameter/aws/service/eks/optimized-ami/*"]
  }

  statement {
    sid       = "InterruptionQueueRead"
    effect    = "Allow"
    actions   = ["sqs:DeleteMessage", "sqs:GetQueueUrl", "sqs:ReceiveMessage"]
    resources = [aws_sqs_queue.karpenter_interruption.arn]
  }

  # Karpenter는 Node Role 이름만 주어지면 매칭되는 Instance Profile을 스스로 생성/조회/삭제함
  # (GetInstanceProfile 403 없으면 NodePool/EC2NodeClass가 Not Ready에 머무름).
  statement {
    sid    = "InstanceProfileManage"
    effect = "Allow"
    actions = [
      "iam:CreateInstanceProfile",
      "iam:TagInstanceProfile",
      "iam:AddRoleToInstanceProfile",
      "iam:RemoveRoleFromInstanceProfile",
      "iam:DeleteInstanceProfile",
      "iam:GetInstanceProfile",
    ]
    resources = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:instance-profile/*"]
  }

  # iam:ListInstanceProfiles는 리소스 레벨 제한을 지원 안 해서 resources="*" 필요.
  statement {
    sid       = "InstanceProfileList"
    effect    = "Allow"
    actions   = ["iam:ListInstanceProfiles"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "karpenter_controller" {
  name   = "${var.project_name}-karpenter-controller-policy"
  role   = aws_iam_role.karpenter_controller.id
  policy = data.aws_iam_policy_document.karpenter_controller.json
}

# ── Node IAM Role — Karpenter가 새로 띄우는 EC2가 실제로 assume하는 역할 ──
resource "aws_iam_role" "karpenter_node" {
  name = "${var.project_name}-karpenter-node-role"

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

resource "aws_iam_role_policy_attachment" "karpenter_node_worker" {
  role       = aws_iam_role.karpenter_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "karpenter_node_cni" {
  role       = aws_iam_role.karpenter_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "karpenter_node_ecr" {
  role       = aws_iam_role.karpenter_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# Karpenter가 새로 띄우는 노드는 상시 SSH 접근 경로가 없어서, 문제 생겼을 때 SSM 세션으로
# 들어가 디버깅하려면 이 정책이 필요 — modules/eks의 기존 노드 역할에는 없던 부분.
resource "aws_iam_role_policy_attachment" "karpenter_node_ssm" {
  role       = aws_iam_role.karpenter_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "karpenter_node" {
  name = "${var.project_name}-karpenter-node-profile"
  role = aws_iam_role.karpenter_node.name
}

# Karpenter가 만든 노드가 클러스터에 join하려면 이 Role이 kubelet 권한을 가져야 함 —
# modules/eks/access.tf와 동일하게 Access Entry API 사용. EC2_LINUX 타입은 EKS가 자동으로
# 노드용 최소 권한을 매핑해줌.
resource "aws_eks_access_entry" "karpenter_node" {
  cluster_name  = var.cluster_name
  principal_arn = aws_iam_role.karpenter_node.arn
  type          = "EC2_LINUX"
}
