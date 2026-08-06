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

  db_name  = var.db_name
  username = var.db_username
  # 비밀번호를 변수로 안 받고 RDS가 자동 생성 + Secrets Manager에 저장/관리하게 함
  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [var.security_group_id]
  publicly_accessible    = false

  multi_az = var.multi_az

  backup_retention_period = 7
  # release는 자주 destroy/재생성하는 샌드박스라 삭제할 때마다 최종 스냅샷 만들면
  # 이름 충돌로 삭제 자체가 막힘 — 그래서 스냅샷 안 만들고 그냥 삭제되게 함.
  # prod는 워크스페이스별 기본값(workload/variables.tf)에서 false로 안전망을 켬.
  skip_final_snapshot = var.skip_final_snapshot
  deletion_protection = var.deletion_protection
}
