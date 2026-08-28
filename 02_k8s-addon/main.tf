# qket-release/qket-prod 네임스페이스 — 원래 04_data(구 workload, kubernetes_namespace.this, workspace별)가
# 만들었었는데, 04_data는 release/prod를 나눠서 두 번 apply해야 하고(workspace), 그마저도 namespace를
# ArgoCD가 YAML(Infra/kubernetes/{release,prod}/namespace_qKet.yaml)로 관리하도록 바꾸면서 04_data에서
# 제거했었음. 근데 그 ArgoCD Application(infra-manifests)이 아직 안 만들어져서, 새 클러스터에서는
# 네임스페이스가 하나도 없는 채로 04_data apply를 시도하게 되고 kubernetes_config_map/kubernetes_service_account가
# "namespace not found"로 실패함. 여기(k8s-addon)가 01_infrastructure 다음, 04_data보다 먼저 apply되므로,
# 여기서 release/prod 네임스페이스를 둘 다 미리 만들어두면 04_data가 항상 그 존재를 전제할 수 있음.
# networkpolicy는 여전히 Infra/kubernetes/*.yaml + ArgoCD가 관리 — namespace/ingress는 예외적으로
# Terraform(k8s-addon)이 갖고 감(ingress를 여기로 옮긴 이유는 아래 app_ingress 리소스 주석 참고).
# Infra/kubernetes/{release,prod}/namespace_qKet.yaml은 이제 중복이라 정리 대상 — CLAUDE_LLM_WIKI 참고.
#
# 2026-08-10: 01_infrastructure에서 이 리소스와 helm_release.argocd를 여기(k8s-addon)로 이전함 —
# kubernetes/helm provider를 쓰는 리소스가 순수 AWS root(01_infrastructure)와 같은 state에 있으면
# destroy 순서 문제(Access Entry가 먼저 지워져서 Unauthorized)가 재발했었음. 자세한 내용은
# CLAUDE_LLM_WIKI의 eks-destroy-layer-separation 문서 참고.
resource "kubernetes_namespace" "qket" {
  for_each = toset(["release", "prod"])

  metadata {
    name = "qket-${each.key}"
    labels = {
      name = "qket-${each.key}"
    }
  }

  # depends_on = [module.keda, module.eso_controller] (2026-08-22): 이 네임스페이스 안에는
  # ArgoCD/04_data가 만든, 각자 자기 컨트롤러의 finalizer가 걸린 CR들이 있음 —
  # ScaledObject(finalizer.keda.sh, CD Helm 차트가 만듦), SecretStore/ExternalSecret
  # (external-secrets.io 계열, 04_data의 module.eso가 만듦). Terraform은 이 CR들의 존재를
  # 전혀 모르지만(다른 root/ArgoCD가 만듦), 이 네임스페이스를 지우려면 그 CR들이 먼저 지워져야
  # 하고, 그러려면 각 컨트롤러(module.keda, module.eso_controller)가 아직 살아있어야 함.
  # depends_on 없이는 이 둘이 네임스페이스보다 먼저 destroy될 수도 있어서(실제로 KEDA가
  # 먼저 지워져서 ScaledObject 2개가 finalizer.keda.sh에 영원히 막혀 namespace가
  # Terminating으로 멈추는 걸 실제로 겪음 — modules/addons/dev-datastore/aws_eks_addon.ebs_csi와
  # 완전히 같은 클래스의 버그), 여기서 명시적으로 순서를 강제함(destroy는 역순 —
  # namespace가 먼저 지워지고 keda/eso_controller는 그다음에 지워짐).
  depends_on = [module.keda, module.eso_controller]
}

