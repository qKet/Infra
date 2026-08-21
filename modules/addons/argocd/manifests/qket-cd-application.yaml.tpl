apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: ${app_name}
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
  # ArgoCD Notifications 구독 — helm_release.this(main.tf)에 정의된 트리거/이메일 서비스를
  # 이 Application에 연결. 여러 명 추가할 땐 콤마로 구분: "a@x.com,b@x.com"
  annotations:
    notifications.argoproj.io/subscribe.on-out-of-sync.email: "zubene1013@gmail.com,chae_young813@naver.com,nyj16907@gmail.com,ojoj4055@gmail.com,pdu0415976@gmail.com"
    notifications.argoproj.io/subscribe.on-sync-failed.email: "zubene1013@gmail.com,chae_young813@naver.com,nyj16907@gmail.com,ojoj4055@gmail.com,pdu0415976@gmail.com"
    notifications.argoproj.io/subscribe.on-health-degraded.email: "zubene1013@gmail.com,chae_young813@naver.com,nyj16907@gmail.com,ojoj4055@gmail.com,pdu0415976@gmail.com"
spec:
  project: default
  source:
    repoURL: https://github.com/qKet/CD.git
    targetRevision: main
    path: helm
    helm:
      valueFiles:
%{ for f in value_files ~}
        - ${f}
%{ endfor ~}
  destination:
    server: https://kubernetes.default.svc
    namespace: ${namespace}
  # KEDA(ScaledObject, CD 레포)가 qket-backend/qket-frontend Deployment의 replicas를 실시간으로
  # 바꾸는데, ArgoCD가 sync할 때마다 git에 적힌 고정값(*.replicas)으로 되돌리면 KEDA랑 계속
  # 충돌함(scale-up 해놓으면 다음 sync에 다시 줄어듦). replicas 필드만 ArgoCD가 diff/sync 대상에서
  # 빼서, "몇 개로 띄울지"는 KEDA한테 완전히 맡김 — ArgoCD 공식 문서에 나온 HPA/KEDA 연동 시
  # 권장 패턴. (2026-08-18: frontend에도 KEDA 적용하며 추가)
  ignoreDifferences:
    - group: apps
      kind: Deployment
      name: qket-backend
      namespace: ${namespace}
      jsonPointers:
        - /spec/replicas
    - group: apps
      kind: Deployment
      name: qket-frontend
      namespace: ${namespace}
      jsonPointers:
        - /spec/replicas
  # automated(prune/selfHeal)는 일부러 안 씀 — 배포는 수동 Sync로 직접 트리거하는 방식을 유지하기로 함.
  # 대신 재시도/네임스페이스/finalizer 같은, 수동 sync와 무관하게 유용한 설정은 그대로 둠.
  syncPolicy:
    syncOptions:
      # 네임스페이스는 01_infrastructure가 이미 만듦 — ArgoCD가 중복 소유하지 않게
      - CreateNamespace=false
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
