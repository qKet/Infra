# archive_file로 lambda-src/를 zip으로 패키징 — CI가 없는 지금 임시 방편.
# 나중에 qket-email-verification-lambda 레포 + CI가 생기면 이 방식 대신 S3 업로드 경로
# (s3_bucket/s3_key)로 바꾸는 게 맞음 — backend/frontend가 로컬 산출물 대신 CI 산출물만
# 쓰는 것과 같은 이유(재현성 — 다른 팀원 컴퓨터에서 이 zip이 없어도 항상 같은 결과가 나와야 함).
terraform {
  required_providers {
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}
