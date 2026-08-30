# vpc/subnet/security_group은 00_network(영구 root)로 분리됨 — 무료 리소스라 destroy할 이유가
# 없어서. 이 root(01_infrastructure)는 비용이 나가는 것만 남아서 통째로 destroy해도 안전함.

/*
  [NAT Gateway]
  이름        :  team5-qket-nat-{AZ}, team5-qket-nat-eip-{AZ}
  설명        :  AZ당 1개, vpc·subnet 둘 다의 값이 필요해서 이 root에 둠 — 00_network(영구 root)에
                두면 매일 밤 재생성되는 NAT Gateway ID 때문에 그 root까지 매번 재적용해야 함
*/
resource "aws_eip" "nat" {
  count  = length(var.azs)
  domain = "vpc"

  tags = {
    Name = "${var.project_name}-nat-eip-${var.azs[count.index]}"
  }
}

resource "aws_nat_gateway" "this" {
  count         = length(var.azs)
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = data.terraform_remote_state.network.outputs.public_subnet_ids[count.index]

  tags = {
    Name = "${var.project_name}-nat-${var.azs[count.index]}"
  }
}

/*
  [라우팅 테이블 - Public]
  이름        :  team5-qket-public-rt
  설명        :  0.0.0.0/0 트래픽을 인터넷 게이트웨이로
*/
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

/*
  [라우팅 테이블 - Private(일반 워크로드)]
  이름        :  team5-qket-private-rt-{AZ}
  설명        :  AZ당 1개, 자기 AZ의 NAT Gateway로만 나가게 함(cross-AZ 트래픽 비용 절감 +
                한쪽 AZ NAT 장애가 다른 AZ에 안 번지게)
*/
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

/*
  [라우팅 테이블 - Private(데이터)]
  이름        :  team5-qket-private-data-rt
  설명        :  DB/Redis 전용, 일반 프라이빗과 분리 관리. 인터넷 라우트를 절대 추가하지 않아서
                외부와 완전히 격리 유지
*/
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

/*
  [EKS 클러스터]
  이름        :  team5-qket-cluster
  설명        :  컨트롤 플레인 + 부트스트랩 노드그룹(고정, 오토스케일은 karpenter가 전담)
*/
module "eks" {
  source = "../modules/eks"

  project_name = var.project_name
  eks_version  = var.eks_version

  cluster_subnet_ids = concat(data.terraform_remote_state.network.outputs.public_subnet_ids, data.terraform_remote_state.network.outputs.private_general_subnet_ids)

  # Karpenter/CoreDNS 등이 뜰 최초의 노드가 없으면 데드락에 빠져서 부트스트랩 노드 1개를 둠.
  node_subnet_ids     = data.terraform_remote_state.network.outputs.private_general_subnet_ids
  node_instance_types = var.node_instance_types
  node_desired_size   = var.node_desired_size
  node_min_size       = var.node_min_size
  node_max_size       = var.node_max_size
}

/*
  [EC2 Bastion]
  이름        :  team5-qket-ssm-bastion
  설명        :  SSM Session Manager로만 접속하는 포트포워딩용 bastion(SSH 미사용)
*/
module "ec2" {
  source = "../modules/ec2"

  project_name = var.project_name
  subnet_id    = data.terraform_remote_state.network.outputs.private_general_subnet_ids[0]
  # 00_network는 영구 root라 이 값은 항상 존재함(try() 불필요).
  security_group_id     = data.terraform_remote_state.network.outputs.security_group_ids["bastion"]
  bastion_instance_type = var.bastion_instance_type
}