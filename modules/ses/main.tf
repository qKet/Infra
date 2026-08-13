# NOTI01_ALERT01(취소표 알림)용 발신 도메인. 이 리소스는 "새로 만드는" 용도가 아니라, 콘솔에서 이미
# verify + 프로덕션 액세스까지 끝낸 기존 도메인(jun979.click)을 Terraform state로 편입(import)하는 용도.
#
# ⚠️ 반드시 import 먼저 하고 apply할 것 — 아래 두 리소스는 각각:
#   terraform import module.ses.aws_ses_domain_identity.this jun979.click
#   terraform import module.ses.aws_ses_domain_dkim.this jun979.click
# import 없이 이 리소스가 새로 "생성"되면(특히 DKIM), SES가 새 DKIM 토큰을 발급해서 지금 DNS에 걸려있는
# CNAME 값과 어긋날 수 있고, 그 순간부터 재검증 전까지 발송이 끊긴다. prevent_destroy로 실수로 지우는 것도 막아둠.
resource "aws_ses_domain_identity" "this" {
  domain = var.domain

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_ses_domain_dkim" "this" {
  domain = aws_ses_domain_identity.this.domain

  lifecycle {
    prevent_destroy = true
  }
}
