# release 전용 root. 2026-08-21에 04_data(단일 root + workspace)에서 분리됨 — release는
# RDS/ElastiCache 대신 02_k8s-addon의 dev-datastore(StatefulSet MySQL/Redis)를 쓰게 되면서
# prod와 구조 자체가 달라졌고(모듈 유무 자체가 다름), workspace + count/삼항식으로 억지로
# 한 파일에 합쳐두는 것보다 디렉토리를 나누는 게 더 읽기 쉽다고 판단해서 분리함.
# 그래서 prod에 있는 module.rds/module.redis/module.security_group이 여기엔 아예 없음
# (count=0으로 숨겨두는 게 아니라 애초에 이 환경에 그 개념 자체가 없음).
locals {
  environment                 = "release"
  secret_recovery_window_days = 0
}

/*
  [S3 Bucket]
  이름        : team5-posters-release
  namespace  : qket-release
*/
module "storage" {
  source = "../../modules/storage"

  project_name = var.project_name
  environment  = local.environment
  namespace    = "qket-${local.environment}"

  oidc_provider_arn = data.terraform_remote_state.infrastructure.outputs.oidc_provider_arn
  oidc_provider_url = data.terraform_remote_state.infrastructure.outputs.oidc_provider_url

  # (포스터 원본이 남아있는 채로 실수로 destroy되는 걸 막기 위함) 
  force_destroy = false
}

/*
  [k8s - configmap]
  이름        :  app_config
  namespace  :  qket-release
  설명        :  app_config 생성해줌 (k8s에서 app_config를 선언만 하면 값이 들어감)  
*/
resource "kubernetes_config_map" "app_config" {
  metadata {
    name      = "app-config"
    namespace = "qket-${local.environment}"
  }

  data = {
    DB_HOST                = "dev-mysql"
    DB_PORT                = "3306"
    DB_NAME                = "qket"
    REDIS_HOST             = "dev-redis"
    REDIS_PORT             = "6379"
    AWS_REGION             = var.aws_region
    NOTIFICATION_QUEUE_URL = module.notification_queue.queue_url # 개인 알림(회원가입 인증코드, 예매확정/취소 영수증) — module.notification_queue의 통합 큐, type 필드로 분기
    OPEN_ALERT_QUEUE_URL   = module.open_alert_queue.queue_url   # 예매 오픈 알림 구독자 브로드캐스트 — module.open_alert_queue, 위와 별개 큐(다대다 발송이라 분리)
  }
}

# DB_HOST/REDIS_HOST는 고정값이라 위 ConfigMap(app-config)에 직접 넣었고, 비밀번호도 안 바뀌니
# ESO 로테이션 동기화가 필요 없음 — db-secrets는 아래에서 plain kubernetes_secret로 직접 생성.
/*
  [Secret Manager]
  이름        :  db-secrets
  namespace  :  qket-release
  설명        :  
*/
module "eso" {
  source = "../../modules/addons/eso"

  project_name = var.project_name
  environment  = local.environment
  aws_region   = var.aws_region
  namespace    = "qket-${local.environment}"

  oidc_provider_arn = data.terraform_remote_state.infrastructure.outputs.oidc_provider_arn
  oidc_provider_url = data.terraform_remote_state.infrastructure.outputs.oidc_provider_url

  manage_db_redis_secrets = false //false 면 ESO 로테이션 동기화 X

  secret_recovery_window_days = local.secret_recovery_window_days
  external_api_keys           = var.external_api_keys

  extra_secret_arns = [data.terraform_remote_state.registry.outputs.argocd_notifications_secret_arn]
}

# db-secrets — DB_HOST는 위 ConfigMap(app-config)에 이미 있어서 여기선 USERNAME/PASSWORD만.
# 03_registry의 dev_mysql_root 시크릿 값을 apply 시점에 한 번 읽어서 그대로 Secret에 씀
# (02_k8s-addon의 dev-datastore mysql_root_password와 같은 패턴).
data "aws_secretsmanager_secret_version" "dev_mysql_root" {
  secret_id = data.terraform_remote_state.registry.outputs.dev_mysql_root_secret_arn
}

resource "kubernetes_secret" "db_secrets" {
  metadata {
    name      = "db-secrets"
    namespace = "qket-${local.environment}"
  }

  data = {
    DB_USERNAME = "root"
    DB_PASSWORD = jsondecode(data.aws_secretsmanager_secret_version.dev_mysql_root.secret_string).password
  }
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
