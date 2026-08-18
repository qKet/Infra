# ArgoCD Application 등록 — 예전엔 Infra/argocd/qket-cd-app.yaml을 사람이 매번 수동으로
# `kubectl apply`해야 했음(02_k8s-addon이 매일 밤 destroy→아침 재생성될 때마다 Application
# 등록이 같이 날아가서, 안 하면 ArgoCD가 "텅 비어있는" 상태로 뜸). 이제 이 root를 apply하면
# 자동으로 같이 생성됨 — 더 이상 사람이 따로 기억해서 실행할 필요 없음.
#
# CD 레포가 raw manifest(release/) 구조에서 Helm 차트(helm/) 구조로 바뀌면서 path도 같이 고침 —
# "release"라는 경로는 이제 CD 레포에 없음(release(backup)/으로 이름이 바뀐 옛날 raw manifest).
# release 환경은 helm/values.yaml 자체가 이미 release 기준 값(namespace: qket-release 등)을
# 직접 담고 있어서 valueFiles를 따로 안 줘도 됨 — ArgoCD의 Helm source가 기본으로 values.yaml을 씀.
resource "kubectl_manifest" "qket_cd_app" {
  yaml_body = yamlencode({
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "qket-cd"
      namespace = "argocd"
      # Application 자체를 지울 때 그 밑에서 관리하던 리소스(Deployment/Service/Ingress 등)까지
      # cascade로 같이 지워지게 함 — 안 하면 Application만 사라지고 실제 리소스는 고아로 남음
      # (ALB/SG 고아 사고와 같은 계열의 문제를 ArgoCD 레벨에서도 막기 위함).
      finalizers = ["resources-finalizer.argocd.argoproj.io"]
    }
    spec = {
      project = "default"
      source = {
        repoURL        = "https://github.com/qKet/CD.git"
        targetRevision = "main"
        path           = "helm"
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = "qket-release"
      }
      # KEDA(ScaledObject, CD 레포)가 qket-backend/qket-frontend Deployment의 replicas를
      # 실시간으로 바꾸는데, ArgoCD가 sync할 때마다 git에 적힌 고정값(*.replicas)으로 되돌리면
      # KEDA랑 계속 충돌함(scale-up 해놓으면 다음 sync에 다시 줄어듦). replicas 필드만 ArgoCD가
      # diff/sync 대상에서 빼서, "몇 개로 띄울지"는 KEDA한테 완전히 맡김 — ArgoCD 공식 문서에
      # 나온 HPA/KEDA 연동 시 권장 패턴. (2026-08-18: frontend에도 KEDA 적용하며 추가)
      ignoreDifferences = [
        {
          group        = "apps"
          kind         = "Deployment"
          name         = "qket-backend"
          namespace    = "qket-release"
          jsonPointers = ["/spec/replicas"]
        },
        {
          group        = "apps"
          kind         = "Deployment"
          name         = "qket-frontend"
          namespace    = "qket-release"
          jsonPointers = ["/spec/replicas"]
        }
      ]
      # automated(prune/selfHeal)는 일부러 안 씀 — 배포는 수동 Sync로 직접 트리거하는 방식을 유지하기로 함.
      # 대신 재시도/네임스페이스/finalizer 같은, 수동 sync와 무관하게 유용한 설정은 그대로 둠.
      syncPolicy = {
        syncOptions = [
          "CreateNamespace=false" # qket-release 네임스페이스는 01_infrastructure가 이미 만듦 — ArgoCD가 중복 소유하지 않게
        ]
        retry = {
          limit = 5
          backoff = {
            duration    = "5s"
            factor      = 2
            maxDuration = "3m"
          }
        }
      }
    }
  })

  depends_on = [helm_release.argocd]
}
