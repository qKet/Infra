module "vpc" {
  source = "../modules/vpc"

  project_name = var.project_name
  vpc_cidr     = var.vpc_cidr
}

module "subnet" {
  source = "../modules/subnet"

  project_name = var.project_name
  vpc_id       = module.vpc.vpc_id

  azs                  = var.azs
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
}

# ── NAT Gateway / 라우팅 — vpc·subnet 모듈 둘 다의 출력이 필요해서 root에 둠 ──
# (vpc 모듈 안에 두면 subnet의 출력이, subnet 모듈 안에 두면 vpc가 필요 없어서 문제 없지만
#  "라우팅은 vpc/subnet 둘 다를 엮는 관심사"로 보고 root로 분리. modules/vpc↔modules/subnet
#  사이에 서로의 출력을 주고받는 순환 참조를 만들지 않는 게 핵심 — 자세한 이유는
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
  subnet_id     = module.subnet.public_subnet_ids[count.index]

  tags = {
    Name = "${var.project_name}-nat-${var.azs[count.index]}"
  }
}

# 퍼블릭 라우팅 테이블 — 0.0.0.0/0 트래픽을 인터넷 게이트웨이로
resource "aws_route_table" "public" {
  vpc_id = module.vpc.vpc_id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = module.vpc.igw_id
  }

  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  count          = length(module.subnet.public_subnet_ids)
  subnet_id      = module.subnet.public_subnet_ids[count.index]
  route_table_id = aws_route_table.public.id
}

# 프라이빗(일반 워크로드) 라우팅 테이블 — AZ당 1개, 자기 AZ의 NAT Gateway로만 나가게 함
# (cross-AZ로 NAT 안 타게 해서 트래픽 비용 절감 + 한쪽 AZ의 NAT 장애가 다른 AZ에 영향 안 주게)
resource "aws_route_table" "private" {
  count  = length(var.azs)
  vpc_id = module.vpc.vpc_id

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
  subnet_id      = module.subnet.private_general_subnet_ids[count.index]
  route_table_id = aws_route_table.private[count.index].id
}

# 프라이빗-데이터(DB/Redis) 라우팅 테이블 — 일반 프라이빗과 분리해서 별도 관리.
# 앞으로도 인터넷 라우트를 절대 추가하지 않아서 DB/Redis 서브넷은 계속 외부와 완전히 격리되게 유지.
resource "aws_route_table" "private_data" {
  vpc_id = module.vpc.vpc_id

  tags = {
    Name = "${var.project_name}-private-data-rt"
  }
}

resource "aws_route_table_association" "private_data" {
  count          = length(var.azs)
  subnet_id      = module.subnet.private_data_subnet_ids[count.index]
  route_table_id = aws_route_table.private_data.id
}

# bastion 보안그룹만 여기서 생성 (rds/redis 보안그룹은 data root에서 환경별로 생성).
# 인바운드 규칙 없음 — SSM은 인스턴스가 AWS로 나가는 방향으로만 연결하므로 열 포트가 없음.
module "security_group" {
  source = "../modules/security_group"

  project_name = var.project_name
  vpc_id       = module.vpc.vpc_id

  security_groups = {
    bastion = {
      ingress = []
    }
  }
}

module "eks" {
  source = "../modules/eks"

  project_name = var.project_name
  eks_version  = var.eks_version

  cluster_subnet_ids = concat(module.subnet.public_subnet_ids, module.subnet.private_general_subnet_ids)
  node_subnet_ids    = module.subnet.private_general_subnet_ids

  node_instance_types = var.node_instance_types
  node_desired_size   = var.node_desired_size
  node_min_size       = var.node_min_size
  node_max_size       = var.node_max_size
}

module "ec2" {
  source = "../modules/ec2"

  project_name = var.project_name
  subnet_id    = module.subnet.private_general_subnet_ids[0]
  # try()로 감쌈 — module.security_group이 destroy된 상태(매일 밤)에는 security_group_ids가
  # 빈 맵이라 존재하지 않는 키 인덱싱이 하드 에러를 냄(2026-08-11 실제로 겪음 — terraform
  # apply -refresh-only가 module.ec2 자체는 안 건드리는데도 이 표현식 평가 때문에 통째로 실패).
  # 실제 apply(아침, 전체 재생성)할 땐 module.security_group이 먼저 만들어지므로 정상적인 값이 들어감.
  security_group_id     = try(module.security_group.security_group_ids["bastion"], null)
  bastion_instance_type = var.bastion_instance_type
}