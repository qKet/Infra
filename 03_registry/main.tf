/*
  [ECR]
  이름        :  team5/ecr/qket
  설명        :  backend/frontend가 공유하는 단일 저장소, release/prod는 태그로만 구분
*/
module "ecr" {
  source = "../modules/ecr"

  repository_name = var.ecr_repository_name
}

/*
  [AMP - Amazon Managed Prometheus]
  이름        :  team5-qket-amp
  설명        :  02_k8s-addon의 Prometheus 지표를 EKS 클러스터 수명과 무관하게 영구 저장.
                IRSA(쓰기 권한)는 Prometheus ServiceAccount 생명주기를 따라야 해서 monitoring 모듈에 둠
*/
resource "aws_prometheus_workspace" "this" {
  alias = "${var.project_name}-amp"
}

/*
  [GitHub Actions OIDC]
  이름        :  team5-qket-gha-{backend,frontend}
  설명        :  GitHub Actions가 고정 키 없이 OIDC로 AWS(ECR push)에 접근 — 레포 각각 별도 role
*/
module "github_actions_oidc" {
  source = "../modules/github-actions-oidc"

  project_name       = var.project_name
  ecr_repository_arn = module.ecr.repository_arn

  # qKet 조직의 불변 ID. `curl https://api.github.com/repos/qKet/backend`의 .owner.id로 확인.
  github_owner_id = "313320752"

  repos = {
    backend = {
      repo             = "qKet/backend"
      repository_id    = "1323850932" # curl https://api.github.com/repos/qKet/backend 의 .id
      allowed_branches = ["release", "main"]
    }
    frontend = {
      repo             = "qKet/frontend"
      repository_id    = "1323797216" # curl https://api.github.com/repos/qKet/frontend 의 .id
      allowed_branches = ["release", "main"]
    }
  }
}

/*
  [ACM 인증서]
  설명    : 각 도메인의 HTTPS 접속을 위한 ACM 인증서 생성
*/
module "grafana_cert" {
  source = "../modules/acm"

  domain_name = "grafana.jun979.click"
  zone_id     = "Z0111999JD2RHOSHTM8A" # jun979.click
}

module "argocd_cert" {
  source = "../modules/acm"

  domain_name = "cd.jun979.click"
  zone_id     = "Z0111999JD2RHOSHTM8A" # jun979.click
}

module "dev_cert" {
  source = "../modules/acm"

  domain_name = "dev.jun979.click"
  zone_id     = "Z0111999JD2RHOSHTM8A" # jun979.click
}

module "app_cert" {
  source = "../modules/acm"

  domain_name = "app.jun979.click"
  zone_id     = "Z0111999JD2RHOSHTM8A" # jun979.click
}

/*
  [EBS 볼륨]
  설명    : dev,redis 영구 데이터 보존용 볼륨 생성
*/
module "dev_mysql_volume" {
  source = "../modules/ebs_volume"

  availability_zone = "ap-northeast-2a"
  size              = 10
  name_tag          = "${var.project_name}-dev-mysql-data"
}

module "dev_redis_volume" {
  source = "../modules/ebs_volume"

  availability_zone = "ap-northeast-2a"
  size              = 2
  name_tag          = "${var.project_name}-dev-redis-data"
}

/*
  [Secret Manager]
  이름        :  team5-qket-dev-mysql-root
  설명        :  개발용 MySQL 루트 비밀번호 — 여기서 딱 한 번만 생성해 영구 보존(재생성 시 컨테이너
                데이터 디렉터리와 값이 어긋나는 드리프트 방지). 04_data의 module.eso가 재사용
*/
resource "random_password" "dev_mysql_root" {
  length  = 20
  special = false
}

resource "aws_secretsmanager_secret" "dev_mysql_root" {
  name = "${var.project_name}-dev-mysql-root"
}

resource "aws_secretsmanager_secret_version" "dev_mysql_root" {
  secret_id = aws_secretsmanager_secret.dev_mysql_root.id
  secret_string = jsonencode({
    username = "root"
    password = random_password.dev_mysql_root.result
  })

  lifecycle {
    ignore_changes = [secret_string]
  }
}

/*
  [Secret Manager]
  이름        :  team5-qket-argocd-notifications
  설명        :  ArgoCD 알림(이메일) 발신 계정 자격증명 — 02_k8s-addon(매일 재생성)이 아니라 여기
                보존, ESO가 읽어와 K8s Secret으로 동기화. 사람이 직접 발급받은 값이라 ignore_changes로 보호
*/
resource "aws_secretsmanager_secret" "argocd_notifications" {
  name = "${var.project_name}-argocd-notifications"
}

resource "aws_secretsmanager_secret_version" "argocd_notifications" {
  secret_id = aws_secretsmanager_secret.argocd_notifications.id
  secret_string = jsonencode({
    email-username = var.notification_gmail_username
    email-password = var.notification_gmail_app_password
  })

  lifecycle {
    ignore_changes = [secret_string]
  }
}
