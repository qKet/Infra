# 기존 k8s/namespace_qKet.yaml 을 대체 — 이제 이 파일로 네임스페이스를 수동/CI로 apply할 필요 없음.
resource "kubernetes_namespace" "qket_release" {
  metadata {
    name = "qket-release"
    labels = {
      name = "qket-release"
    }
  }
}
