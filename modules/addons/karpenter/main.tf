# Karpenter 마이그레이션 2단계 — 컨트롤러 Helm 설치 + EC2NodeClass/NodePool.
# 1단계(iam.tf/sqs.tf)에서 만든 Controller Role/Node Role/Instance Profile/인터럽션 큐를 여기서 실제로 연결함.
# 이 단계까지 적용돼도 cluster-autoscaler는 그대로 두고 노드그룹도 안 건드림 — Karpenter가
# "쓸 수 있는" 상태만 만드는 것. 실제로 Karpenter가 노드를 만들기 시작하는 건 NodePool이
# 생기고 스케줄링 안 되는 파드가 생겼을 때부터라, 지금 당장 노드가 추가로 뜨진 않음.
# cluster-autoscaler 제거/노드그룹 축소는 4단계에서 별도로 진행.

resource "helm_release" "karpenter" {
  name             = "karpenter"
  repository       = "oci://public.ecr.aws/karpenter"
  chart            = "karpenter"
  version          = var.karpenter_chart_version
  namespace        = "kube-system"
  create_namespace = false

  set {
    name  = "settings.clusterName"
    value = var.cluster_name
  }

  set {
    name  = "settings.interruptionQueue"
    value = aws_sqs_queue.karpenter_interruption.name
  }

  set {
    name  = "serviceAccount.name"
    value = "karpenter"
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.karpenter_controller.arn
  }

  # Karpenter 차트 기본값은 nodeAffinity(karpenter.sh/nodepool DoesNotExist, "자기가 만든 노드엔
  # 못 올라감")/podAntiAffinity(호스트 분산)/topologySpreadConstraints(AZ 분산)를 전부
  # requiredDuringScheduling(강제)로 건다. 2026-08-20 관리형 노드그룹을 완전히 제거하고 나니
  # (3단계), Karpenter가 올라갈 수 있는 "자기가 안 만든" 노드가 하나도 안 남아 컨트롤러 자체가
  # Pending에 멈추는 완전한 데드락 발생(신규 노드 프로비저닝 불가 → 재시작될 때마다 재발).
  # affinity를 통째로 비우는 시도(affinity={})는 Helm 템플릿이 "빈 값=미설정"으로 보고 기본값
  # (강제 규칙)으로 그대로 폴백해서 효과가 없었음(2026-08-20 실측) — 대신 required를 preferred로
  # 바꿔서 "가능하면 분산, 안 되면 그냥 배치"로 완화. 분산 의도 자체는 유지하면서 데드락만 제거.
  values = [
    yamlencode({
      replicas = 1
      affinity = {
        nodeAffinity = {
          # Helm의 values 병합은 "덮어쓰기"가 아니라 "병합"이라, preferred만 추가하면 차트 기본값의
          # required는 그대로 남아있음(2026-08-20 첫 시도 실측) — required 키를 명시적으로 null로
          # 지정해야 Helm이 병합 결과에서 그 키 자체를 삭제함(Helm 공식 지원 동작).
          requiredDuringSchedulingIgnoredDuringExecution = null
          preferredDuringSchedulingIgnoredDuringExecution = [
            {
              weight = 1
              preference = {
                matchExpressions = [
                  { key = "karpenter.sh/nodepool", operator = "DoesNotExist" }
                ]
              }
            }
          ]
        }
        podAntiAffinity = {
          preferredDuringSchedulingIgnoredDuringExecution = [
            {
              weight = 1
              podAffinityTerm = {
                labelSelector = {
                  matchLabels = {
                    "app.kubernetes.io/instance" = "karpenter"
                    "app.kubernetes.io/name"     = "karpenter"
                  }
                }
                topologyKey = "kubernetes.io/hostname"
              }
            }
          ]
        }
      }
      topologySpreadConstraints = [
        {
          maxSkew           = 1
          topologyKey       = "topology.kubernetes.io/zone"
          whenUnsatisfiable = "ScheduleAnyway"
          labelSelector = {
            matchLabels = {
              "app.kubernetes.io/instance" = "karpenter"
              "app.kubernetes.io/name"     = "karpenter"
            }
          }
        }
      ]
    })
  ]

  # cluster-autoscaler와 동일 계열 addon이라 동일 톨러레이션/우선순위 정책 적용 안 함 —
  # 차트 기본값(system-cluster-critical)을 그대로 씀.

  depends_on = [
    aws_iam_role_policy.karpenter_controller,
    aws_eks_access_entry.karpenter_node,
    aws_sqs_queue_policy.karpenter_interruption,
  ]
}

# ── EC2NodeClass — Karpenter가 새로 띄우는 EC2의 AMI/네트워크/역할 정의 ──
# 서브넷/보안그룹은 태그 기반 discovery 대신 기존 노드그룹과 동일한 리소스를 ID로 직접 지정
# (00_network/modules/eks에 karpenter.sh/discovery 태그를 새로 추가할 필요 없이 재사용).
resource "kubectl_manifest" "karpenter_node_class" {
  yaml_body = yamlencode({
    apiVersion = "karpenter.k8s.aws/v1"
    kind       = "EC2NodeClass"
    metadata = {
      name = "${var.project_name}-default"
    }
    spec = {
      role = aws_iam_role.karpenter_node.name

      amiSelectorTerms = [
        { alias = "al2023@latest" }
      ]

      subnetSelectorTerms = [
        for id in var.node_subnet_ids : { id = id }
      ]

      securityGroupSelectorTerms = [
        { id = var.cluster_security_group_id }
      ]
    }
  })

  depends_on = [helm_release.karpenter]
}

# ── NodePool — 인스턴스 타입/용량 종류/스케일다운 정책 정의 ──
# 2026-08-20 결정: 인스턴스 타입은 t3.medium~xlarge로 넓게(워크로드 크기에 맞춰 최적화),
# 용량은 온디맨드만(Redis 세션 등 상태 있는 서비스가 있어 스팟 회수 리스크 배제), 스케일다운은
# WhenEmptyOrUnderutilized(비용 최적화 효과를 정량적으로 보여주기 위함 — 야간 멘토링 조언).
resource "kubectl_manifest" "karpenter_node_pool" {
  yaml_body = yamlencode({
    apiVersion = "karpenter.sh/v1"
    kind       = "NodePool"
    metadata = {
      name = "${var.project_name}-default"
    }
    spec = {
      template = {
        spec = {
          nodeClassRef = {
            group = "karpenter.k8s.aws"
            kind  = "EC2NodeClass"
            name  = "${var.project_name}-default"
          }

          requirements = [
            {
              key      = "node.kubernetes.io/instance-type"
              operator = "In"
              values   = var.node_instance_types
            },
            {
              key      = "karpenter.sh/capacity-type"
              operator = "In"
              values   = var.capacity_types
            },
            {
              key      = "kubernetes.io/arch"
              operator = "In"
              values   = ["amd64"]
            },
          ]
        }
      }

      disruption = {
        consolidationPolicy = var.consolidation_policy
        # underutilized 판단 후 실제로 통합을 실행하기까지 기다리는 시간 — 너무 짧으면 트래픽이
        # 잠깐 튈 때도 자꾸 재배치가 일어나서 1분으로 여유를 둠.
        consolidateAfter = "1m"
      }
    }
  })

  depends_on = [kubectl_manifest.karpenter_node_class]
}
