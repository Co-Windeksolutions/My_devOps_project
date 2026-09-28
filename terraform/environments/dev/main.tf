provider "aws" {
  region = var.aws_region
}

# Automatically fetches the latest official Ubuntu 22.04 LTS AMI for the configured region.
# Using a data source instead of a hardcoded ID means this never goes stale and works
# across regions without changes.
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
  # (true for dev/staging, false for prod) — do not pass it here.
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

  environment              = var.environment
  project                  = var.project
  vpc_id                   = module.vpc.vpc_id
  # true for dev: terraform destroy can wipe the bucket automatically.
  # Prod environments should pass false (bucket must be emptied manually — prevents accidental log loss).
  log_bucket_force_destroy = true
  # log_retention_days is not a variable in the logging module —
  # lifecycle transitions (30 d → STANDARD_IA, expire at 90 d) are
  # hard-coded in modules/logging/main.tf.
}

module "ec2" {
  source = "../../modules/ec2"

  environment        = var.environment
  ami                = data.aws_ami.ubuntu.id
  instance_names     = var.instance_names   # ["control-plane", "worker-1", "worker-2"]
  instance_type      = var.instance_type    # t3.medium — kubeadm minimum
  key_name           = var.key_name
  subnet_ids         = module.vpc.private_subnets  # spread across AZs via idx % len
  security_group_ids = [module.security.app_node_sg_id]
  monitoring         = var.enable_monitoring
}

# Bastion host — separate from the cluster nodes intentionally:
#   - lives in a public subnet (needs a public IP / EIP for SSH ingress)
#   - carries only the bastion SG (not app_node_sg — it runs no workloads)
#   - t3.micro is fine; it's a jump box, not a compute node
#   - Ansible targets this first to reach the private-subnet cluster nodes
module "bastion" {
  source = "../../modules/ec2"

  environment                 = var.environment
  ami                         = data.aws_ami.ubuntu.id
  instance_names              = ["bastion"]
  instance_type               = "t3.micro"
  key_name                    = var.key_name
  subnet_ids                  = module.vpc.public_subnets
  security_group_ids          = [module.security.bastion_sg_id]
  monitoring                  = false
  associate_public_ip_address = true  # Bastion needs a public IP — it is the SSH entry point
}

module "secrets" {
  source = "../../modules/secrets"

  environment             = var.environment
  project                 = var.project
  db_password             = var.db_password
  jwt_secret              = var.jwt_secret
  broker_password         = var.broker_password
  recovery_window_in_days = var.environment == "dev" ? 0 : 7
}