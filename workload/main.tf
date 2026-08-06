# default 워크스페이스에서 실수로 apply하는 걸 막음 — 반드시 release/prod 중 하나를 select한 뒤 적용.
# (locals의 lookup()이 "default"에도 안 걸리게 fallback을 두는 이유: 여기서 막지 않으면
#  terraform validate/plan이 아래 env_config 조회 단계에서 이 친절한 에러 메시지 대신
#  밋밋한 "Invalid index"로 먼저 죽어버림 — 실제 apply 차단은 이 precondition이 전담.)
resource "terraform_data" "workspace_guard" {
  lifecycle {
    precondition {
      condition     = contains(["release", "prod"], terraform.workspace)
      error_message = "workspace는 'release' 또는 'prod'여야 합니다 (지금: '${terraform.workspace}'). 'terraform workspace select release' 또는 'terraform workspace new release'로 전환하세요."
    }
  }
}

locals {
  environment = terraform.workspace

  # release/prod마다 달라지는 값들 — release는 저렴/자주재생성 전제, prod는 안전장치를 켠 기본값.
  # 예전엔 "prod 켤 때 코드를 직접 고칠 것"이라는 주석으로 남겨뒀었는데, workspace 전환만으로

  env_config_map = {
    release = {
      db_instance_class        = "db.t3.micro"
      db_allocated_storage     = 20
      db_max_allocated_storage = 100
      multi_az                 = false
      skip_final_snapshot      = true
      deletion_protection      = false
      redis_node_type          = "cache.t3.micro"
      force_destroy            = true
    }
    prod = {
      db_instance_class        = "db.t3.small"
      db_allocated_storage     = 50
      db_max_allocated_storage = 200
      multi_az                 = true
      skip_final_snapshot      = false
      deletion_protection      = true
      redis_node_type          = "cache.t3.small"
      force_destroy            = false
    }
  }

  # "default" workspace(초기 상태)에서도 validate/plan이 안 죽게 release 기본값으로 폴백.
  # 실제로 default에서 apply를 시도하면 위 workspace_guard precondition이 막아줌.
  env_config = lookup(local.env_config_map, local.environment, local.env_config_map["release"])
}

# EKS namespace 생성 
# (release workspace → qket-release, prod workspace → qket-prod).
resource "kubernetes_namespace" "this" {
  metadata {
    name = "qket-${local.environment}"
    labels = {
      name = "qket-${local.environment}"
    }
  }
}

# rds/redis 보안그룹 — EKS 노드/파드, SSM bastion에서만 각자 포트로 접속 허용.
# environment(workspace)별로 별도 그룹이 생김 (이름에 local.environment가 들어감).
module "security_group" {
  source = "../modules/security_group"

  project_name = var.project_name
  vpc_id       = data.terraform_remote_state.platform.outputs.vpc_id

  security_groups = {
    "rds-${local.environment}" = {
      ingress = [
        {
          description     = "MySQL from EKS nodes/pods"
          from_port       = 3306
          to_port         = 3306
          protocol        = "tcp"
          security_groups = [data.terraform_remote_state.platform.outputs.eks_cluster_security_group_id]
          cidr_blocks     = []
        },
        {
          description     = "MySQL from SSM bastion"
          from_port       = 3306
          to_port         = 3306
          protocol        = "tcp"
          security_groups = [data.terraform_remote_state.platform.outputs.bastion_security_group_id]
          cidr_blocks     = []
        }
      ]
    }
    "redis-${local.environment}" = {
      ingress = [
        {
          description     = "Redis from EKS nodes/pods"
          from_port       = 6379
          to_port         = 6379
          protocol        = "tcp"
          security_groups = [data.terraform_remote_state.platform.outputs.eks_cluster_security_group_id]
          cidr_blocks     = []
        },
        {
          description     = "Redis from SSM bastion"
          from_port       = 6379
          to_port         = 6379
          protocol        = "tcp"
          security_groups = [data.terraform_remote_state.platform.outputs.bastion_security_group_id]
          cidr_blocks     = []
        }
      ]
    }
  }
}

module "rds" {
  source = "../modules/rds"

  project_name = var.project_name
  environment  = local.environment

  private_data_subnet_ids = data.terraform_remote_state.platform.outputs.private_data_subnet_ids
  security_group_id       = module.security_group.security_group_ids["rds-${local.environment}"]

  db_name                  = var.db_name
  db_username              = var.db_username
  db_instance_class        = local.env_config.db_instance_class
  db_allocated_storage     = local.env_config.db_allocated_storage
  db_max_allocated_storage = local.env_config.db_max_allocated_storage

  multi_az            = local.env_config.multi_az
  skip_final_snapshot = local.env_config.skip_final_snapshot
  deletion_protection = local.env_config.deletion_protection
}

module "redis" {
  source = "../modules/redis"

  project_name = var.project_name
  environment  = local.environment

  private_data_subnet_ids = data.terraform_remote_state.platform.outputs.private_data_subnet_ids
  security_group_id       = module.security_group.security_group_ids["redis-${local.environment}"]

  redis_node_type      = local.env_config.redis_node_type
  redis_engine_version = var.redis_engine_version
}

module "storage" {
  source = "../modules/storage"

  project_name = var.project_name
  environment  = local.environment
  namespace    = kubernetes_namespace.this.metadata[0].name

  oidc_provider_arn = data.terraform_remote_state.platform.outputs.oidc_provider_arn
  oidc_provider_url = data.terraform_remote_state.platform.outputs.oidc_provider_url

  force_destroy = local.env_config.force_destroy
}

# DB_PORT/DB_NAME/REDIS_PORT/AWS_REGION — 전부 사람이 GitHub Variables에 따로 입력할 필요 없이
# 이미 Terraform이 RDS/ElastiCache를 만들 때 알고 있는 값이라 직접 ConfigMap으로 관리.
resource "kubernetes_config_map" "app_config" {
  metadata {
    name      = "app-config"
    namespace = kubernetes_namespace.this.metadata[0].name
  }

  data = {
    DB_PORT    = tostring(module.rds.rds_port)
    DB_NAME    = module.rds.rds_db_name
    REDIS_PORT = tostring(module.redis.redis_port)
    AWS_REGION = var.aws_region
  }
}
