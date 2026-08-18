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
          finalizers = ["resources-finalizer.argocd.argoproj.io"]
          # ArgoCD Notifications 구독 — 02_k8s-addon(helm_release.argocd)에 정의된 트리거/이메일
          # 서비스를 이 Application에 연결. 여러 명 추가할 땐 콤마로 구분: "a@x.com,b@x.com"
          annotations = {
            "notifications.argoproj.io/subscribe.on-out-of-sync.email"     = "zubene1013@gmail.com,chae_young813@naver.com,nyj16907@gmail.com,ojoj4055@gmail.com,pdu0415976@gmail.com"
            "notifications.argoproj.io/subscribe.on-sync-failed.email"     = "zubene1013@gmail.com,chae_young813@naver.com,nyj16907@gmail.com,ojoj4055@gmail.com,pdu0415976@gmail.com"
            "notifications.argoproj.io/subscribe.on-health-degraded.email" = "zubene1013@gmail.com,chae_young813@naver.com,nyj16907@gmail.com,ojoj4055@gmail.com,pdu0415976@gmail.com"
          }
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
