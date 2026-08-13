# IRSA(서비스어카운트별 IAM 역할)를 쓰려는 모든 애드온(ALB Controller 등)의 공통 전제조건.
# 클러스터당 OIDC 프로바이더는 딱 하나만 등록 가능해서 여기(EKS 모듈)에 두고, 필요한 모듈들이 output으로 가져다 씀.
data "tls_certificate" "this" {
  url = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "this" {
  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.this.certificates[0].sha1_fingerprint]
}