# ArgoCD 설치 + Application 등록 — modules/addons/argocd로 뽑음.
#
# depends_on = [module.alb_controller] — ArgoCD도 자기 Service를 만드는데, ALB Controller는 설치되는
# 순간부터 클러스터 전체의 Service 생성에 mutating webhook(mservice.elbv2.k8s.aws)을 건다. 이 둘이
# depends_on 없이 동시에 apply되면, webhook은 이미 등록됐는데 그걸 처리해줄 컨트롤러 파드는 아직
# Ready가 안 된 타이밍에 ArgoCD의 Service 생성이 걸려서 "no endpoints available for service
# aws-load-balancer-webhook-service"로 실패한다(2026-08-10 실제로 겪음). module.alb_controller의
# helm_release는 wait를 안 껐으니 기본값(true)대로 파드가 Ready될 때까지 기다린 뒤 "생성 완료"로
# 표시되므로, 여기 depends_on만 걸면 그 뒤에 ArgoCD가 안전하게 따라가게 된다.
# 알림용 Gmail 자격증명(ESO 동기화)은 이 모듈 안에 중첩된 module.notifications_secrets가
# 담당 — 2026-08-21: ESO 컨트롤러를 module.eso_controller(아래, 같은 root)로 옮기면서 예전에
# 있던 cross-root CRD 순서 문제(ESO가 04_data라는 "다른 root"에 있어서 매번 "04_data의
# module.eso를 먼저 apply해야 하는" 런북 절차가 필요했음)가 없어짐 — depends_on 하나로 충분.
module "argocd" {
  source = "../modules/addons/argocd"

  project_name                    = var.project_name
  aws_region                      = var.aws_region
  argocd_notifications_secret_arn = data.terraform_remote_state.registry.outputs.argocd_notifications_secret_arn

  depends_on = [module.alb_controller, module.eso_controller]
}

# ESO(External Secrets Operator) 컨트롤러 — release/prod(04_data)가 공유하는 진짜 singleton으로
# 여기 딱 한 곳에만 설치. 04_data 각각의 module.eso는 이 역할(module.eso_controller.role_name)에
# 자기 시크릿 ARN만큼 정책만 추가로 붙이고, SecretStore/ExternalSecret 같은 실제 동기화 규칙만
# 만듦. extra_secret_arns로 넘기는 ArgoCD 알림용 시크릿은 이 root 안에서만 쓰이는 것이라(위
# module.argocd의 notifications_secrets가 argocd 네임스페이스에서 동기화) 04_data가 아니라
# 여기서 바로 권한을 붙임. 자세한 이전 이유는 modules/addons/eso-controller/main.tf 참고.
module "eso_controller" {
  source = "../modules/addons/eso-controller"

  project_name = var.project_name

  oidc_provider_arn = data.terraform_remote_state.infrastructure.outputs.oidc_provider_arn
  oidc_provider_url = data.terraform_remote_state.infrastructure.outputs.oidc_provider_url

  extra_secret_arns = [data.terraform_remote_state.registry.outputs.argocd_notifications_secret_arn]

  depends_on = [module.alb_controller]
}



# Gateway API core CRD — Ingress의 후속 표준으로 전환하는 작업의 1단계. module.alb_controller보다
# 반드시 "먼저" 있어야 함(반대 방향 depends_on 없음, 대신 alb_controller 쪽에서 이 모듈을 기다림) —
# AWS Load Balancer Controller가 부팅 시점에 딱 한 번 이 CRD 존재 여부로 자기 ALBGatewayAPI
# 기능을 켤지 정하기 때문. 이유/실제 겪은 증상은 modules/addons/gateway-api/crds/main.tf 주석과
# CLAUDE_LLM_WIKI decisions/2026-08-20-ingress-to-gateway-api-migration 참고.
#
# 2026-08-22: GatewayClass는 여기 없음 — 아래 kubectl_manifest.gateway_class로 분리됨(이유는
# 그 리소스 주석 참고).
module "gateway_api_crds" {
  source = "../modules/addons/gateway-api/crds"
}

# AWS Load Balancer Controller — Ingress 오브젝트를 보고 실제 ALB를 만들어주는 컨트롤러.
# 이게 없으면 Ingress를 아무리 apply해도 AWS에 ALB 자체가 안 생김(K8s 오브젝트만 있고 실체가 없음).
# 2026-08-10: backup/modules/alb-controller에서 여기로 이전 — Ingress Controller가 만드는
# ALB/타겟그룹/전용SG는 Terraform이 모르는 리소스라, destroy할 땐 반드시 helm uninstall(이 root의
# destroy)이 EKS가 살아있는 동안 먼저 끝나야 함. 그래서 01_infrastructure가 아니라 여기(Layer 2,
# k8s-addon)에 둠 — 자세한 이유는 CLAUDE_LLM_WIKI의 eks-destroy-layer-separation 문서 참고.
#
# depends_on = [module.gateway_api_crds] — 2026-08-20 추가: Gateway API CRD가 이 컨트롤러의
# 부팅 시점에 이미 있어야 ALBGatewayAPI 기능이 켜진다(없으면 "Disabling ALBGatewayAPI: missing
# required CRDs" 로그를 남기고 그 파드가 살아있는 동안 계속 비활성 — kubectl rollout restart로
# 재부팅해야만 정상화됨, 실제로 겪음). 순서를 여기서 강제해두면 매일 아침 이 수동 재시작이 필요 없음.
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

