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
      db_instance_class           = "db.t3.micro"
      db_allocated_storage        = 20
      db_max_allocated_storage    = 100
      multi_az                    = false
      skip_final_snapshot         = true
      deletion_protection         = false
      redis_node_type             = "cache.t3.micro"
      force_destroy               = true
      secret_recovery_window_days = 0 # 바로 삭제 — 자주 재생성하는 샌드박스라 대기기간 있으면 이름 충돌 남
    }
    prod = {
      db_instance_class           = "db.t3.small"
      db_allocated_storage        = 50
      db_max_allocated_storage    = 200
      multi_az                    = true
      skip_final_snapshot         = false
      deletion_protection         = true
      redis_node_type             = "cache.t3.small"
      force_destroy               = false
      secret_recovery_window_days = 7 # 실수 삭제 대비 — 7일 대기 후 진짜 삭제
    }
  }

  # "default" workspace(초기 상태)에서도 validate/plan이 안 죽게 release 기본값으로 폴백.
  # 실제로 default에서 apply를 시도하면 위 workspace_guard precondition이 막아줌.
  env_config = lookup(local.env_config_map, local.environment, local.env_config_map["release"])
}

# EKS namespace(qket-release/qket-prod)는 여기서 안 만듦 — infrastructure가 한 번의 apply로 둘 다 미리 만들어둠
# (data는 workspace라서 release/prod를 나눠서 두 번 apply해야 하는데, namespace는 이 root의 첫
# apply 시점부터 이미 있어야(아래 kubernetes_config_map, module.storage) 해서 infrastructure 쪽이 맞음).
# 자세한 이유는 01_infrastructure/main.tf의 kubernetes_namespace.qket 주석 참고.

# rds/redis 보안그룹 — EKS 노드/파드, SSM bastion에서만 각자 포트로 접속 허용.
# environment(workspace)별로 별도 그룹이 생김 (이름에 local.environment가 들어감).
#
# infrastructure의 SG ID(security_groups)를 직접 참조하지 않고 infrastructure의 "일반 워크로드 서브넷 CIDR"
# (bastion/EKS 노드가 실제로 있는 대역)로 ingress를 검 — SG ID로 참조하면 infrastructure를 destroy할 때
# "아직 참조 중"이라며 AWS가 SG 삭제를 막고(DependencyViolation), infrastructure를 재생성하면 SG ID가
# 바뀌어서 data를 다시 apply해야 하는 문제가 있었음. CIDR은 infrastructure가 몇 번을 destroy/재생성돼도
# 안 바뀌므로 data가 infrastructure 재생성에 전혀 영향받지 않음(단, 서브넷 CIDR 변수 자체를 바꾸면 예외).
module "security_group" {
  source = "../modules/addons/security_group"

  project_name = var.project_name
  vpc_id       = data.terraform_remote_state.infrastructure.outputs.vpc_id

  security_groups = {
    "rds-${local.environment}" = {
      ingress = [
        {
          description     = "MySQL from private-general subnet (EKS nodes/pods + SSM bastion)"
          from_port       = 3306
          to_port         = 3306
          protocol        = "tcp"
          security_groups = []
          cidr_blocks     = data.terraform_remote_state.infrastructure.outputs.private_general_subnet_cidrs
        }
      ]
    }
    "redis-${local.environment}" = {
      ingress = [
        {
          description     = "Redis from private-general subnet (EKS nodes/pods + SSM bastion)"
          from_port       = 6379
          to_port         = 6379
          protocol        = "tcp"
          security_groups = []
          cidr_blocks     = data.terraform_remote_state.infrastructure.outputs.private_general_subnet_cidrs
        }
      ]
    }
  }
}

module "rds" {
  source = "../modules/addons/rds"

  project_name = var.project_name
  environment  = local.environment

  private_data_subnet_ids = data.terraform_remote_state.infrastructure.outputs.private_data_subnet_ids
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
  source = "../modules/addons/redis"

  project_name = var.project_name
  environment  = local.environment

  private_data_subnet_ids = data.terraform_remote_state.infrastructure.outputs.private_data_subnet_ids
  security_group_id       = module.security_group.security_group_ids["redis-${local.environment}"]

  redis_node_type      = local.env_config.redis_node_type
  redis_engine_version = var.redis_engine_version
}

module "storage" {
  source = "../modules/addons/storage"

  project_name = var.project_name
  environment  = local.environment
  namespace    = "qket-${local.environment}"

  oidc_provider_arn = data.terraform_remote_state.infrastructure.outputs.oidc_provider_arn
  oidc_provider_url = data.terraform_remote_state.infrastructure.outputs.oidc_provider_url

  force_destroy = local.env_config.force_destroy
}

# DB_PORT/DB_NAME/REDIS_PORT/AWS_REGION — 전부 사람이 GitHub Variables에 따로 입력할 필요 없이
# 이미 Terraform이 RDS/ElastiCache를 만들 때 알고 있는 값이라 직접 ConfigMap으로 관리.
resource "kubernetes_config_map" "app_config" {
  metadata {
    name      = "app-config"
    namespace = "qket-${local.environment}"
  }

  data = {
    DB_PORT    = tostring(module.rds.rds_port)
    DB_NAME    = module.rds.rds_db_name
    REDIS_PORT = tostring(module.redis.redis_port)
    AWS_REGION = var.aws_region
  }
}

# ESO(External Secrets Operator) — AWS Secrets Manager의 값을 K8s Secret(db-secrets/redis-secrets)으로
# 동기화. RDS가 자동 생성한 마스터 계정 시크릿(username/password)과, 여기서 새로 만드는 "connection"
# 시크릿(DB_HOST/REDIS_HOST)을 합쳐서 CD 헬름 차트(values-release.yaml의 backend.secrets)가 기대하는
# 그 두 개(db-secrets, redis-secrets)를 정확히 만들어냄.
#
# 02_k8s-addon이 아니라 여기(04_data)에 두는 이유: rds_master_user_secret_arn/rds_endpoint/redis_endpoint가
# 전부 이 root가 만든 값이라, k8s-addon(04_data보다 먼저 apply됨)에 두면 아직 없는 값을 참조하는
# 순환 의존이 생김. 대신 namespace(qket-release/qket-prod)가 02_k8s-addon 소관이라 매일 밤 destroy될 때
# 이 db-secrets/redis-secrets도 같이 사라지므로, IRSA ServiceAccount/ConfigMap과 마찬가지로 아침에
# 이 root를 다시 apply해야 함 — 자세한 내용은 CLAUDE_LLM_WIKI의 daily-infrastructure-toggle 문서 참고.
module "eso" {
  source = "../modules/addons/eso"

  project_name = var.project_name
  environment  = local.environment
  aws_region   = var.aws_region
  namespace    = "qket-${local.environment}"

  oidc_provider_arn = data.terraform_remote_state.infrastructure.outputs.oidc_provider_arn
  oidc_provider_url = data.terraform_remote_state.infrastructure.outputs.oidc_provider_url

  rds_master_user_secret_arn = module.rds.rds_master_user_secret_arn
  rds_endpoint               = module.rds.rds_endpoint
  redis_endpoint             = module.redis.redis_endpoint

  secret_recovery_window_days = local.env_config.secret_recovery_window_days
  external_api_keys           = var.external_api_keys
}