# prod 전용 root. release는 RDS/ElastiCache 대신 dev-datastore(StatefulSet)를 쓰므로 구조
# 자체가 달라서 04_data를 디렉토리로 분리해둠(release/main.tf 참고).
locals {
  # 폴더 이름("prod")을 environment 값의 근거로 삼음 — 하드코딩 문자열 산개 방지.
  # path.cwd가 아니라 path.root를 써야 -chdir 실행 시에도 정확함.
  environment = basename(abspath(path.root))

  db_instance_class           = "db.t3.small"
  db_allocated_storage        = 50
  db_max_allocated_storage    = 200
  multi_az                    = false # 팀 프로젝트/학습용이라 대기 인스턴스 상시 운영 안 함(비용 절감)
  skip_final_snapshot         = false
  deletion_protection         = true
  redis_node_type             = "cache.t3.small"
  force_destroy               = false
  secret_recovery_window_days = 7 # 실수 삭제 대비 — 7일 대기 후 진짜 삭제
}

# EKS namespace(qket-release/qket-prod)는 여기서 안 만듦 — infrastructure가 미리 만들어둠
# (이 root의 첫 apply 시점부터 이미 있어야 하므로).

/*
  [보안그룹]
  이름        :  team5-qket-rds-prod, team5-qket-redis-prod
  설명        :  EKS 노드/파드, SSM bastion에서만 각자 포트(3306/6379)로 접속 허용. SG ID가 아니라
                infrastructure의 서브넷 CIDR로 ingress를 검(infrastructure destroy/재생성에 안 흔들리게)
*/
module "security_group" {
  source = "../../modules/security_group"

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

/*
  [RDS]
  이름        :  team5-qket-prod (db.t3.small)
  설명        :  prod 운영 DB — deletion_protection=true, skip_final_snapshot=false
*/
module "rds" {
  source = "../../modules/rds"

  project_name = var.project_name
  environment  = local.environment

  private_data_subnet_ids = data.terraform_remote_state.infrastructure.outputs.private_data_subnet_ids
  security_group_id       = module.security_group.security_group_ids["rds-${local.environment}"]

  db_name                  = var.db_name
  db_username              = var.db_username
  db_instance_class        = local.db_instance_class
  db_allocated_storage     = local.db_allocated_storage
  db_max_allocated_storage = local.db_max_allocated_storage

  multi_az            = local.multi_az
  skip_final_snapshot = local.skip_final_snapshot
  deletion_protection = local.deletion_protection

  storage_encrypted = true # 기본값 그대로지만 의도 명시
}

/*
  [ElastiCache - Redis]
  이름        :  team5-qket-prod (cache.t3.small)
  설명        :  prod 운영 Redis(세션/대기열/좌석 락)
*/
module "redis" {
  source = "../../modules/redis"

  project_name = var.project_name
  environment  = local.environment

  private_data_subnet_ids = data.terraform_remote_state.infrastructure.outputs.private_data_subnet_ids
  security_group_id       = module.security_group.security_group_ids["redis-${local.environment}"]

  redis_node_type      = local.redis_node_type
  redis_engine_version = var.redis_engine_version
}

/*
  [S3 Bucket]
  이름        :  team5-posters-prod
  namespace  :  qket-prod
  설명        :  포스터 이미지 업로드용 — force_destroy=false
*/
module "storage" {
  source = "../../modules/storage"

  project_name = var.project_name
  environment  = local.environment
  namespace    = "qket-${local.environment}"

  oidc_provider_arn = data.terraform_remote_state.infrastructure.outputs.oidc_provider_arn
  oidc_provider_url = data.terraform_remote_state.infrastructure.outputs.oidc_provider_url