# GatewayClass 싱글턴 — 원래 module.gateway_api_crds의 Helm 차트 안에 같이 있었는데(CRD와 묶어서
# "생성은 controller보다 먼저"를 보장하려고), 2026-08-22에 여기로 분리함. 이유: GatewayClass는
# ALB Controller가 자기 전용 finalizer(gateway.k8s.aws/gatewayclass)를 붙이는 오브젝트라, 파괴할
# 땐 그 반대(GatewayClass가 컨트롤러보다 "먼저" 없어져야 finalizer가 정상 처리됨)가 필요함 — CRD
# 차트에 같이 있으면 이 둘을 동시에 만족시킬 수 없어서, 실제로 alb_controller가 먼저 destroy된 뒤
# GatewayClass의 finalizer를 처리해줄 컨트롤러가 없어 `helm_release.gateway_api_crds`의 destroy가
# 영원히 멈추는 사고를 겪음(CLAUDE_LLM_WIKI troubleshooting/
# ebs-csi-addon-destroyed-before-dev-datastore-pvc 참고 — 같은 클래스의 문제).
#
# depends_on을 CRD 쪽과 반대로(module.alb_controller) 걸면: 생성은 crds→alb_controller→
# gateway_class 순서(문제없음, GatewayClass는 컨트롤러가 이미 있어야 실제로 쓰이니 오히려 자연스러움),
# 파괴는 그 역순(gateway_class 먼저, 그다음 alb_controller, 마지막에 crds)이 되어 위 문제가
# 원천적으로 안 생김.
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

# Gateway API — prod 실제 컷오버(Ingress 완전 대체). prod는 아직 실서비스 오픈 전이라(2026-08-20
# 기준) release와 함께 한 번에 진행했었는데, 같은 날 후속으로 release(dev.jun979.click)는
# "개발 서버는 관리자만 들어가야 한다"는 결정에 따라 공개 ALB에서 admin Gateway
# (module.gateway_api_admin)로 옮기고 여기서는 빠짐 — 그래서 for_each가 prod만 남음.
# module.gateway_api_crds와 반대로, 이 모듈은 module.alb_controller "다음"에 있어야 한다(그
# 컨트롤러 자신의 Helm 차트가 LoadBalancerConfiguration/TargetGroupConfiguration CRD를 제공하기
# 때문 — modules/addons/gateway-api-crds/main.tf 주석 참고). alloy-faro Service를
# cross-namespace로 참조하므로 module.gateway_api_faro(ReferenceGrant)에도 의존.
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

# alloy-faro(monitoring 네임스페이스)를 release/prod의 HTTPRoute가 cross-namespace로 참조할 수
# 있게 하는 ReferenceGrant + TargetGroupConfiguration — release/prod가 같은 Service를 공유해서
# env별 module.gateway_api_app/gateway_api_admin 인스턴스에 안 넣고 여기 한 번만 만든다
# (modules/addons/gateway-api-faro/chart/Chart.yaml 참고). release가 이제 gateway_api_admin
# 쪽으로 옮겨가도 namespace 목록(local.ingress_config 전체 키)은 그대로 release/prod 둘 다 필요.
module "gateway_api_faro" {
  source = "../modules/addons/gateway-api/faro"

  allowed_namespaces = [for k in keys(local.ingress_config) : kubernetes_namespace.qket[k].metadata[0].name]

  # module.monitoring — 이 모듈의 차트가 ReferenceGrant를 "monitoring" 네임스페이스(alloy-faro
  # Service가 있는 곳)에 만드는데, 그 네임스페이스 자체를 module.monitoring이 만들어서 먼저
  # 끝나야 함(2026-08-21 실제로 "namespaces monitoring not found"로 겪음).
  depends_on = [module.alb_controller, module.gateway_api_crds, module.monitoring, kubernetes_namespace.qket]
}

