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

output "backend_role_name" {
  description = "백엔드 IRSA IAM 역할 이름 — 04_data에서 SQS 발행 권한 등 다른 모듈이 만든 리소스에 대한 정책을 추가로 붙일 때 씀"
  value       = aws_iam_role.backend.name
}

output "backend_service_account_name" {
  description = "백엔드 파드가 써야 하는 ServiceAccount 이름"
  value       = kubernetes_service_account.backend.metadata[0].name
}
