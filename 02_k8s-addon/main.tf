/*
  [k8s - Namespace]
  이름        :  qket-release, qket-prod
  설명        :  04_data보다 먼저 apply되는 여기서 미리 만들어둠(04_data의 config_map/
                service_account가 namespace 존재를 전제하기 때문). networkpolicy는 여전히
                Infra/kubernetes/*.yaml + ArgoCD가 관리, namespace/ingress만 예외
*/
resource "kubernetes_namespace" "qket" {
  for_each = toset(["release", "prod"])

  metadata {
    name = "qket-${each.key}"
    labels = {
      name = "qket-${each.key}"
    }
  }

  # 이 네임스페이스 안 CR(ScaledObject, SecretStore 등)의 finalizer는 각 컨트롤러가 살아있어야
  # 풀림 — keda/eso_controller가 네임스페이스보다 먼저 destroy되면 Terminating에 멈춤.
  depends_on = [module.keda, module.eso_controller]
}

/*
  [ArgoCD]
  이름        :  argocd (Helm) + qket-cd / qket-cd-release Application
  설명        :  depends_on = [module.alb_controller] — ALB Controller의 mutating webhook이
                아직 준비 안 된 상태에서 ArgoCD가 자기 Service를 만들면 "no endpoints available" 에러
*/
module "argocd" {
  source = "../modules/addons/argocd"

  project_name                    = var.project_name
  aws_region                      = var.aws_region
  argocd_notifications_secret_arn = data.terraform_remote_state.registry.outputs.argocd_notifications_secret_arn

  depends_on = [module.alb_controller, module.eso_controller]
}

/*
  [ESO Controller]
  이름        :  external-secrets (Helm, kube-system 공유 singleton)
  설명        :  release/prod가 공유하는 singleton. 각 04_data의 module.eso는 이 역할에 정책만
                추가하고 SecretStore/ExternalSecret만 만듦
*/
module "eso_controller" {
  source = "../modules/addons/eso-controller"

  project_name = var.project_name

  oidc_provider_arn = data.terraform_remote_state.infrastructure.outputs.oidc_provider_arn
  oidc_provider_url = data.terraform_remote_state.infrastructure.outputs.oidc_provider_url

  extra_secret_arns = [data.terraform_remote_state.registry.outputs.argocd_notifications_secret_arn]

  depends_on = [module.alb_controller]
}



/*
  [Gateway API CRD]
  이름        :  gateway-api-crds (Helm)
  설명        :  module.alb_controller보다 반드시 먼저 있어야 함(ALB Controller가 부팅 시 이 CRD
                존재로 ALBGatewayAPI 기능을 켤지 정함)
*/
module "gateway_api_crds" {
  source = "../modules/addons/gateway-api/crds"
}

/*
  [ALB Controller]
  이름        :  aws-load-balancer-controller (Helm)
  설명        :  Ingress/Gateway를 보고 실제 ALB를 만듦. depends_on = [module.gateway_api_crds] —
                CRD가 부팅 시점에 없으면 ALBGatewayAPI가 비활성화된 채로 굳어서 수동 재시작이 필요해짐
*/
module "alb_controller" {
  source = "../modules/addons/alb-controller"

  project_name = var.project_name
  aws_region   = var.aws_region

  vpc_id       = data.terraform_remote_state.infrastructure.outputs.vpc_id
  cluster_name = data.terraform_remote_state.infrastructure.outputs.eks_cluster_name

  oidc_provider_arn = data.terraform_remote_state.infrastructure.outputs.oidc_provider_arn
  oidc_provider_url = data.terraform_remote_state.infrastructure.outputs.oidc_provider_url

  depends_on = [module.gateway_api_crds]
}

/*
  [GatewayClass]
  이름        :  alb
  설명        :  CRD 차트가 아니라 여기 따로 둠. ALB Controller가 자기 finalizer를 붙이는
                오브젝트라, destroy 시 컨트롤러보다 먼저 없어져야 finalizer가 풀림(반대로 두면
                destroy가 영원히 멈춤) — depends_on을 alb_controller로 걸어 파괴 순서를 역전시킴
*/
resource "kubectl_manifest" "gateway_class" {
  yaml_body = <<-EOT
    apiVersion: gateway.networking.k8s.io/v1
    kind: GatewayClass
    metadata:
      name: alb
    spec:
      controllerName: gateway.k8s.aws/alb
  EOT

  depends_on = [module.alb_controller]
}

