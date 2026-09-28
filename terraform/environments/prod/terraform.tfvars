# ---- General ----
project     = "my-app"
environment = "prod"
aws_region  = "us-east-1"

# ---- Networking ----
vpc_cidr           = "10.2.0.0/16"
azs                = ["us-east-1a", "us-east-1b", "us-east-1c"]
private_subnets    = ["10.2.1.0/24", "10.2.2.0/24", "10.2.3.0/24"]
public_subnets     = ["10.2.101.0/24", "10.2.102.0/24", "10.2.103.0/24"]
single_nat_gateway = false

# ---- Security ----
allowed_ssh_cidrs = ["203.0.113.10/32"]

# ---- Compute ----
instance_names    = ["app-1", "app-2", "app-3", "app-4", "app-5", "app-6"]
instance_type     = "t3.medium"
key_name          = "prod-key"
enable_monitoring = true

# ---- Logging ----
log_retention_days = 90