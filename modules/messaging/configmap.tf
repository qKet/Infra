# SQS 큐 URL을 백엔드 Pod에 전달 — modules/storage/configmap.tf와 동일한 패턴(값을 만든 Terraform이
# 직접 ConfigMap으로 발행). CD(Helm)의 backend.configMaps 목록에 이 ConfigMap 이름을 추가해야
# 실제로 Pod 환경변수로 주입된다 — 여기서 만드는 것만으로는 안 됨.
# 이 큐는 회원가입 인증 + 예매확정/취소 알림을 모두 처리(메시지의 type 필드로 구분)하므로
# 컬럼/변수 이름을 특정 기능(이메일 인증) 전용이 아닌 범용 이름으로 둠.
resource "kubernetes_config_map" "notification" {
  metadata {
    name      = "notification-config"
    namespace = var.namespace
  }

  data = {
    NOTIFICATION_QUEUE_URL = aws_sqs_queue.email_verification.id
  }
}
