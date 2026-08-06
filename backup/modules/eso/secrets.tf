# RDS 자동 생성 시크릿(username/password)은 그대로 두고 안 건드림.
# 여기선 "진짜 비밀은 아니지만 접속 정보"인 DB_HOST/REDIS_HOST만 담는 별도 시크릿을 새로 만듦.
# 이렇게 나누면 RDS가 관리하는 시크릿의 모양(로테이션 등)에 우리가 손대는 일이 없음.
resource "aws_secretsmanager_secret" "connection" {
  name = "${var.project_name}-connection-${var.environment}"

  # dev는 자주 destroy/재생성하는 샌드박스라, 기본 대기기간(최대 30일) 뒤에 지워지면
  # 같은 이름으로 재생성할 때 "삭제 예정이라 못 만든다"는 충돌이 남 — 그래서 바로 지워지게 함.
  # prod 만들 때는 실수 삭제 대비해서 recovery_window_in_days를 7 이상으로 켤 것.
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "connection" {
  secret_id = aws_secretsmanager_secret.connection.id
  secret_string = jsonencode({
    DB_HOST    = var.rds_endpoint
    REDIS_HOST = var.redis_endpoint
  })
}
