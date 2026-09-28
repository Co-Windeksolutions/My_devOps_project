output "bastion_sg_id" {
  description = "ID of the bastion host security group. Pass this to the EC2 module so the bastion instance gets the right firewall rules attached. Also needed by Ansible to confirm which instances it can reach."
  value       = aws_security_group.bastion.id
}

output "app_node_sg_id" {
  description = "ID of the app-node security group. Attach this to EC2/EKS nodes running MiniBank microservices. Ansible (Phase 2) uses this to target the right instances. ALB (Phase 4) will reference this to tighten the inbound rule."
  value       = aws_security_group.app_node.id
}

output "db_sg_id" {
  description = "ID of the database security group. Attach this to the PostgreSQL instances (or RDS, if used later). Only instances with the app_node SG or bastion SG can connect."
  value       = aws_security_group.db.id
}

output "public_nacl_id" {
  description = "ID of the public subnet NACL. Useful for adding supplementary NACL rules via aws_network_acl_rule resources in later phases without editing this module."
  value       = aws_network_acl.public.id
}

output "private_nacl_id" {
  description = "ID of the private subnet NACL. Same use as public_nacl_id — reference it to add rules without touching the module internals."
  value       = aws_network_acl.private.id
}