# 관리 도구(Grafana/ArgoCD) + dev(release) 공유 admin Gateway — admin-ingress.tf의
# kubernetes_ingress_v1.grafana/argocd를 대체하고, dev.jun979.click도 여기로 옮겨서 팀원 IP
# 허용목록(var.admin_allowed_cidrs, variables.tf)을 셋 다 공유하게 함. 인증서는 전부
# 03_registry가 만든 걸 remote_state로 읽어씀(위 ingress_config 주석 참고).
# module.gateway_api_faro 이후에 있어야 함(dev의 /collect 라우팅이 그 ReferenceGrant를 씀).
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

# Cluster Autoscaler — 2026-08-20 Karpenter 마이그레이션 3단계로 완전히 제거함(방식 A: 전면
# 교체). 이전에는 EKS 노드그룹(modules/eks)의 desired_size를 min~max(01_infrastructure/
# variables.tf) 사이에서 자동 조절했으나, 이제 module.karpenter가 그 역할을 전담.
# 3-1에서 helm_release만 먼저 destroy(2026-08-20)로 검증 후, 이 단계에서 모듈 전체 제거.
# 과거 코드는 git history(이 커밋 이전)에서 확인 가능.

# Karpenter — cluster-autoscaler를 대체하는 노드 오토스케일러. 1단계(IAM/SQS) → 2단계(Helm/
# EC2NodeClass/NodePool) → 3단계(cluster-autoscaler 제거, 2026-08-20 진행 중)까지 완료.
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

# 오버프로비저닝("풍선 파드") — Karpenter의 노드 생성 리드타임 때문에 KEDA 스케일업 순간
# 파드가 Pending → 노드 생성 → 한 노드에 몰려서 뜨는 문제(CLAUDE_LLM_WIKI troubleshooting/
# backend-cold-start-cpu-contention-during-rollout 참고)를, "노드를 미리 여유로 예약해둠"으로
# 해결. prod의 오픈런 트래픽 패턴을 겨냥해 qket-prod에 둠 — preemption 자체는 namespace를
# 안 가리므로 release가 스케일업할 때도 이 여유를 opportunistic하게 같이 쓸 수 있음(부작용
# 아니라 덤). 사이징은 실제 노드(kubectl get nodes) t3.large의 allocatable(cpu 1930m,
# mem ~7080Mi) 실측 기준.
module "overprovisioning" {
  source = "../modules/addons/overprovisioning"

  namespace = kubernetes_namespace.qket["prod"].metadata[0].name

  depends_on = [module.karpenter, kubernetes_namespace.qket]
}

# vpc-cni를 EKS 관리형 addon으로 등록 — NetworkPolicy를 실제로 집행시키기 위함.
#
# 배경(2026-08-28 확인): 클러스터엔 vpc-cni(aws-node 데몬셋)가 이미 떠있고 NETWORK_POLICY_
# ENFORCING_MODE=standard까지 켜져 있어서 "정책을 막는 놈"(aws-eks-nodeagent)은 있는데, K8s
# NetworkPolicy 오브젝트를 읽어서 그 놈이 이해하는 형태(PolicyEndpoint CR)로 번역해주는
# 컨트롤러(amazon-network-policy-controller-k8s)가 없어서 실질적으로 아무것도 안 막고 있었음
# (kubectl get policyendpoints -A → No resources found, curl로 실제 무방비 통과까지 확인).
# 이 컨트롤러는 vpc-cni addon의 configuration_values로 enableNetworkPolicy를 켜야 같이 설치됨.
#
# ⚠️ 이 addon을 적용하기 전에 CD 레포의 NetworkPolicy에 ALB 소스 CIDR(ipBlock)이 먼저 반영돼
# 있어야 함 — 안 그러면 이 순간부터 ALB→backend 직접 연결(API 요청 8080 + 헬스체크 8081)이
# 전부 막혀서 즉시 전체 다운으로 이어짐(CLAUDE_LLM_WIKI troubleshooting 참고, 2026-08-28).
#
# resolve_conflicts_on_create = OVERWRITE인 이유: vpc-cni가 이미 self-managed로 떠있는 상태라
# "이미 존재함" 충돌이 나는데, 기존 설치를 그대로 흡수(adopt)해서 관리형으로 전환하기 위함
# (ebs_csi와 동일한 이유).
resource "aws_eks_addon" "vpc_cni" {
  cluster_name = data.terraform_remote_state.infrastructure.outputs.eks_cluster_name
  addon_name   = "vpc-cni"

  configuration_values = jsonencode({
    enableNetworkPolicy = "true"
  })

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
}

