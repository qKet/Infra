# S3를 private로 막아둔 대신, CloudFront가 OAC(Origin Access Control)로 대신 읽어서 서빙
resource "aws_cloudfront_origin_access_control" "posters" {
  name                              = "${var.project_name}-posters-${var.environment}-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "posters" {
  enabled             = true
  comment             = "${var.project_name} 포스터 이미지 CDN (${var.environment})"
  default_root_object = ""
  # 아시아(한국 포함)
  price_class = "PriceClass_200"

  origin {
    domain_name              = aws_s3_bucket.posters.bucket_regional_domain_name
    origin_id                = "s3-posters"
    origin_access_control_id = aws_cloudfront_origin_access_control.posters.id
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "s3-posters"
    viewer_protocol_policy = "redirect-to-https"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  # 커스텀 도메인 안 씀 — 기본 *.cloudfront.net 도메인 그대로 사용 (dev)
  viewer_certificate {
    cloudfront_default_certificate = true
  }
}
