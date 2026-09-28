variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "project" {
  description = "Project name"
  type        = string
}

variable "db_username" {
  description = "Database username"
  type        = string
  default     = "app_user"
}

variable "db_password" {
  description = "Database password (pass via TF_VAR_db_password, never commit)"
  type        = string
  sensitive   = true
}

variable "jwt_secret" {
  description = "JWT signing secret (pass via TF_VAR_jwt_secret, never commit)"
  type        = string
  sensitive   = true
}

variable "broker_username" {
  description = "Message broker username"
  type        = string
  default     = "app_user"
}

variable "broker_password" {
  description = "Message broker password (pass via TF_VAR_broker_password, never commit)"
  type        = string
  sensitive   = true
}

variable "recovery_window_in_days" {
  description = "Recovery window for secret deletion (0 = immediate for dev)"
  type        = number
  default     = 7
}