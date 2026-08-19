# 2026-08-19: EBS CSI 드라이버 — 클러스터에 PVC(영구 볼륨)를 요청하는 파드가 생기기 전까진
# 필요 없어서 지금까지 없었음(RDS/Redis/S3만 씀). Loki(로그 저장소, modules/addons/loki) 추가하면서
# 처음으로 PVC가 필요해졌는데, EKS는 이 드라이버가 기본 내장(vpc-cni/coredns/kube-proxy와 다르게)이
# 아니라서 명시적으로 addon 설치해야 함 — 안 하면 PVC가 "매칭되는 프로비저너 없음"으로 영원히
# Pending 상태에 머무름(실제로 이 addon 없이 겪은 증상).
data "aws_iam_policy_document" "ebs_csi_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.this.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.this.url, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.this.url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ebs_csi" {
  name               = "${var.project_name}-ebs-csi-role"
  assume_role_policy = data.aws_iam_policy_document.ebs_csi_assume.json
}

# AWS가 공식으로 관리하는 정책 그대로 씀 (EBS 볼륨 생성/삭제/연결 등에 필요한 최소 권한 세트)
resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

resource "aws_eks_addon" "ebs_csi" {
  cluster_name             = aws_eks_cluster.this.name
  addon_name               = "aws-ebs-csi-driver"
  service_account_role_arn = aws_iam_role.ebs_csi.arn

  # 이미 있는 버전과 충돌 안 나게 — 클러스터가 매일 destroy/재생성되는 환경이라
  # addon 버전을 못박기보다 그때그때 EKS가 권장하는 최신 호환 버전을 쓰는 게 관리 부담이 적음
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [aws_eks_node_group.this]
}
