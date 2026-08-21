# 2026-08-21: ESO 컨트롤러(Helm 릴리즈 + IRSA 역할 자체)는 02_k8s-addon의
# module.eso_controller로 옮김 — 이 모듈은 더 이상 그 역할을 만들지 않고, var.eso_role_name으로
# 넘어오는 그 공유 역할의 "이름"만 받아서 이 환경(release/prod) 자기 시크릿만큼 인라인 정책을
# 추가로 붙인다. (예전엔 여기서 aws_iam_role.eso를 직접 만들었는데, release/prod가 각자 이
# 모듈을 호출하면서 고정 이름 충돌(IAM Role already exists)이 났었음 — modules/addons/eso-controller/
# main.tf 참고.)
#
# RDS 자동 생성 시크릿 + connection + external_api, 딱 이 세 개만 읽기 허용 (최소 권한)
# — manage_db_redis_secrets=false면 앞의 둘(rds_master_user_secret_arn/connection)은 애초에
# 안 쓰여서 목록에서 뺌.
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
