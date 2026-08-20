# vpc/subnet/security_group은 2026-08-13에 00_network(영구 root)로 분리됨 — 전부 AWS 요금이
# 안 붙는 무료 리소스라 매일 밤 destroy할 이유가 없었고(오히려 밤에 -refresh-only가 깨지는
# 원인만 됐음), 이 root(01_infrastructure)는 이제 순수하게 "비용이 나가는 것"만 남아서
# -target 없이 통째로 destroy해도 안전함. 값은 data.terraform_remote_state.network로 읽어옴.

# ── NAT Gateway / 라우팅 — vpc·subnet 둘 다의 값이 필요해서 root에 둠 ──
# (NAT Gateway 자체가 매일 밤 destroy 대상이라 라우팅 테이블도 여기 같이 둠 — 00_network에
#  두면 매일 바뀌는 NAT Gateway ID를 참조하느라 오히려 그 영구 root까지 매일 재적용해야
#  하는 번거로움이 생김. modules/vpc↔modules/subnet 사이에 서로의 출력을 주고받는 순환
#  참조를 만들지 않는 게 핵심이라는 원래 이유는 여전히 유효 — 자세한 내용은
#  CLAUDE_LLM_WIKI wiki/troubleshooting/terraform-circular-module-dependency.md 참고)

# NAT Gateway용 고정 IP — AZ당 1개
resource "aws_eip" "nat" {
  count  = length(var.azs)
  domain = "vpc"

  tags = {
    Name = "${var.project_name}-nat-eip-${var.azs[count.index]}"
  }
}

# NAT Gateway — AZ당 1개, 해당 AZ의 퍼블릭 서브넷에 배치
resource "aws_nat_gateway" "this" {
  count         = length(var.azs)
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = data.terraform_remote_state.network.outputs.public_subnet_ids[count.index]

  tags = {
    Name = "${var.project_name}-nat-${var.azs[count.index]}"
  }
}

# 퍼블릭 라우팅 테이블 — 0.0.0.0/0 트래픽을 인터넷 게이트웨이로
resource "aws_route_table" "public" {
  vpc_id = data.terraform_remote_state.network.outputs.vpc_id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = data.terraform_remote_state.network.outputs.igw_id
  }

  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  count          = length(data.terraform_remote_state.network.outputs.public_subnet_ids)
  subnet_id      = data.terraform_remote_state.network.outputs.public_subnet_ids[count.index]
  route_table_id = aws_route_table.public.id
}

# 프라이빗(일반 워크로드) 라우팅 테이블 — AZ당 1개, 자기 AZ의 NAT Gateway로만 나가게 함
# (cross-AZ로 NAT 안 타게 해서 트래픽 비용 절감 + 한쪽 AZ의 NAT 장애가 다른 AZ에 영향 안 주게)
resource "aws_route_table" "private" {
  count  = length(var.azs)
  vpc_id = data.terraform_remote_state.network.outputs.vpc_id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this[count.index].id
  }

  tags = {
    Name = "${var.project_name}-private-rt-${var.azs[count.index]}"
  }
}

resource "aws_route_table_association" "private" {
  count          = length(var.azs)
  subnet_id      = data.terraform_remote_state.network.outputs.private_general_subnet_ids[count.index]
  route_table_id = aws_route_table.private[count.index].id
}

# 프라이빗-데이터(DB/Redis) 라우팅 테이블 — 일반 프라이빗과 분리해서 별도 관리.
# 앞으로도 인터넷 라우트를 절대 추가하지 않아서 DB/Redis 서브넷은 계속 외부와 완전히 격리되게 유지.
resource "aws_route_table" "private_data" {
  vpc_id = data.terraform_remote_state.network.outputs.vpc_id

  tags = {
    Name = "${var.project_name}-private-data-rt"
  }
}

resource "aws_route_table_association" "private_data" {
  count          = length(var.azs)
  subnet_id      = data.terraform_remote_state.network.outputs.private_data_subnet_ids[count.index]
  route_table_id = aws_route_table.private_data.id
}

module "eks" {
  source = "../modules/eks"

  project_name = var.project_name
  eks_version  = var.eks_version

  # node_subnet_ids/node_instance_types/node_desired_size/node_min_size/node_max_size는
  # 2026-08-20 Karpenter 마이그레이션 3-4(정리)로 제거함 — 관리형 노드그룹(3-3에서 제거) 전용
  # 인자였음. 노드 프로비저닝은 이제 02_k8s-addon/module.karpenter가 전담.
  cluster_subnet_ids = concat(data.terraform_remote_state.network.outputs.public_subnet_ids, data.terraform_remote_state.network.outputs.private_general_subnet_ids)
}

module "ec2" {
  source = "../modules/ec2"

  project_name = var.project_name
  subnet_id    = data.terraform_remote_state.network.outputs.private_general_subnet_ids[0]
  # 00_network는 영구 root(절대 안 지움)라 이 값은 항상 존재함 — 예전엔 security_group이
  # 이 root 안에서 매일 밤 destroy됐어서 try()로 감싸야 했는데, 그 이유 자체가 없어짐.
  security_group_id     = data.terraform_remote_state.network.outputs.security_group_ids["bastion"]
  bastion_instance_type = var.bastion_instance_type
}