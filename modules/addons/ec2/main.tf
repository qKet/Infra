# SSM Session Manager로만 접속하는 포트포워딩용 bastion.
# SSH(22번 포트)를 아예 안 열어도 됨 — SSM 에이전트가 AWS SSM 서비스로 나가는 아웃바운드 연결만 있으면 동작.
# RDS/Redis(private-data 서브넷)로 가는 다리 역할만 하는 용도라 최소 사양으로 둠.
# 보안그룹은 이 모듈이 만들지 않고 modules/security_group에서 받아옴(var.security_group_id).

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

resource "aws_iam_role" "ssm_bastion" {
  name = "${var.project_name}-ssm-bastion-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# SSM이 이 인스턴스를 관리(세션 연결 포함)할 수 있게 해주는 AWS 공식 정책
resource "aws_iam_role_policy_attachment" "ssm_bastion" {
  role       = aws_iam_role.ssm_bastion.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ssm_bastion" {
  name = "${var.project_name}-ssm-bastion-profile"
  role = aws_iam_role.ssm_bastion.name
}

resource "aws_instance" "ssm_bastion" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = var.bastion_instance_type
  subnet_id              = var.subnet_id
  iam_instance_profile   = aws_iam_instance_profile.ssm_bastion.name
  vpc_security_group_ids = [var.security_group_id]

  tags = {
    Name = "${var.project_name}-ssm-bastion"
  }
}
