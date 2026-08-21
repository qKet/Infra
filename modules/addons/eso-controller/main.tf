# External Secrets Operator 컨트롤러 — 클러스터에 딱 하나만 있어야 하는 부분(Helm 릴리즈 자체,
# CRD, IRSA 역할)만 여기 둠. release/prod(04_data)는 이 역할(module.eso_controller.role_name)에
# 자기 시크릿 ARN만큼 정책만 추가로 붙이고(modules/addons/eso 참고), SecretStore/ExternalSecret
# 같은 실제 동기화 규칙만 만듦 — 컨트롤러나 CRD를 두 번 설치하는 일이 없음.
#
# 2026-08-21: release/prod가 각자 modules/addons/eso를 호출하며 컨트롤러까지 통째로 설치하던
# 구조에서 여기로 이전. 그 구조에서는 이름 충돌(IAM Role already exists — 04_data/prod가 나중에
# apply되면서 실제로 겪음)과 CRD 소유권 충돌(invalid ownership metadata, CRD가 네임스페이스와
# 무관하게 클러스터에 하나뿐이라 두 번째 helm_release가 재설치를 시도하며 발생)이 났었고,
# environment 접미사 + installCRDs 토글로 땜빵했었음. 애초에 "공유 singleton은 한 곳에만 두면
# 된다"는 게 맞는 해법이라 이렇게 옮김.
#
# 부수 효과: 02_k8s-addon이 04_data보다 먼저 apply되는 정상 순서 그대로라, modules/addons/argocd/
# notifications-secrets가 겪던 cross-root CRD 순서 문제(ESO가 04_data라는 "나중" root에 있어서
# 매번 "04_data의 module.eso를 먼저 apply해야 하는" 런북 절차가 필요했음 — CLAUDE_LLM_WIKI
# troubleshooting/crd-not-yet-installed-on-fresh-apply 참고)도 같이 해결됨. 이제 ESO 컨트롤러가
# 같은 root(02_k8s-addon) 안에 있으므로 depends_on 하나로 순서가 보장됨.
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
