# SES 도메인 인증 — 이메일 인증번호 발송(modules/messaging, 04_data에서 release/prod 두 번 호출)용.
# 여기(03_registry, 공유·환경 구분 없음·절대 안 지움)에 두는 이유: 도메인 하나에 대한 SES 인증은
# 계정당 한 번만 해야 하는데, 04_data는 release/prod 두 워크스페이스로 두 번 apply되므로 거기 두면
# 같은 도메인을 두 번 인증하려다 충돌함. modules/messaging의 IAM 정책은 이 도메인 identity의
# ARN을 계정/리전/도메인명으로 직접 계산해서 참조함(랜덤 접미사 없는 결정적 ARN이라 remote_state
# 없이도 가능 — modules/messaging/iam.tf 참고).
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
