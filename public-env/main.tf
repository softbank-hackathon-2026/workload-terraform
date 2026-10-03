locals {
  name = "sbh-workload-demo-public"
  tags = {
    Project     = "SBH"
    Scope       = "workload"
    Environment = "demo"
    ManagedBy   = "terraform"
    Owner       = "박준서"
    InfraId     = "sbh-workload-demo-vpc-public01"
  }
}

module "network" {
  source = "git::https://github.com/softbank-hackathon-2026/platform-terraform.git//modules/network?ref=main"

  name             = local.name
  vpc_cidr         = "10.10.0.0/16"
  nat_gateway_mode = "none"

  public_subnets = {
    pub_a = { availability_zone = "ap-northeast-2a", cidr_block = "10.10.1.0/24" }
    pub_c = { availability_zone = "ap-northeast-2c", cidr_block = "10.10.2.0/24" }
  }

  tags = local.tags
}

output "vpc_id" {
  value = module.network.vpc_id
}

output "public_subnet_ids" {
  value = module.network.public_subnet_ids
}
