# Grafana Alloy를 "Faro 수신기" 모드로 설치 — 브라우저(Faro Web SDK)가 클릭/에러/페이지이동
# 이벤트를 HTTP로 직접 이 파드에 보내면, Alloy가 그걸 받아서 Loki로 로그 형태로 전달함.
# (Promtail이 "서버 파드의 stdout"을 긁어오는 거라면, 이건 "사용자 브라우저"가 직접 보내는 이벤트를 받는 창구)
#
# 브라우저(외부)에서 접근해야 하므로 02_k8s-addon의 ALB Ingress에 경로를 하나 추가해서 노출함
# (kubernetes_ingress_v1.faro 참고).
resource "helm_release" "alloy_faro" {
  name             = "alloy-faro"
  repository       = "https://grafana.github.io/helm-charts"
  chart            = "alloy"
  namespace        = "monitoring"
  create_namespace = true
  version          = "~> 0.12"

  values = [
    yamlencode({
      alloy = {
        # Alloy 설정 언어(river)로 "Faro 수신기 → Loki로 전달" 파이프라인을 정의.
        # faro.receiver가 12347 포트로 HTTP 요청(브라우저가 보내는 이벤트)을 받아서,
        # 그 안의 로그성 데이터를 loki.write로 넘겨줌.
        configMap = {
          content = <<-EOT
            faro.receiver "default" {
              server {
                listen_address = "0.0.0.0"
                listen_port    = 12347
                cors_allowed_origins = ["*"]
              }

              // 2026-08-19: 이게 없으면 Loki가 "at least one label pair is required per
              // stream"으로 push를 전부 400 거부함 — 브라우저->Alloy는 202로 성공해도
              // Alloy->Loki 단계에서 계속 실패해서 실제로는 로그가 하나도 안 쌓이고 있었음.
              // job/service_name 라벨을 붙여서 대시보드/Explore에서 이 값으로 걸러볼 수 있게 함.
              // (River 설정 언어는 '#' 주석을 지원 안 함 — '//'만 지원, 이거 때문에 한 번 CrashLoop 남)
              extra_log_labels = {
                job          = "faro",
                service_name = "qket-frontend",
              }

              output {
                logs = [loki.write.default.receiver]
              }
            }

            loki.write "default" {
              endpoint {
                url = "http://loki.monitoring.svc.cluster.local:3100/loki/api/v1/push"
              }
            }
          EOT
        }

        # 2026-08-19: 원래 최상위 service.ports로 12347을 열려고 했는데, 이 차트엔
        # 그런 키가 없음(helm show values로 확인 — service 블록엔 enabled/type/clusterIP 등만
        # 있고 ports는 없음). 대신 alloy.extraPorts가 Container와 Service 양쪽에 포트를
        # 같이 추가해주는 정식 키 — 차트 기본값 주석에 이 faro 포트 예시가 그대로 있었음.
        extraPorts = [
          {
            name        = "faro"
            port        = 12347
            targetPort  = 12347
            protocol    = "TCP"
            appProtocol = "h2c"
          }
        ]
      }

      controller = {
        type     = "deployment"
        replicas = 1
      }

      service = {
        enabled = true
        type    = "ClusterIP"
      }
    })
  ]
}