/*
  [Gateway API - Pilot]
  이름        :  team5-qket-gw-prod-alb
  namespace  :  qket-prod
  설명        :  prod 실제 컷오버. release(dev.jun979.click)는 "개발 서버는 관리자만" 방침에
                따라 공개 ALB가 아닌 admin Gateway로 옮겨서 for_each가 prod만 남음
*/
locals {
  ingress_config_public = { for k, v in local.ingress_config : k => v if k != "release" }
}

module "gateway_api_app" {
  source   = "../modules/addons/gateway-api/pilot"
  for_each = local.ingress_config_public

  env                = each.key
  namespace          = kubernetes_namespace.qket[each.key].metadata[0].name
  hostname           = each.value.host
  certificate_arn    = each.value.certificate_arn
  load_balancer_name = "team5-qket-gw-${each.key}-alb"

  depends_on = [
    module.alb_controller,
    module.gateway_api_crds,
    kubectl_manifest.gateway_class,
    module.gateway_api_faro,
    module.alloy_faro,
    kubernetes_namespace.qket,
  ]
}

/*
  [Gateway API - Faro ReferenceGrant]
  이름        :  gateway-api-faro (Helm)
  설명        :  alloy-faro(monitoring 네임스페이스)를 release/prod의 HTTPRoute가 cross-namespace로
                참조할 수 있게 하는 ReferenceGrant + TargetGroupConfiguration — 공유 리소스라 여기 한 번만 만듦
*/
module "gateway_api_faro" {
  source = "../modules/addons/gateway-api/faro"

  allowed_namespaces = [for k in keys(local.ingress_config) : kubernetes_namespace.qket[k].metadata[0].name]

  # ReferenceGrant 대상 네임스페이스(monitoring)가 먼저 있어야 함.
  depends_on = [module.alb_controller, module.gateway_api_crds, module.monitoring, kubernetes_namespace.qket]
}

/*
  [Gateway API - Admin]
  이름        :  team5-qket-gw-admin-alb (grafana/cd/dev 공유)
  설명        :  관리 도구(Grafana/ArgoCD) + dev(release) 공유 admin Gateway — 팀원 IP
                허용목록(var.admin_allowed_cidrs)을 셋 다 공유. 인증서는 03_registry가 만든 걸 remote_state로 읽음
*/
module "gateway_api_admin" {
  source = "../modules/addons/gateway-api/admin"

  admin_allowed_cidrs = var.admin_allowed_cidrs

  grafana_certificate_arn = data.terraform_remote_state.registry.outputs.grafana_certificate_arn
  argocd_certificate_arn  = data.terraform_remote_state.registry.outputs.argocd_certificate_arn

  dev_hostname        = local.ingress_config.release.host
  dev_certificate_arn = local.ingress_config.release.certificate_arn

  depends_on = [
    module.alb_controller,
    module.gateway_api_crds,
    kubectl_manifest.gateway_class,
    module.gateway_api_faro,
    module.alloy_faro,
    module.monitoring,
    module.argocd,
    kubernetes_namespace.qket,
  ]
}

/*
  [Karpenter]
  이름        :  karpenter (Helm) + team5-qket-default (NodePool/EC2NodeClass)
  설명        :  cluster-autoscaler를 대체하는 노드 오토스케일러
*/
module "karpenter" {
  source = "../modules/addons/karpenter"

  project_name = var.project_name
  aws_region   = var.aws_region
  cluster_name = data.terraform_remote_state.infrastructure.outputs.eks_cluster_name

  oidc_provider_arn = data.terraform_remote_state.infrastructure.outputs.oidc_provider_arn
  oidc_provider_url = data.terraform_remote_state.infrastructure.outputs.oidc_provider_url

  # 기존 노드그룹과 동일한 서브넷/보안그룹 재사용 — Karpenter 전용 discovery 태그 추가 불필요
  node_subnet_ids           = data.terraform_remote_state.infrastructure.outputs.private_general_subnet_ids
  cluster_security_group_id = data.terraform_remote_state.infrastructure.outputs.eks_cluster_security_group_id

  depends_on = [module.alb_controller]
}

/*
  [오버프로비저닝]
  이름        :  overprovisioning ("풍선 파드")
  namespace  :  qket-prod
  설명        :  Karpenter 노드 생성 리드타임 동안 KEDA 스케일업 파드가 Pending으로 몰리는 문제를,
                노드를 미리 여유로 예약해서 해결. prod 오픈런 트래픽을 겨냥해 qket-prod에 두지만
                preemption은 namespace를 안 가려 release도 opportunistic하게 씀
*/
module "overprovisioning" {
  source = "../modules/addons/overprovisioning"

