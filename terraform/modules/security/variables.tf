variable "environment" {
  description = "Environment name (e.g. dev, staging, prod) — used in the security group name so you can tell them apart in the AWS console."
  type        = string
}

variable "project" {
  description = "Project name — used as a prefix in IAM policy names (e.g. 'my-app-dev-secrets-read')."
  type        = string
}


variable "vpc_id" {
  description = "ID of the VPC to create security groups in. Security groups are VPC-scoped — they must be created inside the same network as the resources they protect."
  type        = string
}

variable "bastion_allowed_cidrs" {
  description = "List of IP address ranges (CIDR notation) allowed to SSH into the bastion host. Should be your office or home IP, not 0.0.0.0/0. Example: [\"203.0.113.5/32\"]."
  type        = list(string)
}

variable "vpc_cidr" {
  description = "The VPC's CIDR block (e.g. 10.0.0.0/16). Used in NACL rules to scope inbound/outbound traffic to within the VPC, and in the app-node SG to allow inbound on the app port from within the network."
  type        = string
}

variable "public_subnet_ids" {
  description = "List of public subnet IDs to associate with the public NACL. The NACL is applied at the subnet level — all traffic entering or leaving these subnets is checked against its rules."
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs to associate with the private NACL. All traffic entering or leaving these subnets (app nodes, DB) is checked against its rules."
  type        = list(string)
}

variable "app_port" {
  description = "The port the microservice app nodes listen on. Used in the app-node SG to allow inbound traffic from the load balancer or VPC. Default matches FastAPI's conventional port."
  type        = number
  default     = 8000
}

variable "db_port" {
  description = "The database port. Used in the DB SG to restrict inbound access to this port only, and to scope the app-node's outbound database egress. Default is PostgreSQL standard port."
  type        = number
  default     = 5432
}
