# Amazon Managed Prometheus(AMP) — 02_k8s-addon의 Prometheus가 수집한 지표를 EKS 클러스터
# 수명과 무관하게 영구 저장하는 곳. release/prod가 공유하는 단일 workspace라 04_data(workspace별로
# 나뉘어 release/prod 두 번 apply되는 레이어)가 아니라 여기(단일 apply)에 둠 — 모니터링은
# RDS/Redis와 달리 환경별로 쪼갤 이유가 없음.
#
# 일반 EBS(PVC) 방식도 검토했으나 기각 — EKS를 destroy하면 PVC도 같이 삭제되고
# StorageClass의 ReclaimPolicy가 Delete라 EBS 볼륨도 함께 지워짐(Pod 재시작에는 강하지만
# "클러스터 통째로 재생성"에는 무력함, 이게 바로 지금 풀려는 문제). AMP는 EKS와 완전히
# 분리된 관리형 서비스라 클러스터를 몇 번을 destroy/재생성해도 데이터가 그대로 남음.
#
# 02_k8s-addon보다 먼저 apply되는 레이어에 두는 이유: module.monitoring(02_k8s-addon)이
# Prometheus를 설치하는 시점에 이 workspace의 remote_write 주소와 IRSA Role ARN을
# 곧바로 Helm values에 넣기 위해서. 순서가 반대(04_data처럼 나중에 apply)였으면 이미
# 설치된 Prometheus 설정에 나중에 patch를 얹어야 하는 번거로움이 생김.
resource "aws_prometheus_workspace" "this" {
  alias = "${var.project_name}-amp"
}

data "aws_iam_policy_document" "amp_write" {
  statement {
    effect    = "Allow"
    actions   = ["aps:RemoteWrite", "aps:GetSeries", "aps:GetLabels", "aps:GetMetricMetadata"]
    resources = [aws_prometheus_workspace.this.arn]
  }
}

# Prometheus가 이 IRSA Role로 뜨면 AMP에 원격 저장 가능해짐. ServiceAccount는 여기서 안 만듦 —
# module.monitoring(02_k8s-addon)의 helm_release가 자체적으로 만드는 SA
# (monitoring-kube-prometheus-prometheus)에 annotation으로 이 Role ARN만 넘겨주면 됨
# (modules/irsa 설명 참고 — Helm이 SA를 직접 만드는 애드온 케이스. modules/monitoring의
# Grafana IRSA와 같은 목적, 대상만 Prometheus로 다름).
module "irsa" {
  source = "../modules/addons/irsa"

  project_name      = var.project_name
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url

  roles = {
    prometheus-amp = {
      namespace       = "monitoring"
      service_account = "monitoring-kube-prometheus-prometheus"
      policy_json     = data.aws_iam_policy_document.amp_write.json
    }
  }
}
