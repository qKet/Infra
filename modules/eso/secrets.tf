# RDS 자동 생성 시크릿(username/password)은 그대로 두고 안 건드림.
# 여기선 "진짜 비밀은 아니지만 접속 정보"인 DB_HOST/REDIS_HOST만 담는 별도 시크릿을 새로 만듦.
# 이렇게 나누면 RDS가 관리하는 시크릿의 모양(로테이션 등)에 우리가 손대는 일이 없음.
resource "aws_secretsmanager_secret" "connection" {
  name = "${var.project_name}-connection-${var.environment}"

  # release는 자주 destroy/재생성하는 샌드박스라, 기본 대기기간(최대 30일) 뒤에 지워지면
  # 같은 이름으로 재생성할 때 "삭제 예정이라 못 만든다"는 충돌이 남 — 그래서 0(바로 삭제)으로 둠.
  # prod는 호출하는 쪽(04_data의 env_config_map)에서 7 이상으로 넘겨서 실수 삭제를 방지함.
  recovery_window_in_days = var.secret_recovery_window_days
}

resource "aws_secretsmanager_secret_version" "connection" {
  secret_id = aws_secretsmanager_secret.connection.id
  secret_string = jsonencode({
    DB_HOST    = var.rds_endpoint
    REDIS_HOST = var.redis_endpoint
  })
}

# 2026-08-11: 토스/OAuth 외부 API 키 — connection과 달리 사람이 직접 발급받은 값이라 위와 분리함
# (같은 시크릿에 합치면, 04_data를 매일 아침 재적용할 때 TF_VAR를 그때그때 안 넘기면 이 값이
# 빈 문자열로 조용히 덮어써지는 위험이 있음 — connection은 Terraform이 매번 자동 재계산하는 게
# 의도된 동작이라 그 위험이 없지만, 이건 반대로 "재적용 시 절대 안 바뀌어야" 함).
# lifecycle.ignore_changes로 secret_string을 보호 — 최초 1회 값을 넣은 뒤로는 04_data를 몇 번을
# 재적용해도 이 값이 안 바뀜. 값을 실제로 갱신해야 할 땐 콘솔/CLI로 직접 UpdateSecret 하거나
# `terraform apply -replace=module.eso.aws_secretsmanager_secret_version.external_api`로 명시적으로.
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
  })

  lifecycle {
    ignore_changes = [secret_string]
  }
}
