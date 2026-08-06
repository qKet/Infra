# 범용 다중 보안그룹 팩토리 — bastion(platform)과 rds/redis(workload)가
# 둘 다 이 모듈을 각자 호출해서 필요한 보안그룹만 만든다.
# var.security_groups의 key가 보안그룹 이름 suffix, value가 규칙 정의.
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

  # 모든 그룹에 아웃바운드 전체 허용을 동일하게 둠 (원래 bastion만 그랬던 것을 rds/redis에도 확장).
  # inline egress 블록을 아예 안 쓰면 Terraform이 AWS 기본 egress 규칙까지 지워버려서
  # (aws_security_group의 잘 알려진 함정) 명시적으로 항상 선언해둠.
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
