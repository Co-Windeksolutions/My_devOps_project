# ---- General ----
project     = "my-app"
environment = "staging"
aws_region  = "us-east-1"

# ---- Networking ----
vpc_cidr           = "10.1.0.0/16"
azs                = ["us-east-1a", "us-east-1b"]
private_subnets    = ["10.1.1.0/24", "10.1.2.0/24"]
public_subnets     = ["10.1.101.0/24", "10.1.102.0/24"]
single_nat_gateway = false

# ---- Security ----
allowed_ssh_cidrs = ["203.0.113.10/32"]

# ---- Compute ----
instance_names    = ["app-1", "app-2"]
instance_type     = "t3.small"
key_name          = "staging-key"
enable_monitoring = true

# ---- Logging ----
log_retention_days = 60