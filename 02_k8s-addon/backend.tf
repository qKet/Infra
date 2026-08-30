# namespace/ArgoCD/Ingress Controller 등 "kubernetes/helm provider를 쓰는 K8s addon" 전용 state.
# 01_infrastructure(순수 AWS 리소스)와 분리 — 같은 state면 destroy 순서가 안 지켜져 Unauthorized가
# 남. apply는 01_infrastructure 다음, destroy는 그보다 먼저.
terraform {
  backend "s3" {
    bucket       = "team5-qket-tfstate-727646470302"
    key          = "k8s-addon/terraform.tfstate"
    region       = "ap-northeast-2"
    encrypt      = true
    use_lockfile = true
  }
}
