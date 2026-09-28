output "log_bucket_id" {
  description = "Name (ID) of the S3 log bucket. The bucket name and ID are the same thing in S3."
  value       = aws_s3_bucket.log_bucket.id
}

output "log_bucket_arn" {
  description = "ARN (Amazon Resource Name) of the S3 log bucket. Used by ALB access logs (Phase 4) and CloudTrail to know where to write. An ARN is AWS's globally unique identifier for any resource."
  value       = aws_s3_bucket.log_bucket.arn
}
