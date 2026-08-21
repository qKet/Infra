resource "aws_ebs_volume" "this" {
  availability_zone = var.availability_zone
  size              = var.size
  type              = "gp3"

  tags = {
    Name = var.name_tag
  }
}