# EBS CSI 드라이버 addon — 원래 01_infrastructure(modules/eks)에 있었는데, 2026-08-21에 여기로
# 옮김. 이유: 이 addon은 실제로 ACTIVE가 되려면 컨트롤러/데몬셋 파드가 뜰 노드가 있어야 하는데,
# 01_infrastructure는 관리형 노드그룹이 없어져서(3단계, 노드는 전부 Karpenter가 만듦) 그 시점엔
# 노드가 0개라 파드가 영원히 Pending → addon이 DEGRADED로 20분 타임아웃(실제로 겪음). Karpenter
# 다음(=최소 1개 노드가 뜬 뒤)에 여기서 설치하면 이 문제가 없음.
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

# ExternalDNS — ALB Controller가 만든 ALB의 주소를 Route53에 자동으로 연결
#
# depends_on = [module.alb_controller] — helm_release.argocd와 같은 이유(위 주석 참고): 이 차트도
# 자기 Service를 만들 수 있어서, ALB Controller의 webhook이 아직 준비 안 된 타이밍에 걸리면
# 같은 "no endpoints available" 에러가 날 수 있음. 방어적으로 동일하게 걸어둠.
module "external_dns" {
  source = "../modules/addons/external-dns"

  project_name = var.project_name
  aws_region   = var.aws_region

  oidc_provider_arn = data.terraform_remote_state.infrastructure.outputs.oidc_provider_arn
  oidc_provider_url = data.terraform_remote_state.infrastructure.outputs.oidc_provider_url

  hosted_zone_id = "Z0111999JD2RHOSHTM8A" # jun979.click
  domain_filter  = "jun979.click"

  # module.gateway_api_crds가 먼저 있어야 함 — sources에 gateway-httproute를 켜놨는데
  # (modules/addons/external-dns/main.tf 참고) 그 CRD가 없으면 external-dns 파드가 크래시루프 남.
  depends_on = [module.alb_controller, module.gateway_api_crds]
}

# 모니터링 스택(Prometheus/Grafana/Alertmanager) — wiki decisions/2026-08-11-monitoring-stack-design 참고.
#
# depends_on = [module.alb_controller] — external_dns와 같은 이유(위 주석 참고): Prometheus/
# Grafana/Alertmanager/node-exporter가 전부 자기 Service를 만들어서 같은 webhook 레이스 위험이 있음.
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

# 로그 저장소(Loki) — 프론트(Next.js SSR/미들웨어)·백엔드(Spring Boot) 파드가 찍는 로그를
# 모아서 위 Grafana에서 같이 볼 수 있게 함. monitoring 모듈과 같은 네임스페이스(monitoring)에 설치.
module "loki" {
  source = "../modules/addons/loki"

  project_name = var.project_name
  aws_region   = var.aws_region

  oidc_provider_arn = data.terraform_remote_state.infrastructure.outputs.oidc_provider_arn
  oidc_provider_url = data.terraform_remote_state.infrastructure.outputs.oidc_provider_url

  depends_on = [module.alb_controller]
}

# 노드마다 떠서 파드 로그를 Loki로 전송 — module.loki가 먼저 만들어져 있어야 보낼 곳이 있음.
module "promtail" {
  source = "../modules/addons/promtail"

  depends_on = [module.loki]
}

# 브라우저(프론트엔드 Faro SDK)가 보내는 클릭/에러 이벤트를 받아서 Loki로 전달.
module "alloy_faro" {
  source = "../modules/addons/alloy-faro"

  depends_on = [module.loki]
}


# Grafana 대시보드 ConfigMap은 modules/addons/monitoring으로 옮김(2026-08-21) — 그 모듈이
# 이미 grafana/monitoring 네임스페이스 자체를 담당해서, 부속물인 이 ConfigMap도 거기 두는 게 맞음.

