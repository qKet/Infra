variable "allowed_namespaces" {
  description = "alloy-faro Service를 cross-namespace backendRef로 참조할 수 있게 허용할 네임스페이스 목록 (release/prod 환경 네임스페이스들)"
  type        = list(string)
}
