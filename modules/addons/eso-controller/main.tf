# External Secrets Operator 컨트롤러 — 클러스터에 딱 하나만 있어야 하는 부분(Helm 릴리즈,
# CRD, IRSA 역할)만 여기 둠. release/prod(04_data)는 이 역할에 자기 시크릿 ARN만큼 정책만
# 추가로 붙이고(modules/addons/eso 참고), SecretStore/ExternalSecret 같은 동기화 규칙만 만듦 —
# 컨트롤러/CRD를 두 번 설치하면 이름 충돌·CRD 소유권 충돌이 나서 singleton으로 분리함.
# 02_k8s-addon이 04_data보다 먼저 apply되므로 depends_on 하나로 CRD 순서도 같이 보장됨.
resource "helm_release" "this" {
  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  namespace        = "external-secrets"
  create_namespace = true

  set {
    name  = "serviceAccount.create"
    value = "true"
  }

  set {
    name  = "serviceAccount.name"
    value = "external-secrets"
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.this.arn
  }

  depends_on = [
    aws_iam_role_policy.extra,
  ]
}
