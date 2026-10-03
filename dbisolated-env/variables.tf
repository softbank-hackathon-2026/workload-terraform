variable "bastion_instance_type" {
  description = "Bastion EC2 인스턴스 유형입니다."
  type        = string
  default     = "t3.micro"
}

variable "db_port" {
  description = "Bastion에서 DB Subnet으로 허용할 DB 포트입니다. 기본값은 PostgreSQL입니다."
  type        = number
  default     = 5432
}
