variable "alert_email" {
  description = "Email pour les alertes budget"
  type        = string
}

variable "budget_limit_usd" {
  description = "Plafond mensuel en USD"
  type        = string
  default     = "20"
}