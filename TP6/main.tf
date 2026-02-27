# ============================================================
# BUCKET S3
# ============================================================
resource "aws_s3_bucket" "tp6" {
  bucket = var.bucket_name
  tags   = var.project_tags
}

# Blocage total de l'accès public
resource "aws_s3_bucket_public_access_block" "tp6" {
  bucket = aws_s3_bucket.tp6.id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

# Versioning activé
resource "aws_s3_bucket_versioning" "tp6" {
  bucket = aws_s3_bucket.tp6.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Chiffrement par défaut (AES-256)
resource "aws_s3_bucket_server_side_encryption_configuration" "tp6" {
  bucket = aws_s3_bucket.tp6.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Policy TLS : refuse tout accès non chiffré (HTTP)
resource "aws_s3_bucket_policy" "tp6_tls" {
  bucket = aws_s3_bucket.tp6.id

  # Dépendance explicite : le blocage public doit être actif avant la policy
  depends_on = [aws_s3_bucket_public_access_block.tp6]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EnforceTLSRequestsOnly"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.tp6.arn,
          "${aws_s3_bucket.tp6.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}

# ============================================================
# LIFECYCLE RULE - Transition et expiration automatique
# ============================================================
resource "aws_s3_bucket_lifecycle_configuration" "tp6" {
  bucket = aws_s3_bucket.tp6.id

  # Dépendance explicite : le versioning doit être actif avant le lifecycle
  depends_on = [aws_s3_bucket_versioning.tp6]

  rule {
    id     = "tp6-lifecycle-rule"
    status = "Enabled"

    # S'applique à tous les objets du bucket
    filter {
      prefix = ""
    }

    # Après 30 jours : transition vers STANDARD_IA (moins cher pour accès rare)
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    # Après 90 jours : transition vers GLACIER (archivage très économique)
    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    # Après 365 jours : suppression définitive de l'objet courant
    expiration {
      days = 365
    }

    # Gestion des anciennes versions (car versioning activé)
    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "STANDARD_IA"
    }

    noncurrent_version_expiration {
      noncurrent_days = 90  # Supprime les anciennes versions après 90 jours
    }
  }
}

