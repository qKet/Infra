# Loki가 실제 로그 데이터(청크)와 색인을 저장하는 곳. Loki 자체는 상태가 없는(stateless)
# 앱이라 파드가 재시작/재생성돼도 이 S3 버킷만 살아있으면 과거 로그가 안 없어짐 —
# RDS/Redis처럼 "저장은 관리형 서비스에, 얹혀서 도는 앱은 클러스터 안에" 패턴을 로그에도 그대로 적용.
resource "aws_s3_bucket" "loki_logs" {
  bucket        = "${var.project_name}-loki-logs"
  force_destroy = var.force_destroy
}

resource "aws_s3_bucket_public_access_block" "loki_logs" {
  bucket = aws_s3_bucket.loki_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# 로그가 쌓이기만 하고 안 지워지면 비용이 계속 늘어남 — 90일 지난 로그는 자동 삭제.
# (필요하면 나중에 이 값만 늘리면 됨, 팀 판단에 따라 조정 가능)
resource "aws_s3_bucket_lifecycle_configuration" "loki_logs" {
  bucket = aws_s3_bucket.loki_logs.id

  rule {
    id     = "expire-old-logs"
    status = "Enabled"

    filter {}

    expiration {
      days = 90
    }
  }
}
