# Gateway API core CRD(kubernetes-sigs/gateway-api v1.6.1, standard channel)를 helm_release로
# 설치한다 (chart/ 참고).
#
# 2026-08-22: GatewayClass 싱글턴은 원래 이 차트 안에 같이 있었는데, 02_k8s-addon/main.tf의
# 별도 kubectl_manifest로 분리함 — destroy 순서 문제 때문(아래 설명 참고). GatewayClass는
# ALB Controller가 자기 finalizer(gateway.k8s.aws/gatewayclass)를 붙이는데, 이 차트와 같이
# 있으면 "CRD가 컨트롤러보다 먼저 있어야 한다"는 이유로 module.alb_controller가 이 모듈에
# depends_on을 거는 바람에(아래 설명), destroy할 땐 그 반대(컨트롤러가 먼저 사라짐)가 되어
# GatewayClass의 finalizer를 처리해줄 컨트롤러가 이미 없는 상태로 delete를 시도해서
# `helm_release.gateway_api_crds`의 destroy가 영원히 멈추는 사고를 실제로 겪음
# (CLAUDE_LLM_WIKI troubleshooting/ebs-csi-addon-destroyed-before-dev-datastore-pvc의
# "일반화된 패턴"과 같은 클래스). GatewayClass만 따로 빼서 반대 방향(`depends_on =
# [module.alb_controller]`)으로 걸면 생성/파괴 양쪽 다 문제없이 풀림 — 자세한 내용은
# CLAUDE_LLM_WIKI troubleshooting/gatewayclass-alb-controller-destroy-order 참고.
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
#
# 이 모듈은 의도적으로 다른 모듈에 depends_on을 걸지 않는다(02_k8s-addon/main.tf에서 호출부도
# 마찬가지) — 오히려 반대로 module.alb_controller가 "이 모듈 다음에" 설치되도록
# module.alb_controller 쪽에 depends_on을 건다. 이유: AWS Load Balancer Controller는 부팅
# 시점에 딱 한 번 Gateway API CRD 존재 여부를 확인해서 ALBGatewayAPI 기능을 켤지 말지 정하는데
# (2026-08-20 실제로 겪음 — "Disabling ALBGatewayAPI: missing required CRDs" 로그를 남기고, 그
# 파드가 살아있는 동안 계속 비활성 상태로 남아서 kubectl rollout restart로 재부팅해야만 정상화됨),
# CRD가 컨트롤러보다 "먼저" 있어야 매일 아침 재기동될 때마다 이 수동 재시작이 필요 없다.
#
# Gateway/HTTPRoute/LoadBalancerConfiguration/TargetGroupConfiguration을 실제로 "쓰는" 파일럿
# 오브젝트(release 환경 테스트 호스트네임)는 별도 모듈 modules/addons/gateway-api/pilot에 있다 —
# 그건 반대로 module.alb_controller "이후"에 있어야 하기 때문에 이 모듈과 분리했다
# (alb_controller의 LoadBalancerConfiguration/TargetGroupConfiguration CRD를 그쪽이 제공).
resource "helm_release" "gateway_api_crds" {
  name      = "gateway-api-crds"
  chart     = "${path.module}/chart"
  namespace = "kube-system"
}
