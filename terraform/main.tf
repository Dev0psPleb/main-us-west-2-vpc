terraform {
  backend "remote" {
    organization = "BrynardSecurity"

    workspaces {
      name = "main-us-west-2-vpc"
    }
  }
}

provider "aws" {
  region = "us-west-2"
}

variable "vpc_name" {
  description = "Name of the VPC to deploy in the AWS account."
  default     = ""
}
variable "aws_region" {
  description = "Region in which to deploy the VPC."
  default     = ""
}
variable "aws_account" {
  description = "The AWS Account ID."
  default     = ""
}
variable "aws_account_alias" {
  description = "AWS Account alias."
  default     = ""
}
variable "customer_gateway_ip" {
  description = "IP address of the customer gateway."
  default     = ""
}
variable "device_name" {
  description = "Customer gateway device name."
  default     = ""
}
variable "environment" {
  description = "Deployment environment. Possible values: Prod, Staging, Test, Dev."
  default     = "dev"
}
variable "cidr" {
  description = "CIDR range for VPC deployment. Possible values: 10.0.0.0/16, 20.10.0.0/16"
  default     = ""
}
variable "build_branch" {
  default = ""
}
variable "build_repo" {
  default = ""
}
variable "custom_tunnel1_inside_cidr" {
  default = ""
}
variable "custom_tunnel1_preshared_key" {
  default = ""
}

locals {
  name         = var.vpc_name
  build_date   = formatdate("YYYY-MM-DD", timestamp())
  build_branch = var.build_branch
  region       = var.aws_region
  tags = {
    "Account ID"    = var.aws_account
    "Account Alias" = var.aws_account_alias
    Environment     = var.environment
    Name            = var.vpc_name
    "Build Branch"  = var.build_branch
    "Build Repo"    = var.build_repo
  }
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "3.11.0"

  name = "${local.name}-${local.build_date}"
  cidr = var.cidr

  azs             = ["${local.region}a", "${local.region}b", "${local.region}c"]
  private_subnets = ["10.19.1.0/24", "10.19.2.0/24", "10.19.3.0/24"]
  public_subnets  = ["10.19.11.0/24", "10.19.12.0/24", "10.19.13.0/24"]

  manage_default_route_table = true
  default_route_table_tags   = { DefaultRouteTable = true }

  enable_dns_hostnames = true
  enable_dns_support   = true

  enable_classiclink             = false
  enable_classiclink_dns_support = false

  enable_nat_gateway = true
  single_nat_gateway = true

  customer_gateways = {
    IP1 = {
      bgp_asn     = 65112
      ip_address  = var.customer_gateway_ip
      device_name = var.device_name
    }
  }
  enable_vpn_gateway = true

  enable_dhcp_options = false

  manage_default_security_group  = true
  default_security_group_ingress = []
  default_security_group_egress  = []

  enable_flow_log = false
}

module "vpn-gateway" {
  source  = "terraform-aws-modules/vpn-gateway/aws"
  version = "2.11.0"
  # insert the 34 required variables here
  vpc_id              = module.vpc.vpc_id
  vpn_gateway_id      = module.vpc.vgw_id
  customer_gateway_id = module.vpc.cgw_ids[0]

  # precalculated length of module variable vpc_subnet_route_table_ids
  vpc_subnet_route_table_count = 3
  vpc_subnet_route_table_ids   = module.vpc.private_route_table_ids

  # tunnel inside cidr & preshared keys (optional)
  tunnel1_inside_cidr   = var.custom_tunnel1_inside_cidr
  tunnel1_preshared_key = var.custom_tunnel1_preshared_key
}

module "main-us-west-2-tgw" {
  source      = "terraform-aws-modules/transit-gateway/aws"
  version     = "~> 2.0"
  name        = "dev-us-west-2-tgw-${local.build_date}"
  description = "Hashicorp Vault HVN TGW"

  enable_auto_accept_shared_attachments = true

  vpc_attachments = {
    vpc = {
      vpc_id       = module.vpc.vpc_id
      subnet_ids   = module.vpc.private_subnets
      dns_support  = true
      ipv6_support = false

      tgw_routes = [
        {
          destination_cidr_block = "10.99.0.0/16"
        }
      ]
    }
  }

  ram_allow_external_principals = true
  ram_principals                = [880955004141]

  tags = {
    Purpose = "hvn-tgw-dev-us-east-2"
  }
}

module "vpc_endpoints_nocreate" {
  source = "terraform-aws-modules/vpc/aws//modules/vpc-endpoints"
  create = false
}

module "hashicorp-vault" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "4.7.0"
  # insert the 3 required variables here
  name                = "hashicorp-vault-egress"
  vpc_id              = module.vpc.vpc_id
  ingress_cidr_blocks = ["172.25.16.0/20"]
  ingress_with_cidr_blocks = [
    {
      from_port   = 8200
      to_port     = 8200
      protocol    = "tcp"
      description = "Hashicorp Vault ports"
      cidr_blocks = "172.25.16.0/20"
    }
  ]
}


data "aws_security_group" "default" {
  name   = "default"
  vpc_id = module.vpc.vpc_id
}