  force_destroy = local.force_destroy
}

/*
  [k8s - ConfigMap]
  이름        :  app-config
  namespace  :  qket-prod
  설명        :  DB_PORT/DB_NAME/REDIS_PORT/AWS_REGION 등 Terraform이 RDS/ElastiCache를 만들 때
                이미 아는 값이라 GitHub Variables 대신 직접 ConfigMap으로 관리
*/
resource "kubernetes_config_map" "app_config" {
  metadata {
    name      = "app-config"
    namespace = "qket-${local.environment}"
  }

  data = {
    DB_PORT                = tostring(module.rds.rds_port)
    DB_NAME                = module.rds.rds_db_name
    REDIS_PORT             = tostring(module.redis.redis_port)
    AWS_REGION             = var.aws_region
    NOTIFICATION_QUEUE_URL = module.notification_queue.queue_url # 개인 알림(회원가입 인증코드, 예매확정/취소 영수증) — module.notification_queue의 통합 큐, type 필드로 분기
    OPEN_ALERT_QUEUE_URL   = module.open_alert_queue.queue_url   # 예매 오픈 알림 구독자 브로드캐스트 — module.open_alert_queue, 위와 별개 큐(다대다 발송이라 분리)
  }
}

/*
  [Secret Manager]
  이름        :  db-secrets, redis-secrets
  namespace  :  qket-prod
  설명        :  ESO가 Secrets Manager 값을 K8s Secret으로 동기화. 컨트롤러 자체(Helm/IRSA/CRD)는
                02_k8s-addon의 module.eso_controller(공유 singleton)가 담당, 여기는 prod 전용 동기화 규칙만
*/
module "eso" {
  source = "../../modules/addons/eso"

  project_name = var.project_name
  environment  = local.environment
  aws_region   = var.aws_region
  namespace    = "qket-${local.environment}"

  eso_role_name = data.terraform_remote_state.k8s_addon.outputs.eso_role_name

  rds_master_user_secret_arn = module.rds.rds_master_user_secret_arn
  rds_endpoint               = module.rds.rds_endpoint
  redis_endpoint             = module.redis.redis_endpoint

  secret_recovery_window_days = local.secret_recovery_window_days
  external_api_keys           = var.external_api_keys

  # ArgoCD 알림용 시크릿 읽기 권한은 이제 02_k8s-addon의 module.eso_controller가 직접 붙임
  # (그 시크릿을 쓰는 notifications_secrets도 같은 root라서) — 여기서 또 붙이면 중복.
}

/*
  [SQS + Lambda]
  이름        :  team5-qket-open-alert-prod / team5-qket-open-alert-mailer-prod
  설명        :  예매 오픈 알림 — 백엔드 @Scheduled 스위퍼가 5분마다 publish, Lambda가 consume.
                release/prod 각자 큐/함수를 가짐
*/
module "open_alert_queue" {
  source = "../../modules/sqs"

  name         = "open-alert"
  project_name = var.project_name
  environment  = local.environment

  sender_role_name = module.storage.backend_role_name
}

module "open_alert_mailer" {
  source = "../../modules/lambda"

  name         = "open-alert-mailer"
  project_name = var.project_name
  environment  = local.environment
  source_dir   = "${path.module}/../../lambda/open-alert-mailer"

  queue_arn  = module.open_alert_queue.queue_arn
  ses_domain = "jun979.click"
  from_email = var.open_alert_from_email
}

/*
  [SQS + Lambda]
  이름        :  team5-qket-email-verification-prod
  설명        :  회원가입 이메일 인증 + 예매확정/취소 알림을 큐 하나로 처리 — SQS(backend가
                type 필드로 종류 구분해 요청 넣음) → Lambda(type 보고 분기해서 SES 발송)
*/
module "notification_queue" {
  source = "../../modules/sqs"

  name         = "email-verification"
  project_name = var.project_name
  environment  = local.environment

  visibility_timeout_seconds = 180 # notification_mailer timeout(30s) 기준 6배

  sender_role_name = module.storage.backend_role_name
}

module "notification_mailer" {
  source = "../../modules/lambda"

  name         = "email-verification"
  project_name = var.project_name
  environment  = local.environment
  source_dir   = "${path.module}/../../lambda/notification-mailer"

  timeout                    = 30
  batch_size                 = 1
  report_batch_item_failures = false

  queue_arn  = module.notification_queue.queue_arn
  ses_domain = "jun979.click"
  from_email = "noreply@jun979.click"
}

# 백엔드가 알림 큐들에 메시지를 넣을 권한(sqs:SendMessage)은 이제 modules/sqs 자체가
# sender_role_name으로 받아서 만듦(위 module.open_alert_queue/notification_queue 참고).
