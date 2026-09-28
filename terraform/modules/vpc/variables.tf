variable "environment" {
  description = "Environment name (e.g. dev, staging, prod) — used in resource names and tags."
  type        = string
}

variable "name" {
  description = "Base name for the VPC and related resources (e.g. 'minibank'). Combined with environment to produce 'minibank-dev-vpc'."
  type        = string
  default     = "minibank"
}

variable "vpc_cidr" {
  description = "The IP address range (CIDR block) for the entire VPC — e.g. 10.0.0.0/16. Each environment should use a non-overlapping range so VPCs can be peered later if needed."
  type        = string
}

variable "azs" {
  description = "List of AWS Availability Zones to spread subnets across. Minimum 2 for HA. Example: [\"us-east-1a\", \"us-east-1b\", \"us-east-1c\"]."
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "One CIDR block per AZ for private subnets (app servers, DB nodes — nothing internet-facing). Must be sub-ranges of vpc_cidr."
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "One CIDR block per AZ for public subnets (load balancers, bastion host). Must be sub-ranges of vpc_cidr and non-overlapping with private subnets."
  type        = list(string)
}
