variable "region" {
  description = "Région AWS"
  type        = string
  default     = "eu-west-3"
}

variable "vpc_cidr" {
  description = "CIDR du VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "project" {
  description = "Préfixe de nommage des ressources"
  type        = string
  default     = "tp-base"
}