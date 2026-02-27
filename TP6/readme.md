# TP 6 : S3 — Sécurité, Versioning, Lifecycle et Politique Transport TLS

## Objectif

Construire un bucket S3 conforme aux bonnes pratiques de sécurité cloud :
blocage public, versioning, chiffrement au repos, politique TLS obligatoire et règle de cycle de vie automatisée.
Démontrer la gestion des versions d'objets et la restauration d'une version antérieure.

## Infrastructure as Code — Terraform

Ce TP a été entièrement réalisé avec **Terraform**. L'ensemble des fichiers sont disponibles dans ce dépôt.

### Structure des fichiers

| Fichier | Rôle |
|---|---|
| `version.tf` | Déclaration du provider AWS, région `eu-west-3`, profil `training` |
| `variables.tf` | Déclaration des variables (`bucket_name`, `project_tags`) |
| `vars.tfvars` | Valeurs des variables (non versionné — voir `.gitignore`) |
| `main.tf` | Toutes les ressources AWS créées pour ce TP |
| `outputs.tf` | Outputs : nom, ARN et URL régionale du bucket |

## Ressources créées

### 1. Bucket S3 (`training-clement-tp6`)
Bucket dédié au projet avec les tags standards `Project`, `Env`, `Owner`, `CostCenter`.

### 2. Blocage de l'accès public
Les quatre paramètres de blocage sont activés pour prévenir toute exposition accidentelle des données sur internet :

```json
{
    "PublicAccessBlockConfiguration": {
        "BlockPublicAcls": true,
        "IgnorePublicAcls": true,
        "BlockPublicPolicy": true,
        "RestrictPublicBuckets": true
    }
}
```

### 3. Versioning
Toutes les modifications d'objets sont conservées sous forme de versions distinctes.
Cela permet la restauration à tout moment d'un état antérieur.

```json
{
    "Status": "Enabled"
}
```

### 4. Chiffrement par défaut (AES-256)
Tous les objets stockés sont automatiquement chiffrés au repos avec l'algorithme AES-256 (SSE-S3) :

```json
{
    "ServerSideEncryptionConfiguration": {
        "Rules": [
            {
                "ApplyServerSideEncryptionByDefault": {
                    "SSEAlgorithm": "AES256"
                },
                "BucketKeyEnabled": false
            }
        ]
    }
}
```

### 5. Politique TLS obligatoire (`EnforceTLSRequestsOnly`)
Une bucket policy refuse explicitement toute requête non chiffrée (HTTP).
Toute action `s3:*` est bloquée si la condition `aws:SecureTransport` est `false` :

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "EnforceTLSRequestsOnly",
            "Effect": "Deny",
            "Principal": "*",
            "Action": "s3:*",
            "Resource": [
                "arn:aws:s3:::training-clement-tp6",
                "arn:aws:s3:::training-clement-tp6/*"
            ],
            "Condition": {
                "Bool": {
                    "aws:SecureTransport": "false"
                }
            }
        }
    ]
}
```

### 6. Règle Lifecycle (`tp6-lifecycle-rule`)

Gestion automatique du cycle de vie des objets pour optimiser les coûts de stockage :

| Délai | Action | Classe de stockage |
|---|---|---|
| J+30 | Transition objets courants | `STANDARD_IA` (accès peu fréquent) |
| J+90 | Transition objets courants | `GLACIER` (archivage longue durée) |
| J+365 | Expiration | Suppression définitive |
| J+30 (versions) | Transition anciennes versions | `STANDARD_IA` |
| J+90 (versions) | Expiration anciennes versions | Suppression définitive |

> **Note :** La gestion des anciennes versions (`NoncurrentVersion*`) est indispensable avec le versioning activé.
> Sans cette règle, les anciennes versions s'accumulent indéfiniment et génèrent des coûts croissants.

## Tests de validation

### Preuve du versioning — Deux versions coexistantes

Après avoir uploadé `test-objet.txt` une première fois (V1, 27 octets), puis une version modifiée (V2, 57 octets), on peut voir que les deux versions sont présentes

```powershell
aws s3api list-object-versions `
    --bucket training-clement-tp6 `
    --prefix "test-objet.txt" `
    --query "Versions[*].{Fichier:Key,Version:VersionId,Derniere:IsLatest,Date:LastModified,Taille:Size}" `
    --output table `
    --profile training
```

```
-----------------------------------------------------------------------------------------------------------
|                                           ListObjectVersions                                            |
+----------------------------+-----------+-----------------+---------+------------------------------------+
|            Date            | Derniere  |     Fichier     | Taille  |              Version               |
+----------------------------+-----------+-----------------+---------+------------------------------------+
|  2026-02-27T11:13:15+00:00 |  True     |  test-objet.txt |  57     |  w27dQPnVtyk2fvjOWsdvYLgX1gSjlASM  |
|  2026-02-27T10:48:31+00:00 |  False    |  test-objet.txt |  27     |  wlwCg1w6tC3UCxHBwimdOqKt04Wb_yP0  |
+----------------------------+-----------+-----------------+---------+------------------------------------+
```

