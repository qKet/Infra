# SES 도메인 인증 — 이메일 인증번호/예매확정·취소/예매오픈 알림 발송(modules/lambda, 04_data에서
# release/prod 두 번 호출)용. 여기(03_registry, 공유·환경 구분 없음·절대 안 지움)에 두는 이유:
# 도메인 하나에 대한 SES 인증은 계정당 한 번만 해야 하는데, 04_data는 release/prod 두 워크스페이스로
# 두 번 apply되므로 거기 두면 같은 도메인을 두 번 인증하려다 충돌함. modules/lambda의 IAM 정책은 이
# 도메인 identity의 ARN을 계정/리전/도메인명으로 직접 계산해서 참조함(랜덤 접미사 없는 결정적 ARN이라
# remote_state 없이도 가능 — modules/lambda/main.tf 참고).
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
