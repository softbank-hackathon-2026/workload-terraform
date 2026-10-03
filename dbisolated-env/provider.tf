terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.24"
    }
  }
}

provider "aws" {
  region = "ap-northeast-2"
  default_tags {
    tags = {
      Project = "SBH"
      Scope = "workload"
      Environment = "demo"
      ManagedBy = "terraform"
      Owner = "박준서"
    }
  }
}