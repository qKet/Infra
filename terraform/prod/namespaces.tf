resource "kubernetes_namespace" "qket_prod" {
  metadata {
    name = "qket-prod"
    labels = {
      name = "qket-prod"
    }
  }
}
