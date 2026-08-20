# 개발용 MySQL/Redis(02_k8s-addon의 StatefulSet, modules/addons/dev-datastore)가 쓰는 EBS 볼륨 —
# 순수 AWS 리소스라서 EKS 클러스터가 밤마다 destroy/재생성돼도 이 볼륨 자체는 안 건드려짐.
#
# 왜 여기(03_registry)에 있어야 하나: StatefulSet/PVC/PV 같은 쿠버네티스 오브젝트는 그게 어느
# Terraform root에 정의돼있든 상관없이 "살아있는 EKS 클러스터 안에서만" 존재 가능 — 클러스터
# 자체가 사라지면 그 안의 모든 K8s 오브젝트도 같이 사라짐. 그래서 데이터를 정말로 유지하려면
# 클러스터와 완전히 독립적인 순수 AWS 리소스(EBS 볼륨 자체)만 별도로 영구 보존하고, 매일 아침
# 새로 뜨는 StatefulSet이 이 "같은" 볼륨을 정적으로(static provisioning) 다시 연결하게 함 —
# AMP를 여기로 옮겼던 것과 같은 원리(2026-08-13 AMP 이전 사건 참고).
#
# ⚠️ AZ 고정 필수: EBS 볼륨은 특정 가용영역(AZ)에 묶여있어서, 이 볼륨을 쓰는 파드는 반드시
# 같은 AZ의 노드에서만 떠야 함(modules/addons/dev-datastore가 PV에 nodeAffinity로 강제함).
# 지금 노드가 뜨는 AZ 중 하나(ap-northeast-2a)로 고정 — 노드그룹이 이 AZ를 포함하는 서브넷을
# 계속 쓰는 한 문제없음.
resource "aws_ebs_volume" "dev_mysql" {
  availability_zone = "ap-northeast-2a"
  size              = 10
  type              = "gp3"

  tags = {
    Name = "${var.project_name}-dev-mysql-data"
  }
}

resource "aws_ebs_volume" "dev_redis" {
  availability_zone = "ap-northeast-2a"
  size              = 2
  type              = "gp3"

  tags = {
    Name = "${var.project_name}-dev-redis-data"
  }
}
