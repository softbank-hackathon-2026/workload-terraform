variable "domain_name" {
  description = "ALB에 연결할 전체 도메인 이름이며 ACM 인증서가 이 이름으로 발급됩니다. 예: demo.example.com"
  type        = string

  validation {
    condition     = length(trimspace(var.domain_name)) > 0
    error_message = "domain_name은 비어 있을 수 없습니다."
  }
}

variable "container_port" {
  description = "ALB Target Group이 트래픽을 전달할 앱 포트입니다."
  type        = number
  default     = 80
}

variable "health_check_path" {
  description = "ALB Target Group의 상태 확인 경로입니다."
  type        = string
  default     = "/"
}
