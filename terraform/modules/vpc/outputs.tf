output "vpc_id" {
  description = "The ID of the VPC — passed to security and logging modules so they know which network to attach to."
  value       = module.vpc.vpc_id
}

output "private_subnets" {
  description = "List of private subnet IDs (one per AZ) — used by EC2/K8s nodes that shouldn't be directly internet-accessible."
  value       = module.vpc.private_subnets
}

output "public_subnets" {
  description = "List of public subnet IDs (one per AZ) — used by the bastion host and load balancers."
  value       = module.vpc.public_subnets
}