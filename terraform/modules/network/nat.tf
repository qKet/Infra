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
  subnet_id     = aws_subnet.public[count.index].id

  tags = {
    Name = "${var.project_name}-nat-${var.azs[count.index]}"
  }

  depends_on = [aws_internet_gateway.this]
}
