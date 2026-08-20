# Cluster Autoscaler — EKS 관리형 노드그룹(modules/eks의 aws_eks_node_group)의 desired_size를
# min_size~max_size(01_infrastructure/variables.tf, 지금은 1~3) 사이에서 자동으로 조절해주는 컨트롤러.
# KEDA(파드 오토스케일링)와는 레이어가 다름 — KEDA가 파드를 늘려도 그 파드를 얹을 노드가 없으면
# Pending으로 멈추는데, 그 밑단(노드 레벨)을 이게 담당함. 2026-08-18 대용량 트래픽 용량 분석에서
# 이게 없어서 node_max_size=3이 사실상 장식값이었다는 게 드러남 — CLAUDE_LLM_WIKI의
# decisions/2026-08-18-capacity-planning-large-traffic-readiness 문서 참고.
#
# EKS 관리형 노드그룹은 밑단 ASG에 autodiscovery 태그(k8s.io/cluster-autoscaler/enabled=true,
# k8s.io/cluster-autoscaler/<클러스터명>=owned)를 AWS가 자동으로 붙여줌 — 실제 확인함(2026-08-18).
# 그래서 여기서 ASG 태그를 따로 만질 필요 없이 helm 설치만 하면 바로 그 태그로 autodiscovery됨.
#
# Karpenter 대신 이걸 선택한 이유: 지금 노드그룹이 인스턴스 타입 1종(t3.xlarge)·최대 3대뿐이라
# Karpenter의 강점(다양한 인스턴스 조합, Spot 최적화, 노드그룹 개념 자체를 대체)이 발휘될 여지가
# 적고, 반대로 Karpenter는 기존 Terraform 노드그룹 구조를 재설계해야 해서 지금 규모엔 과함.
# Cluster Autoscaler는 지금 이미 선언된 min/max를 그대로 활용하는 가장 낮은 비용의 선택.

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

  # 기본값(true)이면 kube-system에 DaemonSet이 아닌 파드(ALB Controller, metrics-server,
  # cluster-autoscaler 자기 자신 등 전부 kube-system에 떠있음, modules/addons/alb-controller·
  # metrics-server 참고)가 하나라도 있는 노드는 절대 스케일다운 대상으로 안 봐서, 사실상
  # 노드가 안 줄어드는 상태가 됨 — 이 프로젝트처럼 addon을 kube-system에 두는 구성에서 자주
  # 걸리는 함정이라 명시적으로 false로 둠.
  set {
    name  = "extraArgs.skip-nodes-with-system-pods"
    value = "false"
  }

  depends_on = [aws_iam_role_policy.cluster_autoscaler]
}

# 참고(2026-08-18 실제로 겪음, 재발 예상): 최초 apply 직후 파드가 정확히 1번
# "AccessDenied: Not authorized to perform sts:AssumeRoleWithWebIdentity"로 크래시하고
# Kubernetes가 자동 재시작한 뒤엔 정상 동작함 — IAM Role/ServiceAccount가 막 생성된 직후라
# IRSA(OIDC federated AssumeRoleWithWebIdentity) trust policy 전파에 약간의 지연이 있어서
# 생기는 일시적 레이스로 보임(ALB Controller의 admission webhook 레이스와 같은 계열 —
# CLAUDE_LLM_WIKI eks-destroy-layer-separation 참고). 매일 아침 02_k8s-addon을 재적용하는
# 루틴(daily-infrastructure-toggle)에서 매번 재현될 수 있으나, restartPolicy가 알아서
# 고쳐주므로 조치 불필요 — 재시작 횟수가 1에서 안 늘어나고 Running 상태면 정상.
