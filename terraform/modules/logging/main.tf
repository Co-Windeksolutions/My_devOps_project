# Fetch the AWS account ID at plan time.
# S3 bucket names are globally unique across ALL AWS accounts — a generic name
# like "my-app-dev-logs" will collide with other accounts or a previous orphaned
# apply. Appending the 12-digit account ID makes the name unique by construction
# without any hardcoding. This is the standard AWS naming pattern for this reason.
data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "log_bucket" {
  # Format: <project>-<environment>-logs-<account-id>
  # e.g.   my-app-dev-logs-123456789012
  bucket = "${var.project}-${var.environment}-logs-${data.aws_caller_identity.current.account_id}"

  # force_destroy controls what happens when you run 'terraform destroy'.
  # false (default): Terraform refuses to delete the bucket if it has any objects — safe for prod.
  # true: Terraform deletes all contents first, then the bucket — convenient for dev teardown.
  # This is driven by var.log_bucket_force_destroy so each environment can choose independently.
  force_destroy = var.log_bucket_force_destroy
}

# Encrypt all log objects at rest using AES-256 (server-side encryption managed by AWS).
# VPC Flow Logs contain IP-level network traffic records and should never sit
# on disk unencrypted. AES256 is free and requires no KMS key management overhead.
resource "aws_s3_bucket_server_side_encryption_configuration" "log_bucket_sse" {
  bucket = aws_s3_bucket.log_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Explicitly block all forms of public access to the log bucket.
# Without this resource, bucket visibility falls back to account-level defaults,
# which may not be set. A log bucket must never be publicly readable under any circumstance.
resource "aws_s3_bucket_public_access_block" "log_bucket_public_access" {
  bucket = aws_s3_bucket.log_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Move logs to cheaper storage after 30 days, delete them after 90 days.
# This prevents the bucket from growing forever and incurring unbounded storage costs.
resource "aws_s3_bucket_lifecycle_configuration" "logs_lifecycle" {
  bucket = aws_s3_bucket.log_bucket.id

  rule {
    id     = "transition-and-expire"
    status = "Enabled"

    # The filter block is required by AWS provider >= 4.0.
    # An empty prefix means this rule applies to ALL objects in the bucket.
    # Omitting filter entirely causes an API error on apply: "Filter must not be null."
    filter {
      prefix = ""
    }

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    expiration {
      days = 90
    }
  }
}

# Capture all IP traffic entering and leaving the VPC and write it to the log bucket.
# Useful for security investigations ("who connected to what?") and network troubleshooting.
# Parquet format is columnar — much cheaper to query with Athena than plain text.
resource "aws_flow_log" "vpc_flow_logs" {
  vpc_id               = var.vpc_id
  traffic_type         = "ALL"
  log_destination      = aws_s3_bucket.log_bucket.arn
  log_destination_type = "s3"

  destination_options {
    file_format = "parquet"
  }
}