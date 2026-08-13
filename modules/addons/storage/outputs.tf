output "bucket_name" {
  description = "포스터 S3 버킷 이름"
  value       = aws_s3_bucket.posters.bucket
}

output "cloudfront_domain" {
  description = "CloudFront 배포 도메인"
  value       = aws_cloudfront_distribution.posters.domain_name
}

output "backend_role_arn" {
  description = "백엔드 IRSA IAM 역할 ARN"
  value       = aws_iam_role.backend.arn
}

output "backend_service_account_name" {
  description = "백엔드 파드가 써야 하는 ServiceAccount 이름"
  value       = kubernetes_service_account.backend.metadata[0].name
}
