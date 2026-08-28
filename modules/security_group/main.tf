# 보안그룹 생성 모듈
resource "aws_security_group" "this" {
  for_each = var.security_groups

  name_prefix = "${var.project_name}-${each.key}-"
  vpc_id      = var.vpc_id

  dynamic "ingress" {
    for_each = each.value.ingress
    content {
      description     = ingress.value.description
      from_port       = ingress.value.from_port
      to_port         = ingress.value.to_port
      protocol        = ingress.value.protocol
      security_groups = ingress.value.security_groups
      cidr_blocks     = ingress.value.cidr_blocks
    }
  }

  # 모든 그룹에 아웃바운드 전체 허용을 동일하게 둠
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-${each.key}-sg"
  }
}
