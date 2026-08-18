variable "project_name" {
  description = "리소스 이름 접두사"
  type        = string
}

variable "environment" {
  description = "환경 구분 (dev/prod)"
  type        = string
}

variable "aws_region" {
  description = "AWS 리전"
  type        = string
}

variable "namespace" {
  description = "db-secrets/redis-secrets를 생성할 쿠버네티스 네임스페이스 (미리 존재해야 함)"
  type        = string
}

variable "oidc_provider_arn" {
  description = "IRSA용 OIDC 프로바이더 ARN (module.eks 출력값)"
  type        = string
}

variable "oidc_provider_url" {
  description = "IRSA용 OIDC 프로바이더 URL (module.eks 출력값)"
  type        = string
}

variable "rds_master_user_secret_arn" {
  description = "RDS가 자동 생성한 마스터 계정 Secrets Manager ARN (건드리지 않고 읽기만 함)"
  type        = string
}

variable "rds_endpoint" {
  description = "RDS 엔드포인트 — connection 시크릿의 DB_HOST 값으로 씀"
  type        = string
}

variable "redis_endpoint" {
  description = "ElastiCache Redis 엔드포인트 — connection 시크릿의 REDIS_HOST 값으로 씀"
  type        = string
}

variable "secret_recovery_window_days" {
  description = "connection 시크릿 삭제 시 대기기간(일) — release는 0(바로 삭제, 재생성 충돌 방지), prod는 7 이상 권장(실수 삭제 대비)"
  type        = number
  default     = 0
}

variable "extra_secret_arns" {
  description = "db/redis/external_api 외에 이 ESO Role이 추가로 읽어야 하는 Secrets Manager ARN 목록 (예: 다른 root에서 만든 시크릿을 재사용할 때)"
  type        = list(string)
  default     = []
}

# 토스/OAuth 등 외부 API 키 — RDS/Redis 엔드포인트처럼 Terraform이 자동 계산하는 값이 아니라
# 사람이 외부 서비스(토스 대시보드, 각 provider 개발자 콘솔)에서 직접 발급받은 값이라 변수로 받음.
# TF_VAR_external_api_keys='{"toss_secret_key":"...",...}' 형태로 넘기거나, 각 필드를
# TF_VAR_external_api_keys_토스_secret_key 식으로는 못 넘기므로(object 변수라 통째로 넘겨야 함)
# gitignore된 .tfvars 파일에 담아서 -var-file로 넘기는 걸 권장. 기본값은 전부 빈 문자열이라
# 값을 안 넘기면 앱에서 그냥 빈 값으로 떨어짐(기존 폴백 동작 그대로 — 신규 기능 끊김 없음).
variable "external_api_keys" {
  description = "토스/OAuth 등 외부 API 키 — 사람이 직접 발급받은 값"
  type = object({
    toss_secret_key      = string
    toss_client_key      = string # 프론트 NEXT_PUBLIC_TOSS_CLIENT_KEY용 — CI가 빌드 시점에 직접 가져감(ESO 경로 안 씀)
    google_client_id     = string
    google_client_secret = string
    kakao_client_id      = string
    kakao_client_secret  = string
    naver_client_id      = string
    naver_client_secret  = string
  })
  sensitive = true
  default = {
    toss_secret_key      = ""
    toss_client_key      = ""
    google_client_id     = ""
    google_client_secret = ""
    kakao_client_id      = ""
    kakao_client_secret  = ""
    naver_client_id      = ""
    naver_client_secret  = ""
  }
}
