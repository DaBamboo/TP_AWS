variable "db_password" {
  description = "Mot de passe a stocker dans Secrets Manager"
  type        = string
  sensitive   = true
}

variable "db_host" {
  description = "Endpoint RDS (output du TP7)"
  type        = string
  sensitive   = true
}