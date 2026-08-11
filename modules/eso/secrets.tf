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
