# RDS는 private-data 서브넷에만 배치 (2개 AZ 서브넷 필요 — DB subnet group 자체는 항상 2개 이상 AZ 요구.
# 단 multi_az = false면 실제 인스턴스는 그중 한 AZ에만 뜸)
# 보안그룹은 이 모듈이 만들지 않고 modules/security_group에서 받아옴(var.security_group_id).
resource "aws_db_subnet_group" "this" {
  name       = "${var.project_name}-rds-subnet-group-${var.environment}"
  subnet_ids = var.private_data_subnet_ids

  tags = {
    Name = "${var.project_name}-rds-subnet-group-${var.environment}"
  }
}

resource "aws_db_instance" "this" {
  identifier     = "${var.project_name}-mysql-${var.environment}"
  engine         = "mysql"
  engine_version = "8.0"

  instance_class        = var.db_instance_class
  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = var.db_max_allocated_storage
  storage_type          = "gp3"
  # 기존 미암호화 인스턴스가 있는 상태에서 이 값을 켜면 destroy+재생성이 발생함 —
  # variables.tf의 storage_encrypted 설명 참고. 반드시 스냅샷 복원 절차로 전환할 것.
  storage_encrypted = var.storage_encrypted

  db_name  = var.db_name
  username = var.db_username
  # 비밀번호를 변수로 안 받고 RDS가 자동 생성 + Secrets Manager에 저장/관리하게 함
  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [var.security_group_id]
  publicly_accessible    = false

  multi_az = var.multi_az

  # 기본값(false)이면 인스턴스 클래스/Multi-AZ 같은 변경이 다음 유지보수 윈도우까지 미뤄져서
  # "apply는 성공했는데 실제로는 며칠 뒤에나 반영되는" 혼란이 생김 — release/prod 둘 다 그때그때
  # 확인하며 바꾸는 프로젝트 특성상 즉시 반영이 맞다고 판단(2026-08-24, Multi-AZ 끄기 작업 계기로 추가).
  # 참고: engine_version처럼 원래도 즉시 적용되는 값도 있고, storage_type처럼 이 값과 무관하게
  # 항상 지연 적용되는 값도 있음 — RDS 콘솔에서 "보류 중인 유지관리"로 확인 가능.
  apply_immediately = true

  backup_retention_period = 7
  # release는 자주 destroy/재생성하는 샌드박스라 삭제할 때마다 최종 스냅샷 만들면
  # 이름 충돌로 삭제 자체가 막힘 — 그래서 스냅샷 안 만들고 그냥 삭제되게 함.
  # prod는 워크스페이스별 기본값(04_data/main.tf의 env_config_map)에서 false로 안전망을 켬.
  skip_final_snapshot = var.skip_final_snapshot
  deletion_protection = var.deletion_protection
}
