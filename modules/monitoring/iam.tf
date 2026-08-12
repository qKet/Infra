# ── Grafana용 IRSA 역할 ──
# CloudWatch를 데이터소스로 붙여서 RDS/Redis/ALB 지표를 같은 화면에서 보기 위한 용도
# (wiki decisions/2026-08-11-monitoring-stack-design 참고). Prometheus/node-exporter/
# kube-state-metrics 자체는 클러스터 안 지표만 긁어서 AWS 권한이 필요 없고, Grafana만 필요함.
data "aws_iam_policy_document" "grafana_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(var.oidc_provider_url, "https://", "")}:sub"
      values   = ["system:serviceaccount:monitoring:grafana"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(var.oidc_provider_url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "grafana" {
  name               = "${var.project_name}-grafana-role"
  assume_role_policy = data.aws_iam_policy_document.grafana_assume.json
}

# AWS가 CloudWatch 데이터소스 플러그인용으로 공식 문서에서 권장하는 최소 권한 그대로 씀
# (https://grafana.com/docs/grafana/latest/datasources/aws-cloudwatch/aws-authentication/).
# CloudWatch GetMetricData/ListMetrics 등은 리소스 단위 ARN 스코핑을 지원 안 해서 resources="*"
# 가 불가피함 — 전부 조회(Describe/List/Get)만 가능한 읽기 전용 액션이라 실질적 위험은 낮음.
data "aws_iam_policy_document" "grafana_cloudwatch_read" {
  statement {
    effect = "Allow"
    actions = [
      "cloudwatch:DescribeAlarmsForMetric",
      "cloudwatch:DescribeAlarmHistory",
      "cloudwatch:DescribeAlarms",
      "cloudwatch:ListMetrics",
      "cloudwatch:GetMetricData",
      "cloudwatch:GetInsightRuleReport",
      "ec2:DescribeTags",
      "ec2:DescribeInstances",
      "ec2:DescribeRegions",
      "tag:GetResources",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "grafana_cloudwatch_read" {
  name   = "${var.project_name}-grafana-cloudwatch-read"
  role   = aws_iam_role.grafana.id
  policy = data.aws_iam_policy_document.grafana_cloudwatch_read.json
}
