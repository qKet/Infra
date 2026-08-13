# VPC/서브넷/보안그룹 전용 state — 전부 AWS 기준 무료 리소스라 비용과 무관하게 영구 보존.
# 03_registry(ECR/OIDC)와 같은 성격("공유·환경 구분 없음·절대 안 지움")이라 같은 패턴을 그대로 씀 —
# workspace 구분 없이 독립적으로(주로 최초 1회만) 적용.
#
# 2026-08-13: 01_infrastructure에서 분리해서 신설. 예전엔 01_infrastructure를 매일 밤 destroy할 때
# 실제로는 -target으로 EKS/EC2/NAT/security_group만 골라 지우고 VPC/서브넷은 항상 살려뒀는데
# (사람이 target 목록을 매번 정확히 기억해야 하는 방식), 그 경계를 root 자체로 구조화함 —
# 이제 01_infrastructure는 통째로 destroy해도 안전(VPC/서브넷은 아예 이 root에 없음).
terraform {
  backend "s3" {
    bucket       = "team5-qket-tfstate-727646470302"
    key          = "network/terraform.tfstate"
    region       = "ap-northeast-2"
    encrypt      = true
    use_lockfile = true
  }
}
