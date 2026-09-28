module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.5.0"

  name = "${var.name}-${var.environment}-vpc"
  cidr = var.vpc_cidr

  azs             = var.azs
  private_subnets = var.private_subnet_cidrs
  public_subnets  = var.public_subnet_cidrs

  enable_nat_gateway = true

  # NAT Gateway cost vs. resilience tradeoff (deliberate decision, documented here):
  #
  # dev / staging — single_nat_gateway = true, one_nat_gateway_per_az = false
  #   One shared NAT Gateway handles all private-subnet outbound traffic.
  #   Saves ~$32/month per skipped gateway. If that one AZ goes down, all
  #   private subnets lose outbound internet access — acceptable for
  #   non-production environments where cost matters more than HA.
  #
  # prod — single_nat_gateway = false, one_nat_gateway_per_az = true
  #   One NAT Gateway per AZ. If us-east-1a fails, instances in us-east-1b
  #   and us-east-1c still reach the internet through their own NATs.
  #   Without one_nat_gateway_per_az = true, the community module would
  #   create one NAT per *private subnet* (potentially more than one per AZ),
  #   which is wasteful and not the intent.
  single_nat_gateway     = var.environment == "prod" ? false : true
  one_nat_gateway_per_az = var.environment == "prod" ? true : false

  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "${var.name}-${var.environment}-vpc"
    Environment = var.environment
    Project     = var.name
    ManagedBy   = "terraform"
  }
}