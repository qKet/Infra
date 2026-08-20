variable "pilot_enabled" {
  description = "release 환경 테스트 호스트네임(gw-dev.jun979.click) 파일럿 오브젝트 생성 여부 — 검증 끝나면 false로 끄고 정리, 2단계(실제 컷오버) 시작할 때 이 모듈 자체를 걷어낼 예정"
  type        = bool
  default     = true
}
