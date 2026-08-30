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
*     외부 API 키 (ESO의 external-api-secrets로 동기화됨)
*******************/
# release는 RDS/ElastiCache를 안 씀(dev-datastore로 대체) — db_name/db_username/
# redis_engine_version은 prod 전용(04_data/prod/variables.tf 참고).
# 기본값은 빈 문자열 — 실제 값은 TF_VAR_external_api_keys나 gitignore된 .tfvars로 넘김.
/*******************
*     예매 오픈 알림
*******************/
variable "open_alert_from_email" {
  description = "예매 오픈 알림 메일 발신자 주소 — 03_registry/ses.tf가 인증해둔 도메인 소속이어야 함"
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
    openai_api_key = string
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
    openai_api_key = ""
  }
}
