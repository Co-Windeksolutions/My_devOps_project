locals {
  # Assign each instance to a subnet by cycling through the provided subnet_ids
  instance_subnet_map = {
    for idx, name in var.instance_names :
    name => var.subnet_ids[idx % length(var.subnet_ids)]
  }
}

module "ec2_instance" {
  source  = "terraform-aws-modules/ec2-instance/aws"
  version = "5.6.0" # Pin to a specific version for stability

  for_each = local.instance_subnet_map

  name = "instance-${each.key}"

  ami                         = var.ami
  instance_type               = var.instance_type
  key_name                    = var.key_name
  monitoring                  = var.monitoring
  subnet_id                   = each.value
  vpc_security_group_ids      = var.security_group_ids
  iam_instance_profile        = var.iam_instance_profile
  user_data                   = var.user_data
  associate_public_ip_address = var.associate_public_ip_address

  tags = merge(
    {
      Terraform   = "true"
      Environment = var.environment
      Name        = "instance-${each.key}"
    },
    var.tags
  )
}