> `IsLatest = True` identifie la version courante (colonne "Derniere"). `IsLatest = False` identifie l'ancienne version conservée.

### Restauration de la V1 — Lecture du contenu

Pour restaurer la première version dans un fichier 'restored-test-object.txt': 

```powershell
aws s3api get-object `
    --bucket training-clement-tp6 `
    --key "test-objet.txt" `
    --version-id wlwCg1w6tC3UCxHBwimdOqKt04Wb_yP0 `
    restored-test-objet.txt `
    --profile training

Get-Content restored-test-objet.txt
```
On voit qu on a bien restauré le contenu, l ajout de la deuxième ligne n est plus présent :

```
Version 1 - Premier contenu
```

### Restauration de la V1 comme version courante (`copy-object`)

La vraie restauration S3 consiste à recopier l'ancienne version comme une nouvelle version courante.
Cela crée une V3 dont le contenu est identique à la V1 originale :

```powershell
aws s3api copy-object `
    --bucket training-clement-tp6 `
    --copy-source "training-clement-tp6/test-objet.txt?versionId=wlwCg1w6tC3UCxHBwimdOqKt04Wb_yP0" `
    --key "test-objet.txt" `
    --profile training
```

> Ainsi, on voit que la version 2 (la plus lourde) n'est plus la dernière version (`IsLatest = False`) 
> C'est bien la version 1 restaurée dans une version 3 qui est la dernière

```
-----------------------------------------------------------------------------------------------------------
|                                           ListObjectVersions                                            |
+----------------------------+-----------+-----------------+---------+------------------------------------+
|            Date            | Derniere  |     Fichier     | Taille  |              Version               |
+----------------------------+-----------+-----------------+---------+------------------------------------+
|  2026-02-27T11:32:30+00:00 |  True     |  test-objet.txt |  27     |  FMk6sKhwTOTfKbYJ56zuIuK2.7fgQ1ig  |
|  2026-02-27T11:13:15+00:00 |  False    |  test-objet.txt |  57     |  w27dQPnVtyk2fvjOWsdvYLgX1gSjlASM  |
|  2026-02-27T10:48:31+00:00 |  False    |  test-objet.txt |  27     |  wlwCg1w6tC3UCxHBwimdOqKt04Wb_yP0  |
+----------------------------+-----------+-----------------+---------+------------------------------------+
```

## Contrôles sécurité appliqués

- Blocage public activé sur les 4 paramètres — aucune exposition accidentelle possible : 
```json
"PublicAccessBlockConfiguration": {
        "BlockPublicAcls": true,
        "IgnorePublicAcls": true,
        "BlockPublicPolicy": true,
        "RestrictPublicBuckets": true
    }
```
- Versioning activé et démontré avec restauration réussie
```powershell
PS C:\Users\cleme\Desktop\TP_AWS\TP6> aws s3api get-bucket-versioning `
     --bucket training-clement-tp6 `
     --profile training
{
    "Status": "Enabled"
}
```

- Chiffrement AES-256 au repos activé par défaut sur tous les objets
```json
{
    "ServerSideEncryptionConfiguration": {
        "Rules": [
            {
                "ApplyServerSideEncryptionByDefault": {
                    "SSEAlgorithm": "AES256"
                },
                "BucketKeyEnabled": false
            }
        ]
    }
}
```

- Transport TLS obligatoire via bucket policy `Deny` sur `aws:SecureTransport = false`

- Règle lifecycle avec gestion des anciennes versions pour maîtrise des coûts
```json
{
    "TransitionDefaultMinimumObjectSize": "all_storage_classes_128K",
    "Rules": [
        {
            "Expiration": {
                "Days": 365
            },
            "ID": "tp6-lifecycle-rule",
            "Filter": {
                "Prefix": ""
            },
            "Status": "Enabled",
            "Transitions": [
                {
                    "Days": 30,
                    "StorageClass": "STANDARD_IA"
                },
                {
                    "Days": 90,
                    "StorageClass": "GLACIER"
                }
            ],
            "NoncurrentVersionTransitions": [
                {
                    "NoncurrentDays": 30,
                    "StorageClass": "STANDARD_IA"
                }
            ],
            "NoncurrentVersionExpiration": {
                "NoncurrentDays": 90
            }
        }
    ]
}
```

- Tags obligatoires appliqués (`Project`, `Owner`, `Env`, `CostCenter`)
