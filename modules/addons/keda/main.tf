# KEDA(Kubernetes Event-Driven Autoscaling) — HPA를 대체하는 게 아니라, HPA가 볼 수 있는 지표를
# CPU/메모리 너머로 넓혀주는 컨트롤러(내부적으로 HPA를 자동 생성해서 씀). 2026-08-13:
# 지금 당장은 backend를 CPU 기준으로 스케일하지만(ScaledObject의 cpu trigger — HPA랑 동일한 효과),
# 나중에 대기열(Redis) 길이 기준으로 스케일하고 싶어질 때 트리거만 추가하면 되게 미리 깔아둠 —
# HPA로 시작했다가 나중에 KEDA로 갈아타는 것보다, 처음부터 KEDA 하나로 통일하는 게 나음.
#
# ScaledObject(실제 스케일 대상/규칙)는 여기(Terraform)가 아니라 CD 레포(Helm)에 있음 —
# qket-backend Deployment를 스케일하는 "애플리케이션 설정"이라 그 Deployment랑 같이 관리되는 게
# 맞다고 판단(Terraform은 클러스터에 KEDA "엔진"을 설치하는 것까지만 담당).
resource "helm_release" "keda" {
  name             = "keda"
  repository       = "https://kedacore.github.io/charts"
  chart            = "keda"
  namespace        = "keda"
  create_namespace = true
  version          = "~> 2.20"
}
