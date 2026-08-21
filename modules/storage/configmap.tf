# S3_BUCKET/CLOUDFRONT_DOMAIN은 이 모듈이 만든 리소스에서 나오는 값이라 Terraform이 직접 관리.
# 별도 ConfigMap으로 분리해서 소유권 충돌 방지.
resource "kubernetes_config_map" "storage" {
  metadata {
    name      = "storage-config"
    namespace = var.namespace
  }

  data = {
    S3_BUCKET         = aws_s3_bucket.posters.bucket
    CLOUDFRONT_DOMAIN = aws_cloudfront_distribution.posters.domain_name
  }
}
