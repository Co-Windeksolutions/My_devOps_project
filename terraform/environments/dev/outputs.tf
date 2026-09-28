################################################################################
# Dev Environment Outputs
#
# These expose the key IPs and IDs of provisioned infrastructure so you can
# see them after "terraform apply" and query them any time via "terraform output".
#
# None of these outputs modify or recreate any AWS resources.
################################################################################

# ---------------------------------------------------------------------------
# Bastion Host
# ---------------------------------------------------------------------------
output "bastion_public_ip" {
  description = "Public IP of the Bastion jump host. SSH here first before reaching private cluster nodes."
  value       = module.bastion.instance_public_ips["bastion"]
}

output "bastion_private_ip" {
  description = "Private IP of the Bastion host inside the VPC."
  value       = module.bastion.instance_private_ips["bastion"]
}

output "bastion_instance_id" {
  description = "EC2 Instance ID of the Bastion host."
  value       = module.bastion.instance_ids["bastion"]
}

# ---------------------------------------------------------------------------
# Kubernetes Cluster Nodes (Private Subnets)
# These instances have NO public IPs - reach them via the bastion jump box.
# ---------------------------------------------------------------------------
output "k8s_node_private_ips" {
  description = "Private IPs of Kubernetes cluster nodes (control-plane, worker-1, worker-2)."
  value       = module.ec2.instance_private_ips
}

output "k8s_node_ids" {
  description = "EC2 Instance IDs of the Kubernetes cluster nodes."
  value       = module.ec2.instance_ids
}

# ---------------------------------------------------------------------------
# Network
# ---------------------------------------------------------------------------
output "vpc_id" {
  description = "ID of the dev VPC."
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "Public subnet IDs (Bastion and future ALB live here)."
  value       = module.vpc.public_subnets
}

output "private_subnet_ids" {
  description = "Private subnet IDs (Kubernetes nodes and DB live here)."
  value       = module.vpc.private_subnets
}
