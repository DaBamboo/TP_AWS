variable "bucket_name" {
  type        = string
  description = "Nom unique du bucket S3 pour le TP6"
}

#Cela permettra d'eviter de repeter les tags a chaque fois qu'on va creer une ressource dans AWS
#il nous suffira d'ecrire : tags = var.project_tags dans la ressource que nous allons creer
variable "project_tags" {
  type        = map(string)
  description = "Tags standards du projet"
  default = {
    Project    = "FormationAWS"
    Env        = "Dev"
    Owner      = "ops-student"
    CostCenter = "IT-Training"
  }
}