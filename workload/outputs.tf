output "namespace" {
  description = "생성된 쿠버네티스 네임스페이스 이름"
  value       = kubernetes_namespace.this.metadata[0].name
}

output "rds_endpoint" {
  description = "RDS 엔드포인트 (DB_HOST)"
  value       = module.rds.rds_endpoint
}

output "rds_master_user_secret_arn" {
  description = "RDS 마스터 비밀번호가 저장된 Secrets Manager ARN"
  value       = module.rds.rds_master_user_secret_arn
}

output "redis_endpoint" {
  description = "ElastiCache Redis 엔드포인트 (REDIS_HOST)"
  value       = module.redis.redis_endpoint
}

output "s3_bucket_name" {
  description = "포스터 S3 버킷 이름"
  value       = module.storage.bucket_name
}

output "cloudfront_domain" {
  description = "CloudFront 배포 도메인"
  value       = module.storage.cloudfront_domain
}

output "backend_irsa_role_arn" {
  description = "백엔드 IRSA IAM 역할 ARN"
  value       = module.storage.backend_role_arn
}
