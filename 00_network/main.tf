# 01_infrastructure에서 그대로 옮겨온 리소스 — 내용 변경 없음(terraform state mv로 옮긴 것과
# 코드가 정확히 일치해야 plan에 diff가 안 남).
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

# bastion 보안그룹만 여기서 생성 (rds/redis 보안그룹은 data root에서 환경별로 생성).
# 인바운드 규칙 없음 — SSM은 인스턴스가 AWS로 나가는 방향으로만 연결하므로 열 포트가 없음.
#
# 예전엔 01_infrastructure에 있었고 매일 밤 -target으로 같이 destroy됐음 — 보안그룹 자체는
# AWS 요금이 안 붙는 무료 리소스라 destroy할 이유가 없었고, 오히려 밤 시간대에 이 모듈이
# 없어서 -refresh-only가 "Invalid index"로 실패하는 문제(try()로 방어했었음)만 만들었음.
# 여기(영구 root)로 옮기면서 그 try() 방어 코드는 더 이상 필요 없어짐 — 01_infrastructure/outputs.tf 참고.
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
