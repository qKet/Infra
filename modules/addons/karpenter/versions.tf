# kubectl_manifest(EC2NodeClass/NodePool)를 쓰는 하위 모듈이라 명시적으로 선언 필요 —
# 이게 없으면 terraform이 기본값 registry.terraform.io/hashicorp/kubectl(존재하지 않음)로
# 잘못 추측해서 "Failed to query available provider packages" 에러가 남(2026-08-20 실측).
# 02_k8s-addon/providers.tf가 쓰는 gavinbunney/kubectl과 반드시 동일한 source여야
# 루트의 provider "kubectl" 설정을 그대로 물려받음.
terraform {
  required_providers {
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
    }
  }
}
