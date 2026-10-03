locals {
  name = "sbh-workload-demo-dbisolated"
  tags = {
    Project     = "SBH"
    Scope       = "workload"
    Environment = "demo"
    ManagedBy   = "terraform"
    Owner       = "박준서"
    InfraId     = "sbh-workload-demo-vpc-dbisolated01"
  }
}

module "network" {
  # 실제 운영 전에는 main 대신 태그 또는 커밋 SHA로 고정하세요.
  source = "git::https://github.com/softbank-hackathon-2026/platform-terraform.git//modules/network?ref=main"

  name             = local.name
  vpc_cidr         = "10.12.0.0/16"
  nat_gateway_mode = "none"

  public_subnets = {
    pub_a = { availability_zone = "ap-northeast-2a", cidr_block = "10.12.0.0/24" }
    pub_c = { availability_zone = "ap-northeast-2c", cidr_block = "10.12.1.0/24" }
  }

  # NAT가 없으므로 DB Subnet은 인터넷으로 나가지 못한다.
  # S3/ECR 접근은 아래 VPC Endpoint로 처리한다.
  private_subnets = {
    db_a = { availability_zone = "ap-northeast-2a", cidr_block = "10.12.20.0/24", enable_nat_route = false }
    db_c = { availability_zone = "ap-northeast-2c", cidr_block = "10.12.21.0/24", enable_nat_route = false }
  }

  tags = local.tags
}


data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

module "bastion_security_group" {
  source = "git::https://github.com/softbank-hackathon-2026/platform-terraform.git//modules/security-group?ref=main"

  name   = "${local.name}-sg-bastion"
  vpc_id = module.network.vpc_id

  # SSH 포트를 열지 않는다. 접속은 SSM Session Manager로 한다.
  ingress_rules = {}

  egress_rules = {
    all = {
      ip_protocol = "-1"
      cidr_ipv4   = "0.0.0.0/0"
      description = "Bastion outbound"
    }
  }

  tags = local.tags
}

# Bastion 접속은 SSH 키 대신 SSM Session Manager를 쓴다.
resource "aws_iam_role" "bastion" {
  name = "${local.name}-role-bastion"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = merge(local.tags, { Name = "${local.name}-role-bastion" })
}

resource "aws_iam_role_policy_attachment" "bastion_ssm" {
  role       = aws_iam_role.bastion.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "bastion" {
  name = "${local.name}-profile-bastion"
  role = aws_iam_role.bastion.name

  tags = merge(local.tags, { Name = "${local.name}-profile-bastion" })
}

module "bastion" {
  source = "git::https://github.com/softbank-hackathon-2026/platform-terraform.git//modules/ec2?ref=main"

  name                        = "${local.name}-ec2-bastion"
  ami_id                      = data.aws_ssm_parameter.al2023_ami.value
  instance_type               = var.bastion_instance_type
  subnet_id                   = module.network.public_subnet_ids["pub_a"]
  security_group_ids          = [module.bastion_security_group.security_group_id]
  iam_instance_profile        = aws_iam_instance_profile.bastion.name
  associate_public_ip_address = true

  tags = local.tags
}

# DB용 Security Group: Bastion에서만 DB 포트 접근을 허용한다.
module "db_security_group" {
  source = "git::https://github.com/softbank-hackathon-2026/platform-terraform.git//modules/security-group?ref=main"

  name   = "${local.name}-sg-db"
  vpc_id = module.network.vpc_id

  ingress_rules = {
    from_bastion = {
      ip_protocol                  = "tcp"
      from_port                    = var.db_port
      to_port                      = var.db_port
      referenced_security_group_id = module.bastion_security_group.security_group_id
      description                  = "DB from bastion"
    }
  }

  tags = local.tags
}

# ---------------------------------------------------------------
# VPC Endpoint: NAT 없이 S3/ECR에 접근하기 위한 설정
# - S3: Gateway Endpoint (ECR 이미지 레이어도 S3에서 내려받는다)
# - ECR: api/dkr는 Gateway가 아닌 Interface Endpoint만 지원한다 (시간당 비용 발생)
# ---------------------------------------------------------------
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = module.network.vpc_id
  service_name      = "com.amazonaws.ap-northeast-2.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = values(module.network.private_route_table_ids)

  tags = merge(local.tags, { Name = "${local.name}-vpce-s3" })
}

# ECR Interface Endpoint는 시간당 비용이 있어 필요할 때 주석을 풀고 apply한다 (Notion ADR Option D).
# module "endpoint_security_group" {
#   source = "git::https://github.com/softbank-hackathon-2026/platform-terraform.git//modules/security-group?ref=main"
#
#   name   = "${local.name}-sg-vpce"
#   vpc_id = module.network.vpc_id
#
#   ingress_rules = {
#     https_from_vpc = {
#       ip_protocol = "tcp"
#       from_port   = 443
#       to_port     = 443
#       cidr_ipv4   = "10.12.0.0/16"
#       description = "HTTPS from VPC"
#     }
#   }
#
#   tags = local.tags
# }
#
# resource "aws_vpc_endpoint" "ecr_api" {
#   vpc_id              = module.network.vpc_id
#   service_name        = "com.amazonaws.ap-northeast-2.ecr.api"
#   vpc_endpoint_type   = "Interface"
#   subnet_ids          = values(module.network.private_subnet_ids)
#   security_group_ids  = [module.endpoint_security_group.security_group_id]
#   private_dns_enabled = true
#
#   tags = merge(local.tags, { Name = "${local.name}-vpce-ecr-api" })
# }
#
# resource "aws_vpc_endpoint" "ecr_dkr" {
#   vpc_id              = module.network.vpc_id
#   service_name        = "com.amazonaws.ap-northeast-2.ecr.dkr"
#   vpc_endpoint_type   = "Interface"
#   subnet_ids          = values(module.network.private_subnet_ids)
#   security_group_ids  = [module.endpoint_security_group.security_group_id]
#   private_dns_enabled = true
#
#   tags = merge(local.tags, { Name = "${local.name}-vpce-ecr-dkr" })
# }

output "vpc_id" {
  value = module.network.vpc_id
}

output "public_subnet_ids" {
  value = module.network.public_subnet_ids
}

output "private_subnet_ids" {
  value = module.network.private_subnet_ids
}

output "bastion_public_ip" {
  value = module.bastion.public_ip
}

output "db_security_group_id" {
  value = module.db_security_group.security_group_id
}
