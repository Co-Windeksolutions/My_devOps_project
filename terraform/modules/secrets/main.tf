locals {
  name_prefix = "${var.project}-${var.environment}"
}

resource "aws_secretsmanager_secret" "db_credentials" {
  name                    = "${local.name_prefix}/db/credentials"
  description             = "Database credentials for ${var.environment}"
  recovery_window_in_days = var.recovery_window_in_days

  tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    username = var.db_username
    password = var.db_password
  })
}

resource "aws_secretsmanager_secret" "jwt_secret" {
  name                    = "${local.name_prefix}/jwt/secret"
  description             = "JWT signing key for ${var.environment}"
  recovery_window_in_days = var.recovery_window_in_days

  tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "aws_secretsmanager_secret_version" "jwt_secret" {
  secret_id     = aws_secretsmanager_secret.jwt_secret.id
  secret_string = var.jwt_secret
}

resource "aws_secretsmanager_secret" "broker_credentials" {
  name                    = "${local.name_prefix}/broker/credentials"
  description             = "Message broker credentials for ${var.environment}"
  recovery_window_in_days = var.recovery_window_in_days

  tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

resource "aws_secretsmanager_secret_version" "broker_credentials" {
  secret_id = aws_secretsmanager_secret.broker_credentials.id
  secret_string = jsonencode({
    username = var.broker_username
    password = var.broker_password
  })
}