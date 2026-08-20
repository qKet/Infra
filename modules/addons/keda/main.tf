# KEDA(Kubernetes Event-Driven Autoscaling)
# 지금 당장은 CPU/Memory 로 스케일링 하지만 추후에 대기열에 사람이 몰릴 시 redis를 보고 판단해서 pod를 늘려야 할 상황이 발생할수 있어 KEDA로 채택함
#
# ScaledObject(실제 스케일 대상/규칙)는 Terraform이 아니라 CD 레포(Helm)에 있음 —
# Deployment를 스케일하는 "애플리케이션 설정"이라 그 Deployment랑 같이 관리되는 게
# 맞다고 판단(Terraform은 클러스터에 KEDA "엔진"을 설치하는 것까지만 담당).
resource "helm_release" "keda" {
  name             = "keda"
  repository       = "https://kedacore.github.io/charts"
  chart            = "keda"
  namespace        = "keda"
  create_namespace = true
  version          = "~> 2.20"
}
