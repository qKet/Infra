# ── Grafana용 IRSA 역할 ──
# CloudWatch를 데이터소스로 붙여서 RDS/Redis/ALB 지표를 같은 화면에서 보기 위한 용도.
# Prometheus/node-exporter 등은 클러스터 안 지표만 긁어서 AWS 권한이 필요 없음.
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

# CloudWatch 데이터소스 플러그인 공식 권장 최소 권한. GetMetricData/ListMetrics 등은 리소스
# 단위 스코핑을 지원 안 해서 resources="*" 불가피 — 전부 읽기 전용 액션이라 위험은 낮음.
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

# Grafana가 AMP를 데이터소스로 직접 조회하기 위한 권한(remote_write와는 별개).
# QueryMetrics는 리소스 단위 스코핑 지원해서 workspace ARN으로 제한.
data "aws_iam_policy_document" "grafana_amp_query" {
  statement {
    effect = "Allow"
    actions = [
      "aps:QueryMetrics",
      "aps:GetSeries",
      "aps:GetLabels",
      "aps:GetMetricMetadata",
    ]
    resources = [var.amp_workspace_arn]
  }
}

resource "aws_iam_role_policy" "grafana_amp_query" {
  name   = "${var.project_name}-grafana-amp-query"
  role   = aws_iam_role.grafana.id
  policy = data.aws_iam_policy_document.grafana_amp_query.json
}

# ── Prometheus용 IRSA 역할 (AMP remote_write) ──
# Prometheus ServiceAccount(helm_release.monitoring)와 생명주기를 같이 함 — Grafana IRSA와
# 동일 패턴. AMP 저장소 자체(aws_prometheus_workspace)는 03_registry에 남아 계속 살아있고,
# 이 Role은 거기 "쓸 권한"만 담당.
data "aws_iam_policy_document" "prometheus_assume" {
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
      values   = ["system:serviceaccount:monitoring:monitoring-kube-prometheus-prometheus"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(var.oidc_provider_url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "prometheus" {
  name               = "${var.project_name}-prometheus-amp-role"
  assume_role_policy = data.aws_iam_policy_document.prometheus_assume.json
}

data "aws_iam_policy_document" "prometheus_amp_write" {
  statement {
    effect    = "Allow"
    actions   = ["aps:RemoteWrite", "aps:GetSeries", "aps:GetLabels", "aps:GetMetricMetadata"]
    resources = [var.amp_workspace_arn]
  }
}

resource "aws_iam_role_policy" "prometheus_amp_write" {
  name   = "${var.project_name}-prometheus-amp-policy"
  role   = aws_iam_role.prometheus.id
  policy = data.aws_iam_policy_document.prometheus_amp_write.json
}
