variable "domain_name" {
  description = "인증서를 발급할 도메인"
  type        = string
}

variable "zone_id" {
  description = "DNS 검증용 CNAME을 넣을 Route53 호스팅존 ID (이미 존재해야 함)"
  type        = string
}
