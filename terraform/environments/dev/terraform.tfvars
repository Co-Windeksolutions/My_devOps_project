# ---- General ----
project     = "my-app"
environment = "dev"
aws_region  = "us-east-1"

# ---- Networking ----
vpc_cidr           = "10.0.0.0/16"
azs                = ["us-east-1a", "us-east-1b"]
private_subnets    = ["10.0.1.0/24", "10.0.2.0/24"]
public_subnets     = ["10.0.101.0/24", "10.0.102.0/24"]
single_nat_gateway = true

# ---- Security ----
allowed_ssh_cidrs = ["0.0.0.0/0"]

# ---- Compute ----
# control-plane + 2 workers — kubeadm hard-fails with <2 vCPU or <1700 MB RAM,
# so t3.micro (1 vCPU / 1 GB) is unusable here. t3.medium = 2 vCPU / 4 GB.
# Workers also run Postgres + RabbitMQ + FastAPI pods so they need headroom too.
instance_names    = ["control-plane", "worker-1", "worker-2"]
instance_type     = "t3.medium"
key_name          = "dev-key"
enable_monitoring = false

# ---- Logging ----
log_retention_days = 30