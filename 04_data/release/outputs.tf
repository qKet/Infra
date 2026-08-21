# release는 RDS/Redis가 없음 — 아래 세 출력은 dev-datastore(02_k8s-addon) 쪽 동등한 값으로 대신함.
# (prod/outputs.tf의 같은 이름 출력과 인터페이스를 맞춰두면, 어느 디렉토리를 보든 "이 환경의
# DB_HOST/시크릿이 뭐냐"를 같은 output 이름으로 조회할 수 있어서 유지)
output "rds_endpoint" {
  description = "release는 RDS가 없음 — dev-mysql 서비스명(같은 네임스페이스 qket-release 안에서만 유효)"
  value       = "dev-mysql"
}

output "rds_master_user_secret_arn" {
  description = "release는 RDS가 없음 — 03_registry의 dev_mysql_root_secret_arn(RDS 마스터 시크릿과 같은 username/password 모양)"
  value       = data.terraform_remote_state.registry.outputs.dev_mysql_root_secret_arn
}

output "redis_endpoint" {
  description = "release는 Redis가 없음 — dev-redis 서비스명(같은 네임스페이스 qket-release 안에서만 유효)"
  value       = "dev-redis"
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
