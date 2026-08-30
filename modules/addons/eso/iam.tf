# ESO 컨트롤러(Helm/IRSA)는 02_k8s-addon의 module.eso_controller가 담당 — 이 모듈은 그 공유
# 역할 이름만 받아서 이 환경(release/prod) 자기 시크릿만큼 인라인 정책을 추가로 붙인다.
#
# RDS 자동 생성 시크릿 + connection + external_api, 딱 이 세 개만 읽기 허용(최소 권한) —
# manage_db_redis_secrets=false면 앞의 둘은 목록에서 뺌.
data "aws_iam_policy_document" "eso_secrets_read" {
  statement {
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]
    resources = concat(
      var.manage_db_redis_secrets ? [
        var.rds_master_user_secret_arn,
        aws_secretsmanager_secret.connection[0].arn,
      ] : [],
      [aws_secretsmanager_secret.external_api.arn],
      var.extra_secret_arns,
    )
  }
}

resource "aws_iam_role_policy" "eso_secrets_read" {
  name   = "${var.project_name}-eso-secrets-read-${var.environment}"
  role   = var.eso_role_name
  policy = data.aws_iam_policy_document.eso_secrets_read.json
}
