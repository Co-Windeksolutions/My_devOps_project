# ---- General ----
variable "project" {
  description = "Project name used in resource naming and tagging"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
}

# ---- Networking ----
variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
}

variable "azs" {
  description = "List of Availability Zones to use"
  type        = list(string)
}

variable "private_subnets" {
  description = "CIDR blocks for private subnets (one per AZ)"
  type        = list(string)
}

variable "public_subnets" {
  description = "CIDR blocks for public subnets (one per AZ)"
  type        = list(string)
}

variable "single_nat_gateway" {
  description = "Use a single shared NAT Gateway (true = cheaper, false = one per AZ for HA)"
  type        = bool
  default     = true
}

# ---- Security ----
variable "allowed_ssh_cidrs" {
  description = "CIDR blocks allowed to SSH into bastion/nodes"
  type        = list(string)
}

# ---- Compute ----
variable "instance_names" {
  description = "Names for the EC2 instances"
  type        = list(string)
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "key_name" {
  description = "Name of the EC2 Key Pair to use for SSH access (must exist in AWS already)"
  type        = string
}

variable "enable_monitoring" {
  description = "Enable detailed CloudWatch monitoring on EC2 instances"
  type        = bool
  default     = false
}

# ---- Logging ----
variable "log_retention_days" {
  description = "Number of days to retain logs in S3 before expiry"
  type        = number
  default     = 30
}

# ---- Secrets ----
variable "db_password" {
  description = "Database password — never commit this value. Pass via secrets.auto.tfvars (gitignored)"
  type        = string
  sensitive   = true
}

variable "jwt_secret" {
  description = "JWT signing secret — never commit this value. Pass via secrets.auto.tfvars (gitignored)"
  type        = string
  sensitive   = true
}

variable "broker_password" {
  description = "Message broker password — never commit this value. Pass via secrets.auto.tfvars (gitignored)"
  type        = string
  sensitive   = true
}