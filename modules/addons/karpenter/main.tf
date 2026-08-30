# Karpenter — 컨트롤러 Helm 설치 + EC2NodeClass/NodePool. iam.tf/sqs.tf가 만든 Role/Instance
# Profile/인터럽션 큐를 여기서 실제로 연결.

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

  # 차트 기본값은 nodeAffinity(자기가 만든 노드엔 못 올라감)를 requiredDuringScheduling(강제)로
  # 건다 — 관리형 노드그룹을 제거하고 나니 올라갈 노드가 하나도 없어 컨트롤러가 Pending에
  # 멈추는 데드락 발생. required를 preferred로 완화해 데드락만 제거.
  values = [
    yamlencode({
      replicas = 1
      affinity = {
        nodeAffinity = {
          # required 키를 null로 지정해야 Helm이 병합 결과에서 삭제함(preferred만 추가하면
          # 차트 기본값의 required가 그대로 남음).
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
# 서브넷/보안그룹은 태그 기반 discovery 대신 기존 노드그룹과 동일한 리소스를 ID로 직접 지정.
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
# 용량은 온디맨드만(Redis 세션 등 상태 있는 서비스가 있어 스팟 회수 리스크 배제).
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
