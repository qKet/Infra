# ── ESO가 실제로 뭘 어디서 어디로 동기화할지 정의 (SecretStore + ExternalSecret) ──
# kubectl_manifest는 kubernetes_manifest와 달리 plan 시점에 클러스터를 라이브 조회하지 않아서
# CRD가 아직 없어도 apply 가능. yaml_body는 manifests/*.yaml.tpl + templatefile()로 분리 —
# YAML 문법 그대로 관리하고 변수만 ${...}로 주입.
#
# ESO 컨트롤러는 02_k8s-addon(다른 root)에 있어서 같은 root에 depends_on 대상이 없음 — root
# 순서(infrastructure→k8s-addon→data)가 apply 순서를 보장해줌.
resource "kubectl_manifest" "secret_store" {
  yaml_body = templatefile("${path.module}/manifests/secret-store.yaml.tpl", {
    namespace  = var.namespace
    aws_region = var.aws_region
  })
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

# 토스/OAuth 외부 API 키 — db-secrets/redis-secrets랑 같은 패턴이지만 원본이 사람이 직접
# 발급받은 값(ignore_changes로 보호됨). application.yml이 기대하는 이름과 1:1로 같아서
# 리스트 하나로 관리 — 새 provider 추가 시 이 리스트에 한 줄만 추가하면 됨.
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
