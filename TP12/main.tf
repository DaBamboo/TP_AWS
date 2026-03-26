# ── Lecture du state de base/ ─────────────────────────────────────────
data "terraform_remote_state" "base" {
  backend = "local"
  config = {
    path = "../base/terraform.tfstate"
  }
}

data "aws_caller_identity" "current" {}

# ── Clé KMS ───────────────────────────────────────────────────────────
resource "aws_kms_key" "tp12" {
  description             = "Cle KMS TP12 - S3 et Secrets Manager"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AdminAccess"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid       = "SecretsManagerAccess"
        Effect    = "Allow"
        Principal = { Service = "secretsmanager.amazonaws.com" }
        Action    = ["kms:Decrypt", "kms:GenerateDataKey"]
        Resource  = "*"
      }
    ]
  })

  tags = { Name = "tp12-kms-key" }
}

resource "aws_kms_alias" "tp12" {
  name          = "alias/tp12-key"
  target_key_id = aws_kms_key.tp12.key_id
}

# ── Bucket S3 chiffré KMS ─────────────────────────────────────────────
resource "aws_s3_bucket" "tp12" {
  bucket        = "tp12-kms-clement"
  force_destroy = true
  tags          = { Name = "tp12-kms-bucket" }
}

resource "aws_s3_bucket_public_access_block" "tp12" {
  bucket                  = aws_s3_bucket.tp12.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tp12" {
  bucket = aws_s3_bucket.tp12.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.tp12.arn
    }
    bucket_key_enabled = true
  }
}

# ── Secret Secrets Manager ────────────────────────────────────────────
resource "aws_secretsmanager_secret" "db_creds" {
  name                    = "tp12/db-credentials"
  description             = "Credentials de la base RDS TP7"
  kms_key_id              = aws_kms_key.tp12.arn
  recovery_window_in_days = 0

  tags = { Name = "tp12-db-credentials" }
}

resource "aws_secretsmanager_secret_version" "db_creds" {
  secret_id = aws_secretsmanager_secret.db_creds.id
  secret_string = jsonencode({
    username = "admintp7"
    password = var.db_password
    host     = var.db_host
    port     = 5432
    dbname   = "tp7db"
  })
}

# ── Rôle IAM Lambda ───────────────────────────────────────────────────
resource "aws_iam_role" "lambda_role" {
  name = "tp12-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "lambda_secrets" {
  role = aws_iam_role.lambda_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadSecret"
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = aws_secretsmanager_secret.db_creds.arn
      },
      {
        Sid      = "DecryptKMS"
        Effect   = "Allow"
        Action   = ["kms:Decrypt"]
        Resource = aws_kms_key.tp12.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# ── Lambda ────────────────────────────────────────────────────────────
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda_secrets.py"
  output_path = "${path.module}/lambda_secrets.zip"
}

resource "aws_lambda_function" "secret_reader" {
  function_name    = "tp12-secret-reader"
  role             = aws_iam_role.lambda_role.arn
  handler          = "lambda_secrets.handler"
  runtime          = "python3.12"
  timeout          = 10
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = { SECRET_NAME = aws_secretsmanager_secret.db_creds.name }
  }

  tags = { Name = "tp12-secret-reader" }
}

# ── GuardDuty ─────────────────────────────────────────────────────────
# GuardDuty non disponible sur compte lab (SubscriptionRequiredException)
# resource "aws_guardduty_detector" "tp12" {
#   enable = true
#   tags   = { Name = "tp12-guardduty" }
# }