  namespace = kubernetes_namespace.qket["prod"].metadata[0].name

  depends_on = [module.karpenter, kubernetes_namespace.qket]
}

/*
  [VPC CNI addon]
  이름        :  vpc-cni (EKS 관리형 addon)
  설명        :  NetworkPolicy를 실제로 집행시키기 위함. aws-eks-nodeagent(집행 에이전트)는 이미
                있었지만, NetworkPolicy를 PolicyEndpoint CR로 번역하는 컨트롤러
                (amazon-network-policy-controller-k8s)가 없어서 실질적으로 아무것도 안 막고 있었음 —
                enableNetworkPolicy를 켜야 그 컨트롤러가 같이 설치됨.
                ⚠️ 적용 전에 CD 레포 NetworkPolicy에 ALB 소스 CIDR(ipBlock)이 먼저 반영돼 있어야
                함 — 안 그러면 ALB→backend 직접 연결이 전부 막혀 즉시 전체 다운으로 이어짐.
                resolve_conflicts_on_create = OVERWRITE — 이미 self-managed로 떠있는 설치를 흡수(adopt)
*/
resource "aws_eks_addon" "vpc_cni" {
  cluster_name = data.terraform_remote_state.infrastructure.outputs.eks_cluster_name
  addon_name   = "vpc-cni"

  configuration_values = jsonencode({
    enableNetworkPolicy = "true"
  })

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
}

