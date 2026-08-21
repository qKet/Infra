# Gateway API core CRD(kubernetes-sigs/gateway-api v1.6.1, standard channel) + GatewayClass
# 싱글턴을 "같은 Helm 차트" 안에 묶어서 helm_release 하나로 설치한다 (chart/ 참고).
#
# 왜 kubernetes_manifest/kubectl_manifest 대신 이 방식을 쓰는지: 그 두 리소스 타입은
# terraform plan 시점에 해당 kind의 CRD가 클러스터에 이미 등록돼 있는지 API 서버에 물어봐서
# 확인하는데, 02_k8s-addon이 매일 밤 통째로 destroy→재생성되는 이 프로젝트 구조상 그 확인이
# 매번 실패한다(ServiceMonitor/SecretStore로 이미 3일 연속 겪음 — CLAUDE_LLM_WIKI의
# troubleshooting/crd-not-yet-installed-on-fresh-apply 참고. depends_on을 걸어도 apply *순서*만
# 보장할 뿐 plan이 스키마를 조회하는 시점 자체는 못 늦춰줘서 소용없음).
#
# helm_release는 테라폼 입장에서 "이 차트를 이 값으로 설치해라"는 선언 하나일 뿐이라 plan 단계에서
# 차트 내용물의 kind/스키마를 전혀 확인하지 않고, 실제 적용은 apply 시 Helm 클라이언트가 처리한다.
# 그리고 Helm은 자기 차트 안의 crds/ 폴더를 templates/보다 항상 먼저 설치하는 걸 스스로 보장하므로
# (Helm 자체 동작, 같은 차트 안에서는 예외 없음), CRD와 그걸 쓰는 GatewayClass를 같은 차트에
# 넣어두면 이 문제 자체가 원천적으로 발생하지 않는다.
#
# 이 모듈은 의도적으로 다른 모듈에 depends_on을 걸지 않는다(02_k8s-addon/main.tf에서 호출부도
# 마찬가지) — 오히려 반대로 module.alb_controller가 "이 모듈 다음에" 설치되도록
# module.alb_controller 쪽에 depends_on을 건다. 이유: AWS Load Balancer Controller는 부팅
# 시점에 딱 한 번 Gateway API CRD 존재 여부를 확인해서 ALBGatewayAPI 기능을 켤지 말지 정하는데
# (2026-08-20 실제로 겪음 — "Disabling ALBGatewayAPI: missing required CRDs" 로그를 남기고, 그
# 파드가 살아있는 동안 계속 비활성 상태로 남아서 kubectl rollout restart로 재부팅해야만 정상화됨),
# CRD가 컨트롤러보다 "먼저" 있어야 매일 아침 재기동될 때마다 이 수동 재시작이 필요 없다.
#
# GatewayClass/Gateway/HTTPRoute/LoadBalancerConfiguration/TargetGroupConfiguration을 실제로
# "쓰는" 파일럿 오브젝트(release 환경 테스트 호스트네임)는 별도 모듈
# modules/addons/gateway-api-pilot에 있다 — 그건 반대로 module.alb_controller "이후"에 있어야
# 하기 때문에 이 모듈과 분리했다(alb_controller의 LoadBalancerConfiguration/TargetGroupConfiguration
# CRD를 그쪽이 제공하고, GatewayClass는 이쪽이 제공 — 순서 요구사항이 서로 반대라 하나로 합칠 수
# 없었음).
resource "helm_release" "gateway_api_crds" {
  name      = "gateway-api-crds"
  chart     = "${path.module}/chart"
  namespace = "kube-system"
}
