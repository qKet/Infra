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
      # 2026-08-18: db.t3.micro → db.t3.medium — 대용량 트래픽 용량 분석(CLAUDE_LLM_WIKI
      # decisions/2026-08-18-capacity-planning-large-traffic-readiness) 후속 조치. 목적은
      # 두 가지: (1) max_connections이 ~85→~340대로 늘어나 backend maxReplicas(8)×dbPoolSize(10)=80의
      # 얇았던 여유(5)가 실질적으로 풀림, (2) 부하테스트로 실제 대용량 시나리오를 검증할 여유가 생김.
      # prod(db.t3.small)는 아직 실트래픽 규모가 불확실해서 이번엔 안 올림 — release에서 재측정 후 결정.
      db_instance_class           = "db.t3.medium"
      db_allocated_storage        = 20
      db_max_allocated_storage    = 100
      multi_az                    = false
      skip_final_snapshot         = true
      deletion_protection         = false
      redis_node_type             = "cache.t3.micro"
      force_destroy               = false # 2026-08-13: release도 실수로 destroy할 때 안에 파일 있으면 막히게 — true였을 땐 포스터 이미지가 통째로 날아갈 수 있었음
      secret_recovery_window_days = 0     # 바로 삭제 — 자주 재생성하는 샌드박스라 대기기간 있으면 이름 충돌 남
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
  source = "../modules/security_group"

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
  source = "../modules/rds"

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

  # 2026-08-18: 개발 단계 데이터라 스냅샷 복원 절차 없이 destroy+재생성으로 바로 암호화 전환하기로
  # 팀 결정(PAYMENTS 6건 등 QA 기록은 재테스트로 대체 가능하다고 판단). modules/rds/variables.tf의
  # storage_encrypted 기본값(true)을 그대로 씀 — 이 줄은 삭제해도 되지만 의도를 명시적으로 남겨둠.
  storage_encrypted = true
}

module "redis" {
  source = "../modules/redis"

  project_name = var.project_name
  environment  = local.environment

  private_data_subnet_ids = data.terraform_remote_state.infrastructure.outputs.private_data_subnet_ids
  security_group_id       = module.security_group.security_group_ids["redis-${local.environment}"]

  redis_node_type      = local.env_config.redis_node_type
  redis_engine_version = var.redis_engine_version
}

module "storage" {
  source = "../modules/storage"

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
    # 개인 알림(회원가입 인증코드, 예매확정/취소 영수증) — module.notification_queue의 통합 큐, type 필드로 분기
    NOTIFICATION_QUEUE_URL = module.notification_queue.queue_url
    # 예매 오픈 알림 구독자 브로드캐스트 — module.open_alert_queue, 위와 별개 큐(다대다 발송이라 분리)
    OPEN_ALERT_QUEUE_URL = module.open_alert_queue.queue_url
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
# 예매 오픈 알림 — 백엔드의 @Scheduled 스위퍼가 5분마다 publish, Lambda가 consume. rds/redis처럼
# release/prod마다 따로 존재(운영 트래픽이 개발/스테이징 알림과 섞이면 안 되므로 큐도 여기서 workspace별로 나눔).
module "open_alert_queue" {
  source = "../modules/sqs"

  name         = "open-alert"
  project_name = var.project_name
  environment  = local.environment
}

module "open_alert_mailer" {
  source = "../modules/lambda"

  name         = "open-alert-mailer"
  project_name = var.project_name
  environment  = local.environment
  source_dir   = "${path.module}/../lambda/open-alert-mailer"

  queue_arn  = module.open_alert_queue.queue_arn
  ses_domain = "jun979.click"
  from_email = var.open_alert_from_email
}

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

    extra_secret_arns = [data.terraform_remote_state.registry.outputs.argocd_notifications_secret_arn]
}

