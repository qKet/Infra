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

output "open_alert_queue_url" {
  description = "예매 오픈 알림 SQS 큐 URL — CD 헬름 차트 configMaps에 OPEN_ALERT_QUEUE_URL로 들어가는 값과 같은지 대조용"
  value       = module.open_alert_queue.queue_url
}

output "open_alert_mailer_function_name" {
  description = "예매 오픈 알림 발송 Lambda 함수 이름 (CloudWatch Logs 조회 등에 씀)"
  value       = module.open_alert_mailer.function_name
}
