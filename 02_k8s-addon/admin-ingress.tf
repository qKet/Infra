# Grafana/ArgoCD — 팀 내부용 관리 도구. 공개 앱(app_ingress_backend/frontend)과는 별도 ALB를 쓰지만
# (관리 도구가 원래 공개 앱보다 보안 요구사항이 높음), 둘끼리는 group.name을 공유해서 ALB 하나로
# 합침 — 4인 팀 규모라 "Grafana든 ArgoCD든 팀원이면 접속 가능, 팀 밖이면 둘 다 차단"이면 충분하고,
# ALB를 하나 더 아낄 수 있음(2026-08-12, 처음엔 도구별로 IP를 다르게 주려고 분리했다가 합침).
# inbound-cidrs는 그룹 전체가 공유하는 보안그룹 단위로 적용되므로, 이제 두 Ingress 다 같은
# admin_allowed_cidrs를 씀 — 개별 도구별로 다른 IP를 주고 싶어지면 다시 group.name을 나눠야 함.

# grafana.jun979.click / cd.jun979.click 전용 인증서 — 기존 dev/app 인증서는 그 도메인 전용이라
# (와일드카드 아님, aws acm describe-certificate로 확인) 새로 발급해야 함. DNS 검증은 이미 있는
# jun979.click 호스팅존에 검증용 CNAME을 Terraform이 직접 넣어서 사람 개입 없이 자동으로 끝남.
resource "aws_acm_certificate" "grafana" {
  domain_name       = "grafana.jun979.click"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "grafana_cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.grafana.domain_validation_options : dvo.domain_name => {
      name  = dvo.resource_record_name
      type  = dvo.resource_record_type
      value = dvo.resource_record_value
    }
  }

  zone_id = "Z0111999JD2RHOSHTM8A" # jun979.click
  name    = each.value.name
  type    = each.value.type
  records = [each.value.value]
  ttl     = 60
}

resource "aws_acm_certificate_validation" "grafana" {
  certificate_arn         = aws_acm_certificate.grafana.arn
  validation_record_fqdns = [for r in aws_route53_record.grafana_cert_validation : r.fqdn]
}

resource "aws_acm_certificate" "argocd" {
  domain_name       = "cd.jun979.click"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "argocd_cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.argocd.domain_validation_options : dvo.domain_name => {
      name  = dvo.resource_record_name
      type  = dvo.resource_record_type
      value = dvo.resource_record_value
    }
  }

  zone_id = "Z0111999JD2RHOSHTM8A" # jun979.click
  name    = each.value.name
  type    = each.value.type
  records = [each.value.value]
  ttl     = 60
}

resource "aws_acm_certificate_validation" "argocd" {
  certificate_arn         = aws_acm_certificate.argocd.arn
  validation_record_fqdns = [for r in aws_route53_record.argocd_cert_validation : r.fqdn]
}

# 허용 IP 목록 — 팀원 IP가 추가되면 이 리스트에 한 줄씩 추가하면 됨(2026-08-12 기준: 팀원 1 + 본인).
# Grafana/ArgoCD 둘 다 이 목록 하나를 공유함(위 주석 참고).
locals {
  admin_allowed_cidrs = [
    "222.111.119.115/32", # 윤준
    "121.138.193.90/32",  # 채영
    "162.120.184.59/32",  # 진호
    "123.214.77.21/32"    # 우진
  ]
}

# 2026-08-20: kubernetes_ingress_v1.grafana/argocd를 여기서 완전히 제거 — Gateway API로 이관.
# 인증서(aws_acm_certificate.grafana/argocd)는 그대로 재사용하고, 실제 Gateway/HTTPRoute/
# LoadBalancerConfiguration(sourceRanges = local.admin_allowed_cidrs)은
# module.gateway_api_admin(02_k8s-addon/main.tf)이 만든다 — dev(release)도 "개발 서버는
# 관리자만 들어가야 한다"는 결정에 따라 같은 admin Gateway로 옮겨서 이 3개가 ALB 하나(SNI 다중
# 인증서)와 IP 허용목록을 공유한다. 자세한 내용은 CLAUDE_LLM_WIKI
# decisions/2026-08-20-ingress-to-gateway-api-migration 참고.
