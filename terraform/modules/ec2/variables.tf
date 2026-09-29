variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
}

variable "ami" {
  description = "ID of the Amazon Machine Image (AMI) to use for EC2 instances — this is the operating system image. Rather than hardcoding an AMI ID here (which is region-specific and goes stale), pass the result of a data.aws_ami lookup from the environment root."
  type        = string
}

variable "instance_names" {
  description = "List of names for the EC2 instances"
  type        = list(string)
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "key_name" {
  description = "SSH key pair name"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs to launch instances in (instances will cycle through these)"
  type        = list(string)
}

variable "security_group_ids" {
  description = "List of security group IDs to attach"
  type        = list(string)
  default     = []
}

variable "monitoring" {
  description = "Enable detailed monitoring"
  type        = bool
  default     = true
}

variable "iam_instance_profile" {
  description = "IAM instance profile to attach"
  type        = string
  default     = null
}

variable "user_data" {
  description = "User data script"
  type        = string
  default     = null
}

variable "tags" {
  description = "Additional tags"
  type        = map(string)
  default     = {}
}

variable "associate_public_ip_address" {
  description = "Whether to associate a public IP with the instance. Set true for the bastion (public subnet). Defaults to false for cluster nodes in private subnets."
  type        = bool
  default     = false
}

variable "root_block_device" {
  description = "Customize details about the root block device of the instance. Takes a list of maps."
  type        = list(any)
  default     = []
}

variable "source_dest_check" {
  description = "Whether AWS drops traffic whose source/destination doesn't match the instance. Must be false for Kubernetes nodes running Calico, whose overlay traffic uses pod IPs. Leave true for the bastion."
  type        = bool
  default     = true
}