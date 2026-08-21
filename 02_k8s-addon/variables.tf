variable "aws_region" {
  description = "EKS get-token 호출 시 사용할 AWS 리전"
  type        = string
  default     = "ap-northeast-2"
}

variable "project_name" {
  description = "리소스 이름 접두사 — module.alb_controller가 IAM Role 이름 짓는 데 씀"
  type        = string
  default     = "team5-qket"
}

variable "admin_allowed_cidrs" {
  description = "grafana/argocd/dev(release) 공유 ALB에 접속 가능한 팀원 IP 허용목록 — 팀원 IP가 추가되면 default 리스트에 한 줄씩 추가하면 됨"
  type        = list(string)
  default = [
    "222.111.119.115/32", # 윤준
    "121.138.193.90/32",  # 채영
    "162.120.184.59/32",  # 진호
    "123.214.77.21/32"    # 우진
    "58.29.99.44"         # 준혁
  ]
}