/*
  [EBS CSI addon]
  이름        :  aws-ebs-csi-driver (EKS 관리형 addon)
  설명        :  Karpenter 다음(최소 1개 노드가 뜬 뒤)에 설치해야 함. 관리형 노드그룹이 없는
                01_infrastructure에 두면 노드가 0개라 파드가 Pending인 채 DEGRADED로 멈춤
*/
data "aws_iam_policy_document" "ebs_csi_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.terraform_remote_state.infrastructure.outputs.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(data.terraform_remote_state.infrastructure.outputs.oidc_provider_url, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(data.terraform_remote_state.infrastructure.outputs.oidc_provider_url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ebs_csi" {
  name               = "${var.project_name}-ebs-csi-role"
  assume_role_policy = data.aws_iam_policy_document.ebs_csi_assume.json
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

resource "aws_eks_addon" "ebs_csi" {
  cluster_name             = data.terraform_remote_state.infrastructure.outputs.eks_cluster_name
  addon_name               = "aws-ebs-csi-driver"
  service_account_role_arn = aws_iam_role.ebs_csi.arn

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [module.karpenter]
}

/*
  [ExternalDNS]
  이름        :  external-dns (Helm)
  설명        :  ALB Controller가 만든 ALB의 주소를 Route53에 자동으로 연결
*/
module "external_dns" {
  source = "../modules/addons/external-dns"

  project_name = var.project_name
  aws_region   = var.aws_region

  oidc_provider_arn = data.terraform_remote_state.infrastructure.outputs.oidc_provider_arn
  oidc_provider_url = data.terraform_remote_state.infrastructure.outputs.oidc_provider_url

  hosted_zone_id = "Z0111999JD2RHOSHTM8A" # jun979.click
  domain_filter  = "jun979.click"

  # gateway-httproute source를 쓰므로 CRD가 먼저 있어야 크래시루프가 안 남.
  depends_on = [module.alb_controller, module.gateway_api_crds]
}

/*
  [모니터링 스택]
  이름        :  monitoring (kube-prometheus-stack, Helm)
  namespace  :  monitoring
  설명        :  Prometheus/Grafana/Alertmanager
*/
module "monitoring" {
  source = "../modules/addons/monitoring"

  project_name = var.project_name
  aws_region   = var.aws_region

  oidc_provider_arn = data.terraform_remote_state.infrastructure.outputs.oidc_provider_arn
  oidc_provider_url = data.terraform_remote_state.infrastructure.outputs.oidc_provider_url

  amp_remote_write_endpoint = data.terraform_remote_state.registry.outputs.amp_remote_write_endpoint
  amp_workspace_arn         = data.terraform_remote_state.registry.outputs.amp_workspace_arn
  amp_query_endpoint        = data.terraform_remote_state.registry.outputs.amp_query_endpoint

  depends_on = [module.alb_controller]
}

/*
  [로그 저장소 - Loki]
  이름        :  loki (Helm)
  namespace  :  monitoring
  설명        :  프론트/백엔드 로그를 모아서 Grafana에서 같이 봄
*/
module "loki" {
  source = "../modules/addons/loki"

  project_name = var.project_name
  aws_region   = var.aws_region

  oidc_provider_arn = data.terraform_remote_state.infrastructure.outputs.oidc_provider_arn
  oidc_provider_url = data.terraform_remote_state.infrastructure.outputs.oidc_provider_url

  depends_on = [module.alb_controller]
}

/*
  [Promtail]
  이름        :  promtail (Helm, DaemonSet)
  설명        :  노드마다 떠서 파드 로그를 Loki로 전송
*/
module "promtail" {
  source = "../modules/addons/promtail"

  depends_on = [module.loki]
}

/*
  [Alloy Faro]
  이름        :  alloy-faro (Helm)
  설명        :  브라우저(프론트엔드 Faro SDK)가 보내는 클릭/에러 이벤트를 받아서 Loki로 전달
*/
module "alloy_faro" {
  source = "../modules/addons/alloy-faro"

  depends_on = [module.loki]
}


/*
  [ServiceMonitor]
  이름        :  backend-servicemonitor (Helm)
  namespace  :  monitoring
  설명        :  backend API 지표(응답시간, 요청수, HikariCP, JVM 등)를 Prometheus가 스크랩하게
                등록. release 환경만 우선 커버. helm_release 기반 — kubernetes_manifest는 CRD 존재
                여부를 plan 시점에 확인해서 매일 밤 destroy/재생성되는 구조와 안 맞았음
*/
module "backend_servicemonitor" {
  source = "../modules/addons/backend-servicemonitor"

  depends_on = [module.monitoring]
}

/*
  [KEDA]
  이름        :  keda (Helm)
  설명        :  backend 오토스케일링 컨트롤러(엔진)만 설치. 실제 스케일 규칙(ScaledObject)은 CD 레포
*/
module "keda" {
  source = "../modules/addons/keda"

  depends_on = [module.alb_controller]
}

/*
  [metrics-server]
  이름        :  metrics-server (Helm)
  설명        :  KEDA(cpu trigger) HPA가 CPU 사용률을 읽으려면 반드시 필요
*/
module "metrics_server" {
  source = "../modules/addons/metrics-server"

  depends_on = [module.alb_controller]
}

/*
  [도메인/인증서 설정]
  이름        :  dev.jun979.click(release), app.jun979.click(prod)
  설명        :  module.gateway_api_app이 이 값으로 Gateway/HTTPRoute를 만듦. 인증서는
                02_k8s-addon(매일 밤 재생성)이 아니라 03_registry(영구)에서 만들고 remote_state로 읽음
*/
locals {
  ingress_config = {
    release = {
      host            = "dev.jun979.click"
      certificate_arn = data.terraform_remote_state.registry.outputs.dev_certificate_arn
    }
    prod = {
      host            = "app.jun979.click"
      certificate_arn = data.terraform_remote_state.registry.outputs.app_certificate_arn
    }
  }
}

/*
  [k8s - StatefulSet MySQL/Redis]
  이름        :  dev-mysql, dev-redis
  namespace  :  qket-release
  설명        :  개발용 스테이트풀셋 MySQL/Redis — release 환경의 RDS/ElastiCache를 완전히 대체(비용 절감)
*/
data "aws_secretsmanager_secret_version" "dev_mysql_root" {
  secret_id = data.terraform_remote_state.registry.outputs.dev_mysql_root_secret_arn
}

module "dev_datastore" {
  source = "../modules/addons/dev-datastore"

  namespace = "qket-release"

  mysql_ebs_volume_id = data.terraform_remote_state.registry.outputs.dev_mysql_ebs_volume_id
  redis_ebs_volume_id = data.terraform_remote_state.registry.outputs.dev_redis_ebs_volume_id
  availability_zone   = data.terraform_remote_state.registry.outputs.dev_datastore_availability_zone

  # 03_registry가 영구 보존
  mysql_root_password = jsondecode(data.aws_secretsmanager_secret_version.dev_mysql_root.secret_string).password

  # ebs_csi가 이 모듈의 PV보다 먼저 destroy되면 PVC/PV의 finalizer가 안 풀려 멈춤 — depends_on으로
  # destroy 역순(dev_datastore 먼저)을 강제.
  depends_on = [kubernetes_namespace.qket, aws_eks_addon.ebs_csi]
}
