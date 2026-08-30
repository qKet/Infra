# Gateway API core CRD(kubernetes-sigs/gateway-api v1.6.1, standard channel)를 helm_release로
# 설치한다. GatewayClass 싱글턴은 여기 안 두고 02_k8s-addon/main.tf의 별도 kubectl_manifest로
# 분리함 — GatewayClass는 ALB Controller의 finalizer가 붙어서, 이 차트와 묶으면 destroy 순서가
# 꼬여 finalizer가 안 풀림.
#
# kubernetes_manifest/kubectl_manifest 대신 helm_release를 쓰는 이유: 그 리소스들은 plan
# 시점에 CRD가 클러스터에 이미 있는지 확인하는데, 02_k8s-addon이 매일 밤 destroy→재생성되는
# 구조상 그 확인이 매번 실패함. helm_release는 plan 단계에서 차트 내용을 확인하지 않아 문제없음.
#
# 이 모듈은 다른 모듈에 depends_on을 걸지 않고, 반대로 module.alb_controller 쪽에서 이 모듈을
# 기다린다 — ALB Controller가 부팅 시 CRD 존재 여부로 ALBGatewayAPI 기능을 켤지 정하기 때문
# (없으면 비활성 상태로 굳어서 수동 재시작이 필요해짐).
#
# 파일럿 오브젝트(Gateway/HTTPRoute 등, release 테스트용)는 modules/addons/gateway-api/pilot에
# 별도 — 그건 반대로 alb_controller 이후에 있어야 해서 분리함.
resource "helm_release" "gateway_api_crds" {
  name      = "gateway-api-crds"
  chart     = "${path.module}/chart"
  namespace = "kube-system"
}
