variable "project" {
  description = "Project name — used as a prefix in the log bucket name (e.g. 'minibank'). Helps identify which project owns this bucket in the AWS console."
  type        = string
}

variable "environment" {
  description = "Environment name (e.g. dev, staging, prod). Combined with project to produce a unique bucket name per environment — dev logs and prod logs never share a bucket."
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC to enable Flow Logs for. VPC Flow Logs record all IP traffic entering and leaving the VPC and are written to this log bucket."
  type        = string
}

variable "log_bucket_force_destroy" {
  description = <<EOT
Controls whether Terraform is allowed to delete the log bucket even when it contains objects.

  false (default, recommended for prod): 'terraform destroy' will refuse to delete the bucket
  if it has any log files in it. You must empty it manually first. Prevents accidental data loss.

  true (recommended for dev): 'terraform destroy' wipes the bucket contents automatically.
  Convenient for teardown in non-production environments.
EOT
  type    = bool
  default = false
}
