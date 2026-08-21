variable "availability_zone" {
  description = "볼륨을 만들 AZ — 이 볼륨을 쓰는 파드는 반드시 같은 AZ의 노드에서만 떠야 함"
  type        = string
}

variable "size" {
  description = "볼륨 크기(GB)"
  type        = number
}

variable "name_tag" {
  description = "Name 태그"
  type        = string
}
