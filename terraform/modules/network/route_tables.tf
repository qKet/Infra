# 퍼블릭 라우팅 테이블 — 0.0.0.0/0 트래픽을 인터넷 게이트웨이로
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# 프라이빗(일반 워크로드) 라우팅 테이블 — AZ당 1개, 자기 AZ의 NAT Gateway로만 나가게 함
# (cross-AZ로 NAT 안 타게 해서 트래픽 비용 절감 + 한쪽 AZ의 NAT 장애가 다른 AZ에 영향 안 주게)
resource "aws_route_table" "private" {
  count  = length(var.azs)
  vpc_id = aws_vpc.this.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this[count.index].id
  }

  tags = {
    Name = "${var.project_name}-private-rt-${var.azs[count.index]}"
  }
}

# 프라이빗-데이터(DB/Redis) 라우팅 테이블 — 일반 프라이빗과 분리해서 별도 관리.
# 앞으로도 인터넷 라우트를 절대 추가하지 않아서 DB/Redis 서브넷은 계속 외부와 완전히 격리되게 유지.
resource "aws_route_table" "private_data" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.project_name}-private-data-rt"
  }
}

# private 서브넷 리스트는 [a-일반, a-데이터, b-일반, b-데이터] 순서라
# 짝수 인덱스(count.index*2) = 일반, 홀수 인덱스(count.index*2+1) = 데이터
resource "aws_route_table_association" "private" {
  count          = length(var.azs)
  subnet_id      = aws_subnet.private[count.index * 2].id
  route_table_id = aws_route_table.private[count.index].id
}

resource "aws_route_table_association" "private_data" {
  count          = length(var.azs)
  subnet_id      = aws_subnet.private[count.index * 2 + 1].id
  route_table_id = aws_route_table.private_data.id
}
