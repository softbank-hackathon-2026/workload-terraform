locals {
  name = "sbh-workload-demo-multiaz"
  tags = {
    Project     = "SBH"
    Scope       = "workload"
    Environment = "demo"
    ManagedBy   = "terraform"
    Owner       = "박준서"
    InfraId     = "sbh-workload-demo-vpc-multiaz01"
  }
}

module "network" {
  # 실제 운영 전에는 main 대신 태그 또는 커밋 SHA로 고정하세요.
  source = "git::https://github.com/softbank-hackathon-2026/platform-terraform.git//modules/network?ref=main"

  name     = local.name
  vpc_cidr = "10.11.0.0/16"
  # NAT Gateway(과금)는 일단 제외한다. 다시 켜려면 아래 "none"을 지우고 "zonal"의 주석을 풀고,
  # 아래 zonal_nat_subnet_keys 블록의 주석도 함께 푼다.
  nat_gateway_mode = "none"
  # nat_gateway_mode = "zonal"

  # web: ALB 등 외부 노출용, nat: AZ별 NAT Gateway 배치용
  public_subnets = {
    web_a = { availability_zone = "ap-northeast-2a", cidr_block = "10.11.0.0/24" }
    web_c = { availability_zone = "ap-northeast-2c", cidr_block = "10.11.1.0/24" }
    nat_a = { availability_zone = "ap-northeast-2a", cidr_block = "10.11.2.0/24" }
    nat_c = { availability_zone = "ap-northeast-2c", cidr_block = "10.11.3.0/24" }
  }

  private_subnets = {
    app_a = { availability_zone = "ap-northeast-2a", cidr_block = "10.11.10.0/24" }
    app_c = { availability_zone = "ap-northeast-2c", cidr_block = "10.11.11.0/24" }
    db_a  = { availability_zone = "ap-northeast-2a", cidr_block = "10.11.20.0/24", enable_nat_route = false }
    db_c  = { availability_zone = "ap-northeast-2c", cidr_block = "10.11.21.0/24", enable_nat_route = false }
  }

  # NAT Gateway를 AZ마다 하나씩 배치 (총 2개)
  # zonal_nat_subnet_keys = {
  #   "ap-northeast-2a" = "nat_a"
  #   "ap-northeast-2c" = "nat_c"
  # }

  tags = local.tags
}

# ---------------------------------------------------------------
# 도메인과 HTTPS 인증서 (ACM)
# DNS는 Cloudflare에서 관리하므로 검증 CNAME과 도메인 CNAME은 사람이 등록한다.
# 적용 순서:
#   1) terraform apply -target=aws_acm_certificate.alb
#   2) 출력 acm_validation_records의 이름/값을 도메인 관리자에게 전달 -> 인증서 ISSUED 확인
#   3) terraform apply (ALB 등 나머지 생성)
#   4) 출력 alb_dns_name을 도메인 관리자에게 전달 -> domain_name이 ALB를 가리키는 CNAME 등록
# ---------------------------------------------------------------
resource "aws_acm_certificate" "alb" {
  domain_name       = var.domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(local.tags, { Name = "${local.name}-acm-alb" })
}

resource "aws_acm_certificate_validation" "alb" {
  certificate_arn         = aws_acm_certificate.alb.arn
  validation_record_fqdns = [for option in aws_acm_certificate.alb.domain_validation_options : option.resource_record_name]
}

module "alb_security_group" {
  source = "git::https://github.com/softbank-hackathon-2026/platform-terraform.git//modules/security-group?ref=main"

  name   = "${local.name}-sg-alb"
  vpc_id = module.network.vpc_id

  ingress_rules = {
    http = {
      ip_protocol = "tcp"
      from_port   = 80
      to_port     = 80
      cidr_ipv4   = "0.0.0.0/0"
      description = "HTTP from internet (redirects to HTTPS)"
    }
    https = {
      ip_protocol = "tcp"
      from_port   = 443
      to_port     = 443
      cidr_ipv4   = "0.0.0.0/0"
      description = "HTTPS from internet"
    }
  }

  egress_rules = {
    to_vpc = {
      ip_protocol = "-1"
      cidr_ipv4   = "10.11.0.0/16"
      description = "ALB to targets in VPC"
    }
  }

  tags = local.tags
}

module "alb" {
  source = "git::https://github.com/softbank-hackathon-2026/platform-terraform.git//modules/alb?ref=main"

  name               = "${local.name}-alb"
  internal           = false
  vpc_id             = module.network.vpc_id
  subnet_ids         = [module.network.public_subnet_ids["web_a"], module.network.public_subnet_ids["web_c"]]
  security_group_ids = [module.alb_security_group.security_group_id]

  target_groups = {
    web = {
      name              = "${local.name}-tg-web"
      target_type       = "ip"
      protocol          = "HTTP"
      port              = var.container_port
      health_check_path = var.health_check_path
    }
  }

  listeners = {
    http = {
      port           = 80
      protocol       = "HTTP"
      default_action = { type = "redirect", redirect_to_listener_key = "https" }
    }
    https = {
      port            = 443
      protocol        = "HTTPS"
      certificate_arn = aws_acm_certificate_validation.alb.certificate_arn
      default_action  = { type = "forward", target_group_key = "web" }
    }
  }

  tags = local.tags
}

output "vpc_id" {
  value = module.network.vpc_id
}

output "public_subnet_ids" {
  value = module.network.public_subnet_ids
}

output "private_subnet_ids" {
  value = module.network.private_subnet_ids
}

output "nat_gateway_ids_by_az" {
  value = module.network.nat_gateway_ids_by_az
}

output "alb_dns_name" {
  value = module.alb.dns_name
}

output "alb_security_group_id" {
  value = module.alb_security_group.security_group_id
}

output "target_group_arns" {
  value = module.alb.target_group_arns
}

output "service_url" {
  value = "https://${var.domain_name}"
}

output "acm_validation_records" {
  description = "도메인 관리자가 DNS에 등록할 ACM 검증 CNAME입니다."
  value = {
    for option in aws_acm_certificate.alb.domain_validation_options : option.domain_name => {
      name  = option.resource_record_name
      type  = option.resource_record_type
      value = option.resource_record_value
    }
  }
}
