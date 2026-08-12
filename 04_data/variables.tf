variable "project_name" {
  description = "리소스 이름"
  type        = string
  default     = "team5-qket"
}

variable "team_tag" {
  description = "공통 팀 테그(필수)"
  type        = string
  default     = "team5"
}

variable "aws_region" {
  description = "리소스를 생성할 AWS 리전"
  type        = string
  default     = "ap-northeast-2"
}

/*******************
*     RDS (MySQL) — environment(workspace)와 무관하게 공통인 값만
*******************/
variable "db_name" {
  description = "RDS에 생성할 기본 데이터베이스 이름"
  type        = string
  default     = "qket"
}

variable "db_username" {
  description = "RDS 마스터 계정 이름"
  type        = string
  default     = "admin"
}

/*******************
*     ElastiCache (Redis)
*******************/
variable "redis_engine_version" {
  description = "ElastiCache Redis 엔진 버전"
  type        = string
  default     = "7.1"
}

/*******************
*     외부 API 키 (ESO의 external-api-secrets로 동기화됨)
*******************/
# 사람이 직접 발급받은 값이라 기본값은 빈 문자열 — 실제 값은 TF_VAR_external_api_keys 환경변수나
# gitignore된 .tfvars로 넘김(절대 이 파일이나 git에 평문으로 안 남게). module.eso 쪽
# aws_secretsmanager_secret_version.external_api에 ignore_changes가 걸려있어서, 최초 1회만
# 값을 넣으면 그 뒤로 04_data를 몇 번을 재적용해도(이 변수를 매번 안 넘겨도) 안 바뀜.
/*******************
*     취소표 알림 (NOTI01_ALERT01)
*******************/
variable "cancel_alert_from_email" {
  description = "취소표 알림 메일 발신자 주소 — modules/ses.ses_domain(03_registry) 소속이어야 함"
  type        = string
  default     = "noreply@jun979.click"
}

variable "external_api_keys" {
  description = "토스/OAuth 등 외부 API 키 — 사람이 직접 발급받은 값"
  type = object({
    toss_secret_key      = string
    toss_client_key      = string
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
