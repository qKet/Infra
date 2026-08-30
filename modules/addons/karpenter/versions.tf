# kubectl_manifest(EC2NodeClass/NodePool)를 쓰는 하위 모듈이라 명시적으로 선언 필요 —
# 없으면 존재하지 않는 기본 source로 잘못 추측함. 02_k8s-addon/providers.tf와 동일 source여야
# 루트 provider 설정을 물려받음.
terraform {
  required_providers {
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
    }
  }
}
