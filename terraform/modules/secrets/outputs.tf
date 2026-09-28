output "db_credentials_arn" {
  description = "ARN of the database credentials secret"
  value       = aws_secretsmanager_secret.db_credentials.arn
}

output "jwt_secret_arn" {
  description = "ARN of the JWT signing secret"
  value       = aws_secretsmanager_secret.jwt_secret.arn
}

output "broker_credentials_arn" {
  description = "ARN of the broker credentials secret"
  value       = aws_secretsmanager_secret.broker_credentials.arn
}