# ── ExternalDNS 설치 (Helm) ──
resource "helm_release" "external_dns" {
  name       = "external-dns"
  repository = "https://kubernetes-sigs.github.io/external-dns/"
  chart      = "external-dns"
  namespace  = "kube-system"

  set {
    name  = "provider"
    value = "aws"
  }

  set {
    name  = "aws.region"
    value = var.aws_region
  }

  # 이중 방어: IAM이 이미 hosted_zone_id 하나로 권한을 좁혀놨지만, 이 필터도 같이 걸어서
  # 혹시 모를 실수(다른 zone에 있는 레코드 건드리기)를 애초에 후보에서 제외함.
  set {
    name  = "domainFilters[0]"
    value = var.domain_filter
  }

  # Gateway API 마이그레이션 1단계(release 파일럿) 대응 — 차트 기본값은 sources: [service, ingress]뿐이라
  # HTTPRoute를 아예 감시 안 함. gateway-httproute를 추가해야 Gateway API의 Gateway/HTTPRoute
  # hostname을 보고도 Route53 레코드를 만들어줌(기존 service/ingress 감시는 그대로 유지, 순수 추가).
  # 주의: 이 sources가 켜진 채로 Gateway API CRD가 클러스터에 없으면 external-dns 파드가
  # 시작 시 해당 kind를 못 찾아 크래시루프 날 수 있음 — module.gateway_api_crds가 먼저 설치돼
  # 있어야 하므로, 이 모듈을 부르는 02_k8s-addon/main.tf에서 depends_on으로 순서를 강제한다.
  set {
    name  = "sources[0]"
    value = "service"
  }

  set {
    name  = "sources[1]"
    value = "ingress"
  }

  set {
    name  = "sources[2]"
    value = "gateway-httproute"
  }

  # upsert-only: Ingress가 지워져도 DNS 레코드는 안 지움 — 공유 계정에서 실수로 남의 레코드까지
  # 건드리는 것보다, 안 쓰는 레코드가 좀 남는 게 안전하다고 판단. 필요해지면 "sync"로 바꿀 것.
  set {
    name  = "policy"
    value = "upsert-only"
  }

  # 같은 zone을 여러 ExternalDNS 인스턴스가 공유할 경우 TXT 레코드로 소유권 구분하는 값.
  set {
    name  = "txtOwnerId"
    value = var.project_name
  }

  set {
    name  = "serviceAccount.create"
    value = "true"
  }

  set {
    name  = "serviceAccount.name"
    value = "external-dns"
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.external_dns.arn
  }

  depends_on = [
    aws_iam_role_policy.external_dns,
  ]
}
