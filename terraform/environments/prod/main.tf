provider "aws" {
  region = var.aws_region
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical's official AWS account ID

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

module "vpc" {
  source = "../../modules/vpc"

  environment          = var.environment
  vpc_cidr             = var.vpc_cidr
  azs                  = var.azs
  private_subnet_cidrs = var.private_subnets
  public_subnet_cidrs  = var.public_subnets
  # single_nat_gateway is derived inside the vpc module from var.environment
}

module "security" {
  source = "../../modules/security"

  environment           = var.environment
  project               = var.project
  vpc_id                = module.vpc.vpc_id
  vpc_cidr              = var.vpc_cidr
  bastion_allowed_cidrs = var.allowed_ssh_cidrs
  public_subnet_ids     = module.vpc.public_subnets
  private_subnet_ids    = module.vpc.private_subnets
}

module "logging" {
  source = "../../modules/logging"

  environment = var.environment
  project     = var.project
  vpc_id      = module.vpc.vpc_id
  # log_retention_days not a module variable — lifecycle is hard-coded in the module
}

module "ec2" {
  source = "../../modules/ec2"

  environment        = var.environment
  ami                = data.aws_ami.ubuntu.id
  instance_names     = var.instance_names
  instance_type      = var.instance_type
  key_name           = var.key_name
  subnet_ids         = module.vpc.private_subnets
  security_group_ids = [module.security.app_node_sg_id]
  monitoring         = var.enable_monitoring
}

module "secrets" {
  source = "../../modules/secrets"

  environment             = var.environment
  project                 = var.project
  db_password             = var.db_password
  jwt_secret              = var.jwt_secret
  broker_password         = var.broker_password
  recovery_window_in_days = 30
}