# [사용 안 함 — Karpenter로 전면 교체됨(02_k8s-addon/main.tf 참고), 이 모듈은 호출되지 않음]
# Cluster Autoscaler — EKS 관리형 노드그룹의 desired_size를 min~max 사이에서 자동 조절하던
# 컨트롤러. KEDA(파드 오토스케일링)와는 레이어가 다름 — 노드 레벨을 이게 담당했었음.

# ── 설치 (Helm) ──
resource "helm_release" "cluster_autoscaler" {
  name       = "cluster-autoscaler"
  repository = "https://kubernetes.github.io/autoscaler"
  chart      = "cluster-autoscaler"
  namespace  = "kube-system"

  set {
    name  = "autoDiscovery.clusterName"
    value = var.cluster_name
  }

  set {
    name  = "awsRegion"
    value = var.aws_region
  }

  # cluster-autoscaler 이미지는 클러스터 마이너 버전과 맞춰야 노드 API 호환성이 보장됨
  # (AWS 공식 권장) — eks_version을 올릴 때 이것도 같이 올릴 것.
  set {
    name  = "image.tag"
    value = "v${var.eks_version}.0"
  }

  set {
    name  = "rbac.serviceAccount.name"
    value = "cluster-autoscaler"
  }

  set {
    name  = "rbac.serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.cluster_autoscaler.arn
  }

  # 기본값(true)이면 kube-system에 떠있는 addon 파드 때문에 노드가 절대 스케일다운 안 됨.
  set {
    name  = "extraArgs.skip-nodes-with-system-pods"
    value = "false"
  }

  depends_on = [aws_iam_role_policy.cluster_autoscaler]
}

# 참고: 최초 apply 직후 파드가 1번 AssumeRoleWithWebIdentity 실패로 크래시하고 자동 재시작
# 후 정상 동작함 — IRSA trust policy 전파 지연에 의한 일시적 레이스, 조치 불필요.
