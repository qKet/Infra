# RDS 자동 생성 시크릿(username/password)은 그대로 두고 안 건드림.
# 여기선 "진짜 비밀은 아니지만 접속 정보"인 DB_HOST/REDIS_HOST만 담는 별도 시크릿을 새로 만듦.
# 이렇게 나누면 RDS가 관리하는 시크릿의 모양(로테이션 등)에 우리가 손대는 일이 없음.
#
# manage_db_redis_secrets=false면 이 시크릿 자체를 안 만듦 — DB_HOST/REDIS_HOST가 하드코딩 가능한
# 고정값인 환경(release)은 CD 쪽에서 직접 하드코딩하므로 이 시크릿이 필요 없음.
resource "aws_secretsmanager_secret" "connection" {
  count = var.manage_db_redis_secrets ? 1 : 0

  name = "${var.project_name}-connection-${var.environment}"

  # release는 자주 재생성해서 0(바로 삭제)으로 둠 — 안 그러면 재생성 시 이름 충돌.
  # prod는 호출하는 쪽에서 7 이상으로 넘겨서 실수 삭제 방지.
  recovery_window_in_days = var.secret_recovery_window_days
}

resource "aws_secretsmanager_secret_version" "connection" {
  count = var.manage_db_redis_secrets ? 1 : 0

  secret_id = aws_secretsmanager_secret.connection[0].id
  secret_string = jsonencode({
    DB_HOST    = var.rds_endpoint
    REDIS_HOST = var.redis_endpoint
  })
}

# 토스/OAuth 외부 API 키 — connection과 달리 사람이 직접 발급받은 값이라 분리함(재적용 시
# TF_VAR 누락으로 빈 문자열에 덮어써지는 위험 방지). ignore_changes로 secret_string 보호 —
# 값 갱신은 콘솔/CLI로 직접 UpdateSecret 하거나 -replace로 명시적으로.
resource "aws_secretsmanager_secret" "external_api" {
  name                    = "${var.project_name}-external-api-${var.environment}"
  recovery_window_in_days = var.secret_recovery_window_days
}

resource "aws_secretsmanager_secret_version" "external_api" {
  secret_id = aws_secretsmanager_secret.external_api.id
  secret_string = jsonencode({
    TOSS_SECRET_KEY      = var.external_api_keys.toss_secret_key
    TOSS_CLIENT_KEY      = var.external_api_keys.toss_client_key
    GOOGLE_CLIENT_ID     = var.external_api_keys.google_client_id
    GOOGLE_CLIENT_SECRET = var.external_api_keys.google_client_secret
    KAKAO_CLIENT_ID      = var.external_api_keys.kakao_client_id
    KAKAO_CLIENT_SECRET  = var.external_api_keys.kakao_client_secret
    NAVER_CLIENT_ID      = var.external_api_keys.naver_client_id
    NAVER_CLIENT_SECRET  = var.external_api_keys.naver_client_secret
    OPENAI_API_KEY = var.external_api_keys.openai_api_key
  })

  lifecycle {
    ignore_changes = [secret_string]
  }
}
