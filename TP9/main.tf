# ── Lecture du state de base/ ─────────────────────────────────────────
data "terraform_remote_state" "base" {
  backend = "local"
  config = {
    path = "../base/terraform.tfstate"
  }
}

# ── Bucket S3 ─────────────────────────────────────────────────────────
resource "aws_s3_bucket" "tp9" {
  bucket = "tp9-lambda-trigger-clement"
  tags   = { Name = "tp9-lambda-bucket" }
}

resource "aws_s3_bucket_public_access_block" "tp9" {
  bucket                  = aws_s3_bucket.tp9.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "tp9" {
  bucket = aws_s3_bucket.tp9.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tp9" {
  bucket = aws_s3_bucket.tp9.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# ── Rôle IAM Lambda (minimal) ─────────────────────────────────────────
resource "aws_iam_role" "lambda_role" {
  name = "tp9-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "lambda_s3_policy" {
  name = "tp9-lambda-s3-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadInput"
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "${aws_s3_bucket.tp9.arn}/input/*"
      },
      {
        Sid      = "WriteOutput"
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = "${aws_s3_bucket.tp9.arn}/output/*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# ── Package Lambda ────────────────────────────────────────────────────
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda.py"
  output_path = "${path.module}/lambda.zip"
}

# ── Fonction Lambda ───────────────────────────────────────────────────
resource "aws_lambda_function" "validator" {
  function_name    = "tp9-file-validator"
  role             = aws_iam_role.lambda_role.arn
  handler          = "lambda.handler"
  runtime          = "python3.12"
  timeout          = 30
  memory_size      = 128
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      BUCKET_NAME   = aws_s3_bucket.tp9.bucket
      MAX_SIZE_MB   = "5"
      ALLOWED_TYPES = "image/jpeg,image/png,application/pdf"
    }
  }

  tags = { Name = "tp9-file-validator" }
}

# ── Log Group CloudWatch ──────────────────────────────────────────────
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${aws_lambda_function.validator.function_name}"
  retention_in_days = 7
  tags              = { Name = "tp9-lambda-logs" }
}

# ── Permission S3 → Lambda ────────────────────────────────────────────
resource "aws_lambda_permission" "allow_s3" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.validator.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.tp9.arn
}

# ── Notification S3 → Lambda ──────────────────────────────────────────
resource "aws_s3_bucket_notification" "trigger" {
  bucket = aws_s3_bucket.tp9.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.validator.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "input/"
  }

  depends_on = [aws_lambda_permission.allow_s3]
}