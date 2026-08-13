# namespace/ArgoCD/Ingress Controller 등 "kubernetes/helm provider를 쓰는 K8s addon" 전용 state.
# 01_infrastructure(순수 AWS API 리소스)와 분리한 이유는 CLAUDE_LLM_WIKI의
# troubleshooting/eks-destroy-layer-separation 문서 참고 — 요약하면, kubernetes/helm provider가
# 인증에 쓰는 EKS Access Entry가 이 리소스들과 같은 state에 있으면 destroy 순서가 안 지켜져서
# Unauthorized가 나는 문제가 있었음. apply는 01_infrastructure 다음, destroy는 01_infrastructure보다 먼저.
terraform {
  backend "s3" {
    bucket       = "team5-qket-tfstate-727646470302"
    key          = "k8s-addon/terraform.tfstate"
    region       = "ap-northeast-2"
    encrypt      = true
    use_lockfile = true
  }
}
