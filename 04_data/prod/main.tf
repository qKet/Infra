# prod 전용 root. 2026-08-21에 04_data(단일 root + workspace)에서 분리됨 — release가
# RDS/ElastiCache 대신 dev-datastore(StatefulSet)를 쓰게 되면서 release/prod 구조 자체가
# 달라졌고(모듈 유무 자체가 다름), workspace + count/삼항식으로 억지로 한 파일에 합쳐두는 것보다
# 디렉토리를 나누는 게 더 읽기 쉽다고 판단해서 분리함. prod는 이 분리 시점까지 한 번도 apply된
# 적이 없었음(release/backend.tf 주석 참고) — 이 root의 첫 실제 apply가 이 분리 이후가 됨.
locals {
  # 폴더 이름 자체("prod")를 값의 근거로 삼음 — release/main.tf와 같은 이유(하드코딩 문자열을
  # 흩뿌리는 대신 이 root의 디렉토리 경로 자체가 environment 값의 유일한 근거가 되게 함).
  # path.cwd가 아니라 path.root를 써야 -chdir로 실행해도(daily-infrastructure-toggle 런북) 정확함.
  environment = basename(abspath(path.root))

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

# EKS namespace(qket-release/qket-prod)는 여기서 안 만듦 — infrastructure가 한 번의 apply로 둘 다 미리 만들어둠
# (namespace는 이 root의 첫 apply 시점부터 이미 있어야(아래 kubernetes_config_map, module.storage) 해서
# infrastructure 쪽이 맞음). 자세한 이유는 01_infrastructure/main.tf의 kubernetes_namespace.qket 주석 참고.

# rds/redis 보안그룹 — EKS 노드/파드, SSM bastion에서만 각자 포트로 접속 허용.
#
# infrastructure의 SG ID(security_groups)를 직접 참조하지 않고 infrastructure의 "일반 워크로드 서브넷 CIDR"
# (bastion/EKS 노드가 실제로 있는 대역)로 ingress를 검 — SG ID로 참조하면 infrastructure를 destroy할 때
# "아직 참조 중"이라며 AWS가 SG 삭제를 막고(DependencyViolation), infrastructure를 재생성하면 SG ID가
# 바뀌어서 data를 다시 apply해야 하는 문제가 있었음. CIDR은 infrastructure가 몇 번을 destroy/재생성돼도
# 안 바뀌므로 data가 infrastructure 재생성에 전혀 영향받지 않음(단, 서브넷 CIDR 변수 자체를 바꾸면 예외).
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

  # 2026-08-18: 개발 단계 데이터라 스냅샷 복원 절차 없이 destroy+재생성으로 바로 암호화 전환하기로
  # 팀 결정(PAYMENTS 6건 등 QA 기록은 재테스트로 대체 가능하다고 판단). modules/rds/variables.tf의
  # storage_encrypted 기본값(true)을 그대로 씀 — 이 줄은 삭제해도 되지만 의도를 명시적으로 남겨둠.
  storage_encrypted = true
}

module "redis" {
  source = "../../modules/redis"

  project_name = var.project_name
  environment  = local.environment

  private_data_subnet_ids = data.terraform_remote_state.infrastructure.outputs.private_data_subnet_ids
  security_group_id       = module.security_group.security_group_ids["redis-${local.environment}"]

  redis_node_type      = local.redis_node_type
  redis_engine_version = var.redis_engine_version
}

module "storage" {
  source = "../../modules/storage"

  project_name = var.project_name
  environment  = local.environment
  namespace    = "qket-${local.environment}"

  oidc_provider_arn = data.terraform_remote_state.infrastructure.outputs.oidc_provider_arn
  oidc_provider_url = data.terraform_remote_state.infrastructure.outputs.oidc_provider_url

  force_destroy = local.force_destroy
}

# DB_PORT/DB_NAME/REDIS_PORT/AWS_REGION — 전부 사람이 GitHub Variables에 따로 입력할 필요 없이
# 이미 Terraform이 RDS/ElastiCache를 만들 때 알고 있는 값이라 직접 ConfigMap으로 관리.
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

# ESO(External Secrets Operator) — AWS Secrets Manager의 값을 K8s Secret(db-secrets/redis-secrets)으로
# 동기화. RDS가 자동 생성한 마스터 계정 시크릿(username/password)과, 여기서 새로 만드는 "connection"
# 시크릿(DB_HOST/REDIS_HOST)을 합쳐서 CD 헬름 차트(values-prod.yaml의 backend.secrets)가 기대하는
# 그 두 개(db-secrets, redis-secrets)를 정확히 만들어냄.
#
# 컨트롤러 자체(Helm 릴리즈/IRSA 역할/CRD)는 02_k8s-addon의 module.eso_controller(공유
# singleton)가 담당 — 여기 이 모듈은 SecretStore/ExternalSecret 같은 이 환경(prod) 전용 동기화
# 규칙만 만들고, 그 공유 역할에 자기 시크릿 읽기 정책만 추가로 붙임(2026-08-21, 예전엔 release/prod가
# 각자 컨트롤러까지 설치하며 이름 충돌/CRD 소유권 충돌이 났었음 — modules/addons/eso-controller/
# main.tf 참고). rds_master_user_secret_arn/rds_endpoint/redis_endpoint가 이 root가 만든 값이라
# 컨트롤러 자체는 여전히 여기 둘 수 없음(순환 의존) — SecretStore/ExternalSecret만 여기 있는 이유.
# namespace(qket-prod)가 02_k8s-addon 소관이라 매일 밤 destroy될 때 이 db-secrets/redis-secrets도
# 같이 사라지므로, IRSA ServiceAccount/ConfigMap과 마찬가지로 아침에 이 root를 다시 apply해야 함
# — 자세한 내용은 CLAUDE_LLM_WIKI의 daily-infrastructure-toggle 문서 참고.
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

# 예매 오픈 알림 — 백엔드의 @Scheduled 스위퍼가 5분마다 publish, Lambda가 consume. release/prod
# 각자 큐/함수를 가짐(운영 트래픽이 개발/스테이징 알림과 섞이면 안 되므로). SES 도메인 인증 자체는
# 03_registry에 있음(도메인당 한 번만 해야 해서 — modules/lambda/main.tf 주석 참고).
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

# 알림 발송 파이프라인 — 회원가입 이메일 인증 + 예매확정/취소 알림을 모두 여기 큐 하나로 처리.
# SQS(backend가 요청 넣음, type 필드로 종류 구분) → Lambda(type 보고 분기해서 SES로 발송).
# open_alert_queue/mailer와 같은 범용 모듈(modules/sqs, modules/lambda)을 재사용 — 예전엔
# 전용 모듈(modules/messaging)로 따로 있었으나 리소스는 여전히 분리 유지(큐/함수 각 2개).
# timeout/batch_size/report_batch_item_failures를 명시하는 이유: modules/lambda 기본값(batch 10,
# ReportBatchItemFailures on)은 open-alert-mailer 기준이고, 이 Lambda는 기존 동작(batch 1, 부분배치
# 실패응답 미지원)을 그대로 유지해야 해서 다르게 지정함. runtime은 둘 다 기본값(nodejs22.x)을 그대로 씀.
module "notification_queue" {
  source = "../../modules/sqs"

  name         = "email-verification"
  project_name = var.project_name
  environment  = local.environment

  # notification_mailer의 timeout(30s) 기준 6배 — 모듈 기본값(60s)은 open-alert-mailer(timeout 10s)
  # 기준이라 이 Lambda엔 배수가 부족함(modules/sqs/variables.tf 주석 참고)
  visibility_timeout_seconds = 180

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
