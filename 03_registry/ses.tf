# SES 도메인 인증 — 이메일 알림 발송(modules/lambda, 04_data가 release/prod 두 번 호출)용.
# 도메인 인증은 계정당 한 번만 해야 해서 04_data(release/prod 두 번 apply)가 아니라 여기 둠.
resource "aws_ses_domain_identity" "this" {
  domain = "jun979.click"
}

resource "aws_route53_record" "ses_verification" {
  zone_id = "Z0111999JD2RHOSHTM8A" # jun979.click
  name    = "_amazonses.${aws_ses_domain_identity.this.domain}"
  type    = "TXT"
  ttl     = 600
  records = [aws_ses_domain_identity.this.verification_token]
}

resource "aws_ses_domain_identity_verification" "this" {
  domain     = aws_ses_domain_identity.this.domain
  depends_on = [aws_route53_record.ses_verification]
}

# DKIM — 이걸 안 하면 이메일이 스팸함으로 직행할 확률이 높음(발신 도메인 인증이 없으면 대부분의
# 메일 서비스가 신뢰 안 함). 토큰 3개가 나오고, 각각 CNAME 레코드로 등록해야 함.
resource "aws_ses_domain_dkim" "this" {
  domain = aws_ses_domain_identity.this.domain
}

resource "aws_route53_record" "ses_dkim" {
  count   = 3
  zone_id = "Z0111999JD2RHOSHTM8A" # jun979.click
  name    = "${element(aws_ses_domain_dkim.this.dkim_tokens, count.index)}._domainkey.${aws_ses_domain_identity.this.domain}"
  type    = "CNAME"
  ttl     = 600
  records = ["${element(aws_ses_domain_dkim.this.dkim_tokens, count.index)}.dkim.amazonses.com"]
}

# SPF — "이 도메인 메일은 Amazon SES를 통해서만 발송된다"를 선언하는 TXT 레코드.
# DKIM(서명 검증)과 별개로 발신 출처 자체를 검증하는 용도라, 스팸함행 방지를 위해 DKIM과 같이 있어야 함.
# apex(jun979.click) 도메인에 기존 TXT 레코드 없음을 확인 후 추가(2026-08-21, list-resource-record-sets로 확인).
resource "aws_route53_record" "spf" {
  zone_id = "Z0111999JD2RHOSHTM8A" # jun979.click
  name    = "jun979.click"
  type    = "TXT"
  ttl     = 600
  records = ["v=spf1 include:amazonses.com ~all"]
}
