output "rds_release_endpoint" {
  description = "release RDS 엔드포인트 (DB_HOST)"
  value       = module.data_release.rds_endpoint
}

output "rds_release_master_user_secret_arn" {
  description = "release RDS 마스터 비밀번호가 저장된 Secrets Manager ARN"
  value       = module.data_release.rds_master_user_secret_arn
}

output "redis_release_endpoint" {
  description = "release ElastiCache Redis 엔드포인트 (REDIS_HOST)"
  value       = module.data_release.redis_endpoint
}

output "eso_role_arn" {
  description = "External Secrets Operator IRSA IAM 역할 ARN"
  value       = module.eso_release.role_arn
}

output "eso_connection_secret_arn" {
  description = "DB_HOST/REDIS_HOST를 담은 커스텀 Secrets Manager ARN"
  value       = module.eso_release.connection_secret_arn
}

output "s3_bucket_name_release" {
  description = "release 포스터 S3 버킷 이름"
  value       = module.storage_release.bucket_name
}

output "cloudfront_domain_release" {
  description = "release CloudFront 도메인"
  value       = module.storage_release.cloudfront_domain
}

output "backend_irsa_role_arn_release" {
  description = "release 백엔드 IRSA IAM 역할 ARN"
  value       = module.storage_release.backend_role_arn
}