# backend API 지표(응답시간, 요청수, HikariCP, JVM 등)를 Prometheus가 스크랩하게 등록.
# wiki decisions/2026-08-11-monitoring-stack-design 문서상 "2차(나중)" 범위였던 앱 레벨 지표 —
# release 환경만 우선 커버.
#
# 2026-08-20: kubernetes_manifest에서 helm_release 기반 모듈로 전환 — kubernetes_manifest는
# plan 시점에 ServiceMonitor CRD가 클러스터에 이미 있는지 확인하는데, 02_k8s-addon이 매일 밤
# destroy→재생성되는 구조상 이게 매번 실패했음(3일 연속 재현, CLAUDE_LLM_WIKI
# troubleshooting/crd-not-yet-installed-on-fresh-apply). helm_release는 이 문제 자체가 없어서
# 매일 아침 `-target=module.monitoring` 선적용 없이도 그냥 apply 한 번으로 끝남. 실제
# ServiceMonitor 내용/포트 관련 주석은 modules/addons/backend-servicemonitor/chart/templates/
# servicemonitor.yaml 참고.
module "backend_servicemonitor" {
  source = "../modules/addons/backend-servicemonitor"

  depends_on = [module.monitoring]
}

# KEDA — backend 오토스케일링용. 실제 스케일 규칙(ScaledObject)은 CD 레포(Helm)에 있고,
# 여기는 그 규칙을 처리할 컨트롤러(엔진)만 설치. modules/addons/keda/main.tf 주석 참고.
module "keda" {
  source = "../modules/addons/keda"

  depends_on = [module.alb_controller]
}

# metrics-server — KEDA(cpu trigger)가 만드는 HPA가 CPU 사용률을 읽으려면 이게 반드시 있어야 함.
# 이게 없으면 HPA가 "unknown"으로 멈춰서 ScaledObject를 아무리 만들어도 절대 스케일 안 됨 —
# 2026-08-13 부하테스트에서 4개 replica가 끝까지 안 늘어난 원인이 이거였음(modules/addons/metrics-server 참고).
module "metrics_server" {
  source = "../modules/addons/metrics-server"

  depends_on = [module.alb_controller]
}

# 환경별 도메인/인증서 설정 — 예전엔 이 값들로 kubernetes_ingress_v1(app_ingress_backend/
# app_ingress_frontend/faro_ingress) 3개를 만들었는데, 2026-08-20 Gateway API로 완전히
# 대체하면서 그 3개 리소스는 삭제함 — 지금은 module.gateway_api_app(위)이 이 값을 그대로 받아서
# Gateway/HTTPRoute를 만듦. host는 CD/helm/values.yaml에도 그대로 남아있음(backend의
# APP_BASE_URL이 참조) — 두 군데 다 "이 환경의 프론트 도메인"이라는 같은 사실을 나타내는 것뿐이라
# 굳이 하나로 합칠 필요는 없음.
#
# 인증서는 02_k8s-addon(매일 밤 destroy/재생성)이 아니라 03_registry(영구)에서 만들고
# remote_state로 읽음 — 여기 두면 매일 아침 DNS 검증을 새로 거쳐야 해서(수 분간 HTTPS 불가) 안 됨.
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

# 개발용 스테이트풀셋 MySQL/Redis — release 환경의 RDS/ElastiCache를 완전히 대체. (비용/관리 부담 때문)
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

  # depends_on에 aws_eks_addon.ebs_csi 추가 이유(2026-08-22): 이 모듈의 PV가 CSI 드라이버
  # "ebs.csi.aws.com"을 문자열로만 참조해서 Terraform이 이 둘 사이에 실제 의존 관계를 전혀
  # 모르고 있었음 — 그래서 destroy 순서가 정해진 게 없어서, 어느 날 밤 destroy가 하필
  # ebs_csi addon을 dev_datastore의 PV/PVC보다 먼저 지워버림. CSI 컨트롤러가 이미 사라진
  # 상태라 PVC/PV가 finalizer(external-attacher/ebs-csi-aws-com 등)를 영원히 못 떼서
  # `terraform destroy`가 몇 시간이고 "Still destroying..."만 반복하며 멈춤(실제로 겪음,
  # kubectl로 finalizer 강제 제거해서 겨우 풀었음 — Retain 정책이라 실제 EBS 볼륨은 안전했음).
  # depends_on을 걸면 destroy는 역순(dev_datastore 먼저, ebs_csi 나중)으로 자동 보장됨 —
  # create 쪽도 CSI 드라이버가 먼저 준비된 뒤에 PV/파드가 뜨는 게 되어 오히려 더 안전해짐.
  depends_on = [kubernetes_namespace.qket, aws_eks_addon.ebs_csi]
}
