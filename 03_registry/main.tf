# backend/frontend가 공유하는 단일 ECR 저장소. release/prod는 태그(backend-<sha> 등)로만 구분.
# platform과 마찬가지로 workspace 구분 없는 싱글턴 레이어 — workload(workspace별 state)에 두면
# release/prod가 같은 이름의 저장소를 각자 만들려다 충돌하므로 여기 별도 state로 둔다.
module "ecr" {
  source = "../modules/ecr"

  repository_name = var.ecr_repository_name
}

# Amazon Managed Prometheus(AMP) — 02_k8s-addon의 Prometheus가 수집한 지표를 EKS 클러스터
# 수명과 무관하게 영구 저장하는 곳. 원래 01_infrastructure에 뒀었는데(2026-08-12), 그 root도
# 매일 브랜치가 안 맞으면 orphan 리소스로 오인돼 지워질 수 있다는 걸 실제로 겪음(2026-08-13,
# 팀원이 이 코드 없는 main으로 apply해서 AMP 워크스페이스가 통째로 삭제됨). registry는 ECR처럼
# 완전히 독립적이고 수동으로만 apply하는 불변 싱글턴이라 이게 진짜 안전한 자리 — IRSA(쓰기 권한)는
# 02_k8s-addon의 Prometheus ServiceAccount 생명주기를 따라가야 해서 여기 안 두고 modules/addons/monitoring에 둠.
#
# 일반 EBS(PVC) 방식도 검토했으나 기각 — EKS를 destroy하면 PVC도 같이 삭제되고 StorageClass의
# ReclaimPolicy가 Delete라 EBS 볼륨도 함께 지워짐(Pod 재시작엔 강하지만 클러스터 재생성엔 무력).
resource "aws_prometheus_workspace" "this" {
  alias = "${var.project_name}-amp"
}

# GitHub Actions가 고정 키 없이 OIDC로 AWS(ECR push)에 접근하기 위한 IAM.
# backend/frontend 레포 각각 별도 role — 서로 다른 레포의 워크플로우가 남의 role을 못 씀.
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

# 개발용 MySQL 루트 비밀번호 — 02_k8s-addon(매일 밤 재생성)이 아니라 여기서 딱 한 번만 생성해
# 영구 보존. MySQL 컨테이너는 데이터 디렉터리가 이미 있으면(둘째 날부터) MYSQL_ROOT_PASSWORD를
# 다시 안 읽어서, 매번 새로 생성하면 Terraform이 아는 값과 실제 비밀번호가 어긋나는 드리프트가 생김.
# secret_string을 RDS 마스터 계정 시크릿과 같은 모양(username/password)으로 맞춰서, 04_data의
# module.eso가 RDS든 이거든 그대로 재사용할 수 있게 함.
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

# ArgoCD 알림(이메일) 발신 계정 자격증명 — 02_k8s-addon은 매일 밤 destroy되는 root라 여기
# (03_registry, 절대 안 지워짐)에 Secrets Manager로 저장해두고, 02_k8s-addon에서는
# ESO(ExternalSecret)로 이 값을 읽어와 Kubernetes Secret으로 동기화한다.
# 사람이 직접 발급받은 값이라 external_api_keys와 같은 이유로 lifecycle.ignore_changes로
# 보호 — 재적용 시 값이 빈 문자열로 덮어써지는 사고 방지.
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
