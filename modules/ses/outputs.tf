output "identity_arn" {
  value = aws_ses_domain_identity.this.arn
}

output "domain" {
  value = aws_ses_domain_identity.this.domain
}
