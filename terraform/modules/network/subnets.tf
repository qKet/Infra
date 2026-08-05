# private_subnet_cidrs 인덱스를 azs에 2개씩 매핑: [a, a, b, b]
locals {
  private_subnet_azs = flatten([for az in var.azs : [az, az]])
}

# 퍼블릭 서브넷 (AZ당 1개) — ALB, NAT Gateway가 들어갈 자리
resource "aws_subnet" "public" {
  count                   = length(var.azs)
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.azs[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-${var.azs[count.index]}"
    Tier = "public"
  }
}

# 프라이빗 서브넷 (AZ당 2개) — 짝수 인덱스는 일반 워크로드용, 홀수 인덱스는 데이터(DB/Redis)용
resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = local.private_subnet_azs[count.index]

  tags = {
    Name = count.index % 2 == 0 ? "${var.project_name}-private-${local.private_subnet_azs[count.index]}" : "${var.project_name}-private-${local.private_subnet_azs[count.index]}-data"
    Tier = count.index % 2 == 0 ? "private" : "data"
  }
}
