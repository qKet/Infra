# ── ESO가 실제로 뭘 어디서 어디로 동기화할지 정의 (SecretStore + ExternalSecret) ──
# kubectl_manifest는 kubernetes_manifest와 달리 plan 시점에 클러스터를 라이브 조회하지 않아서,
# 클러스터 생성 + helm_release(ESO 설치) + 이 CRD 리소스들을 전부 한 번의 apply로 처리할 수 있음.
#
# 2026-08-21: yaml_body를 HCL 객체(yamlencode)로 직접 쓰지 않고 manifests/*.yaml.tpl 파일 +
# templatefile()로 분리함 — 매니페스트가 늘어날수록 "이 HCL 키가 실제로 어떤 YAML 필드가 되는지"
# 눈으로 매핑해야 하는 부담이 커져서, 진짜 YAML 문법 그대로 파일로 관리하고 변수만 ${...}로 주입.
# 리팩터링 전후로 terraform plan에 diff가 없는지(렌더링 결과가 기존 yamlencode와 동일한지) 확인함.

resource "kubectl_manifest" "secret_store" {
  yaml_body = templatefile("${path.module}/manifests/secret-store.yaml.tpl", {
    namespace  = var.namespace
    aws_region = var.aws_region
  })

  depends_on = [helm_release.external_secrets]
}

# manage_db_redis_secrets=false면 이 리소스 자체를 안 만듦 — release처럼 DB 비밀번호가 절대 안
# 바뀌는 환경은 ESO의 로테이션 동기화가 필요 없어서, db-secrets를 이 모듈 밖에서 plain
# kubernetes_secret으로 직접 만듦(호출부 main.tf 참고).
resource "kubectl_manifest" "external_secret_db" {
  count = var.manage_db_redis_secrets ? 1 : 0

  yaml_body = templatefile("${path.module}/manifests/external-secret-db.yaml.tpl", {
    namespace      = var.namespace
    connection_arn = aws_secretsmanager_secret.connection[0].arn
    rds_secret_arn = var.rds_master_user_secret_arn
  })

  depends_on = [kubectl_manifest.secret_store]
}

# 2026-08-11: 토스/OAuth 외부 API 키 — db-secrets/redis-secrets랑 같은 패턴이지만 원본이
# aws_secretsmanager_secret.external_api(사람이 직접 발급받은 값, ignore_changes로 보호됨).
# 키 목록을 local로 뽑은 이유: application.yml이 기대하는 이름(TOSS_SECRET_KEY,
# GOOGLE_CLIENT_ID 등)과 Secrets Manager 쪽 JSON 키가 1:1로 같아서, 하나씩 나열하는 대신
# 리스트 하나로 관리 — 나중에 새 provider 추가할 때 이 리스트에 한 줄만 추가하면 됨
# (템플릿 쪽 %{ for }도 자동으로 그만큼 늘어남).
locals {
  external_api_keys_list = [
    "TOSS_SECRET_KEY",
    "GOOGLE_CLIENT_ID", "GOOGLE_CLIENT_SECRET",
    "KAKAO_CLIENT_ID", "KAKAO_CLIENT_SECRET",
    "NAVER_CLIENT_ID", "NAVER_CLIENT_SECRET",
    "OPENAI_API_KEY",
  ]
}

resource "kubectl_manifest" "external_secret_external_api" {
  yaml_body = templatefile("${path.module}/manifests/external-secret-external-api.yaml.tpl", {
    namespace        = var.namespace
    external_api_arn = aws_secretsmanager_secret.external_api.arn
    keys             = local.external_api_keys_list
  })

  depends_on = [kubectl_manifest.secret_store]
}

resource "kubectl_manifest" "external_secret_redis" {
  count = var.manage_db_redis_secrets ? 1 : 0

  yaml_body = templatefile("${path.module}/manifests/external-secret-redis.yaml.tpl", {
    namespace      = var.namespace
    connection_arn = aws_secretsmanager_secret.connection[0].arn
  })

  depends_on = [kubectl_manifest.secret_store]
}
