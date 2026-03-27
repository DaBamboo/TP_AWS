# TP AWS — VALENTIN Clément — ESGI M1-SRC
 
Réalisations des travaux pratiques AWS dans le cadre du cours de Cloud Computing.
À partir du TP5, l'ensemble des ressources AWS sont déployées et gérées via **Terraform**.
 
---
 
## Structure du projet
 
```
TP_AWS/
├── base/       ← Infrastructure commune (VPC, subnets, SGs, EC2) — déployée en premier
├── TP5/        ← Haute disponibilité : ALB public + ASG privé multi-AZ
├── TP6/        ← S3 : sécurité, versioning, lifecycle, politique TLS
├── TP7/        ← RDS PostgreSQL : base privée, SG restrictif, snapshot
├── TP8/        ← DynamoDB : modélisation single-table, GSI, TTL, Streams
├── TP9/        ← Lambda trigger S3 : validation de fichiers, rôles minimaux, logs
├── TP10/       ← API Gateway + SQS + DLQ : pipeline asynchrone
├── TP11/       ← Observabilité : CloudWatch dashboard, alarmes, CloudTrail
├── TP12/       ← KMS + Secrets Manager : chiffrement et gestion des secrets
├── TP13/       ← CloudFormation : socle réseau reproductible
├── TP14/       ← ECS Fargate : conteneur managé, ECR, ALB, rolling update
└── TP15/       ← FinOps : budget, audit des tags, test de continuité, PRA
```
 
Chaque dossier contient un `README.md` détaillant les ressources créées, les choix techniques et les preuves de validation.
 
---
 
## Approche Terraform
 
Les TPs 1 à 4 ont été réalisés manuellement via la console AWS et la CLI.
À partir du **TP5**, toutes les ressources sont déclarées en **Infrastructure as Code** avec Terraform.
 
### Dossier `base/`
 
À partir du TP7, un dossier `base/` regroupe les ressources communes à tous les TPs :
VPC, subnets publics et privés, Internet Gateway, NAT Gateway, route tables, security groups et instance EC2.
 
Ce socle est déployé une seule fois. Chaque TP y accède via `terraform_remote_state` :
 
```hcl
data "terraform_remote_state" "base" {
  backend = "local"
  config = {
    path = "../base/terraform.tfstate"
  }
}
```
 
Cela évite de redéclarer les IDs de ressources dans chaque TP et garantit que les TPs s'adaptent automatiquement si le socle est recréé.
 
### Gestion des fichiers sensibles
 
Un `.gitignore` unique à la racine couvre l'ensemble du projet :
 
```gitignore
# État Terraform — contient les IDs et données sensibles
*.tfstate
*.tfstate.backup
 
# Cache Terraform
**/.terraform/
**/.terraform.lock.hcl
 
# Valeurs des variables sensibles (mots de passe, emails...)
*.tfvars
*.tfvars.json
```
 
Les fichiers `terraform.tfvars` (mots de passe, adresses email) et `terraform.tfstate` (IDs de ressources) ne sont jamais commités.
 
---
 
## Tableau récapitulatif des TPs
 
| TP | Thème | Services AWS | IaC |
|---|---|---|---|
| TP1 | Découverte console | IAM, EC2 | Manuel |
| TP2 | Stockage objet | S3 | Manuel |
| TP3 | Réseau | VPC, Subnets, IGW, NAT, SG | Manuel |
| TP4 | Compute privé | EC2, SSM, IMDSv2 | Manuel |
| TP5 | Haute disponibilité | ALB, ASG, Launch Template | Terraform |
| TP6 | Sécurité S3 | S3, Lifecycle, TLS policy | Terraform |
| TP7 | Base de données managée | RDS PostgreSQL, Snapshots | Terraform |
| TP8 | NoSQL | DynamoDB, GSI, TTL, Streams | Terraform |
| TP9 | Serverless event-driven | Lambda, S3, CloudWatch Logs | Terraform |
| TP10 | Pipeline asynchrone | API Gateway, SQS, DLQ, Lambda | Terraform |
| TP11 | Observabilité | CloudWatch, SNS, CloudTrail | Terraform |
| TP12 | Chiffrement & secrets | KMS, Secrets Manager | Terraform |
| TP13 | IaC natif AWS | CloudFormation, Change Sets | CloudFormation |
| TP14 | Conteneurs managés | ECS Fargate, ECR, ALB | Terraform |
| TP15 | Gouvernance & PRA | Budgets, Tag audit, Runbook | Terraform |
 
---
 
## Bonnes pratiques appliquées
 
- **Principe du moindre privilège** : chaque rôle IAM est limité aux actions strictement nécessaires
- **Pas de credentials en dur** : mots de passe via `terraform.tfvars` (ignoré par git) ou Secrets Manager
- **Chiffrement systématique** : AES-256 ou KMS sur tous les buckets S3 et la base RDS
- **Instances privées** : aucune EC2 ou task ECS exposée directement sur internet
- **IMDSv2 forcé** : `http_tokens = required` sur toutes les instances EC2
- **Tags obligatoires** : `Project`, `Owner`, `Env`, `CostCenter` sur toutes les ressources
- **Teardown discipliné** : `terraform destroy` après chaque TP pour maîtriser les coûts
 
---
 
## Prérequis pour reproduire
 
- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.5
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html) configurée avec un profil `training`
- [Docker Desktop](https://www.docker.com/products/docker-desktop/) (TP14 uniquement)
- Compte AWS avec les permissions suffisantes sur les services utilisés
 
```bash
# Déployer le socle commun en premier
cd base/
terraform init
terraform apply -auto-approve
 
# Puis chaque TP indépendamment
cd ../TP7/
terraform init
terraform apply -auto-approve
```