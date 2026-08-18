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
    "121.128.146.191/32", # 진호
    "123.214.77.21/32"    # 우진
  ]
}

resource "kubernetes_ingress_v1" "grafana" {
  metadata {
    name      = "grafana-ingress"
    namespace = "monitoring"

    annotations = {
      "alb.ingress.kubernetes.io/group.name"         = "qket-admin"
      "alb.ingress.kubernetes.io/group.order"        = "10"
      "alb.ingress.kubernetes.io/tags"               = "Team=team5,Project=qket"
      "alb.ingress.kubernetes.io/load-balancer-name" = "team5-qket-admin-alb"
      "alb.ingress.kubernetes.io/scheme"             = "internet-facing"
      "alb.ingress.kubernetes.io/target-type"        = "ip"
      "alb.ingress.kubernetes.io/certificate-arn"    = aws_acm_certificate_validation.grafana.certificate_arn
      "alb.ingress.kubernetes.io/ssl-redirect"       = "443"
      "alb.ingress.kubernetes.io/listen-ports"       = "[{\"HTTP\":80},{\"HTTPS\":443}]"
      "alb.ingress.kubernetes.io/inbound-cidrs"      = join(",", local.admin_allowed_cidrs)
      # 기본 헬스체크 경로("/")는 로그인 안 된 상태에서 302를 줘서 비정상으로 뜸(backend 때와 같은
      # 종류의 문제) — Grafana 전용 헬스 엔드포인트(로그인 여부 무관하게 200 고정)로 지정.
      "alb.ingress.kubernetes.io/healthcheck-path" = "/api/health"
    }
  }

  spec {
    ingress_class_name = "alb"

    rule {
      host = "grafana.jun979.click"

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = "monitoring-grafana"
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }

  wait_for_load_balancer = false

  depends_on = [module.alb_controller, module.monitoring]
}

resource "kubernetes_ingress_v1" "argocd" {
  metadata {
    name      = "argocd-ingress"
    namespace = "argocd"

    annotations = {
      "alb.ingress.kubernetes.io/group.name"         = "qket-admin"
      "alb.ingress.kubernetes.io/group.order"        = "20"
      "alb.ingress.kubernetes.io/tags"               = "Team=team5,Project=qket"
      "alb.ingress.kubernetes.io/load-balancer-name" = "team5-qket-admin-alb"
      "alb.ingress.kubernetes.io/scheme"             = "internet-facing"
      "alb.ingress.kubernetes.io/target-type"        = "ip"
      "alb.ingress.kubernetes.io/certificate-arn"    = aws_acm_certificate_validation.argocd.certificate_arn
      "alb.ingress.kubernetes.io/ssl-redirect"       = "443"
      "alb.ingress.kubernetes.io/listen-ports"       = "[{\"HTTP\":80},{\"HTTPS\":443}]"
      "alb.ingress.kubernetes.io/inbound-cidrs"      = join(",", local.admin_allowed_cidrs)
      # Grafana와 같은 이유 — argocd-server 자체 readiness probe 경로(/healthz)를 그대로 씀,
      # 로그인 여부 무관하게 200 고정이라 안전함.
      "alb.ingress.kubernetes.io/healthcheck-path" = "/healthz"
    }
  }

  spec {
    ingress_class_name = "alb"

    rule {
      host = "cd.jun979.click"

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = "argocd-server"
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }

  wait_for_load_balancer = false

  depends_on = [module.alb_controller, helm_release.argocd]
}
