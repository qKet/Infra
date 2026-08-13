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

# Grafana가 AMP(Amazon Managed Prometheus)를 데이터소스로 직접 조회하기 위한 권한.
# 이게 없으면 Prometheus는 AMP에 데이터를 계속 잘 보내고 있어도, Grafana 화면에는
# 안 보임 — Grafana는 여전히 로컬(클러스터 안) Prometheus만 조회하는 상태이기 때문.
# QueryMetrics는 리소스 단위 스코핑 지원해서 workspace ARN으로 제한(CloudWatch와 달리).
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
# 원래 01_infrastructure에 module.irsa로 있었는데(2026-08-12), 여기로 옮김(2026-08-13) — 이 Role은
# monitoring 네임스페이스의 Prometheus ServiceAccount(바로 아래 helm_release가 만듦)에만 의미가 있어서,
# 그 ServiceAccount와 생명주기를 같이 하는 게 맞음. 02_k8s-addon이 destroy되면 SA도 이 Role도 같이
# 사라지고, apply되면 같이 다시 생김 — Grafana IRSA(위쪽)랑 동일한 이유·동일한 패턴.
# AMP 저장소 자체(aws_prometheus_workspace)는 03_registry에 남아 계속 살아있음 — 이 Role은 그
# 저장소에 "쓸 권한"만 담당하고, 저장소 자체를 만들지 않음.
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