# 알림 발송 파이프라인 — 회원가입 이메일 인증 + 예매확정/취소 알림을 모두 여기 큐 하나로 처리.
# SQS(backend가 요청 넣음, type 필드로 종류 구분) → Lambda(type 보고 분기해서 SES로 발송).
# release/prod 각자 큐/함수를 가짐(테스트 발송이 실제 서비스랑 안 섞이게). SES 도메인 인증 자체는
# 03_registry에 있음(도메인당 한 번만 해야 해서 — modules/lambda/main.tf 주석 참고).
# open_alert_queue/mailer와 같은 범용 모듈(modules/sqs, modules/lambda)을 재사용 — 예전엔
# 전용 모듈(modules/messaging)로 따로 있었으나 리소스는 여전히 분리 유지(큐/함수 각 2개).
# timeout/batch_size/report_batch_item_failures를 명시하는 이유: modules/lambda 기본값(batch 10,
# ReportBatchItemFailures on)은 open-alert-mailer 기준이고, 이 Lambda는 기존 동작(batch 1, 부분배치
# 실패응답 미지원)을 그대로 유지해야 해서 다르게 지정함. runtime은 둘 다 기본값(nodejs22.x)을 그대로 씀.
module "notification_queue" {
  source = "../modules/sqs"

  name         = "email-verification"
  project_name = var.project_name
  environment  = local.environment

  # notification_mailer의 timeout(30s) 기준 6배 — 모듈 기본값(60s)은 open-alert-mailer(timeout 10s)
  # 기준이라 이 Lambda엔 배수가 부족함(modules/sqs/variables.tf 주석 참고)
  visibility_timeout_seconds = 180
}

module "notification_mailer" {
  source = "../modules/lambda"

  name         = "email-verification"
  project_name = var.project_name
  environment  = local.environment
  source_dir   = "${path.module}/../lambda/notification-mailer"

  timeout                    = 30
  batch_size                 = 1
  report_batch_item_failures = false

  queue_arn  = module.notification_queue.queue_arn
  ses_domain = "jun979.click"
  from_email = "noreply@jun979.click"
}

# 백엔드가 알림 큐들에 메시지를 넣을 권한(sqs:SendMessage) — Lambda 쪽 IAM(모듈 안, 큐 읽기+SES 발송)만
# 만들어두고 이걸 빠뜨리면, 로컬에선 가짜 URL이라 InvalidAddressException으로 먼저 막혀서 못 잡아내지만
# 실제 AWS에서는 백엔드가 SendMessage 호출 시 AccessDenied(403)로 조용히 실패함(코드가 예외를 삼키므로
# 사용자는 "발송 실패"만 보고 원인은 CloudTrail/로그 봐야 알 수 있음) — 그래서 여기서 명시적으로 부여.
# modules/storage에서 만든 백엔드 IRSA 역할(backend_role_name 출력값)에 정책만 추가로 붙이는 구조 —
# 역할을 만드는 storage 모듈이 큐가 몇 개인지 알 필요 없게, 큐를 정의하는 이 root에서 큐마다 각각 attach.
# (예전엔 오픈알림 큐 권한만 modules/storage 안에 따로 있었으나 두 큐 방식을 통일하며 이쪽으로 옮김)
data "aws_iam_policy_document" "backend_sqs_open_alert" {
  statement {
    effect    = "Allow"
    actions   = ["sqs:SendMessage"]
    resources = [module.open_alert_queue.queue_arn]
  }
}

# name에 "open-alert"를 붙인 이유: 바로 아래 backend_sqs(개인 알림 큐용)와 같은 백엔드 역할에
# 붙는 인라인 정책이라, 이름이 같으면 (역할, 이름)이 곧 식별자인 인라인 정책 특성상 나중에 apply한
# 쪽이 먼저 것을 덮어써버림 — 실제로 겹쳤던 적이 있어서 접미사로 구분함.
resource "aws_iam_role_policy" "backend_sqs_open_alert" {
  name   = "${var.project_name}-backend-sqs-open-alert-${local.environment}"
  role   = module.storage.backend_role_name
  policy = data.aws_iam_policy_document.backend_sqs_open_alert.json
}

data "aws_iam_policy_document" "backend_sqs" {
  statement {
    effect = "Allow"
    actions = [
      "sqs:SendMessage",
    ]
    resources = [
      module.notification_queue.queue_arn,
    ]
  }
}

resource "aws_iam_role_policy" "backend_sqs" {
  name   = "${var.project_name}-backend-sqs-messaging-${local.environment}"
  role   = module.storage.backend_role_name
  policy = data.aws_iam_policy_document.backend_sqs.json
}