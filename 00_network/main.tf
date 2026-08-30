/*
  [VPC]
  이름        :  team5-qket-vpc
  설명        :  01_infrastructure에서 그대로 옮겨온 리소스 — 내용 변경 없음(state mv 대상이라
                코드가 정확히 일치해야 plan에 diff가 안 남)
*/
module "vpc" {
  source = "../modules/vpc"

  project_name = var.project_name
  vpc_cidr     = var.vpc_cidr
}

/*
  [Subnet]
  이름        :  public / private-general / private-data (AZ당 각 1개)
  설명        :  AZ 2개 × 3-tier(public/private-general/private-data) 서브넷 생성
*/
module "subnet" {
  source = "../modules/subnet"

  project_name = var.project_name
  vpc_id       = module.vpc.vpc_id

  azs                  = var.azs
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
}

/*
  [보안그룹]
  이름        :  team5-qket-bastion-sg
  설명        :  bastion 전용 — 인바운드 규칙 없음(SSM은 아웃바운드 연결만 필요).
                rds/redis 보안그룹은 data root(04_data)에서 환경별로 생성
*/
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
