# ── Lecture du state de base/ ─────────────────────────────────────────
data "terraform_remote_state" "base" {
  backend = "local"
  config = {
    path = "../base/terraform.tfstate"
  }
}

# ── DynamoDB (destination finale) ─────────────────────────────────────
resource "aws_dynamodb_table" "items" {
  name         = "tp10-items"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  tags = { Name = "tp10-items" }
}

# ── Dead Letter Queue ─────────────────────────────────────────────────
resource "aws_sqs_queue" "dlq" {
  name                      = "tp10-dlq"
  message_retention_seconds = 86400
  tags                      = { Name = "tp10-dlq" }
}

# ── Queue principale ──────────────────────────────────────────────────
resource "aws_sqs_queue" "main" {
  name                       = "tp10-main-queue"
  visibility_timeout_seconds = 60

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 3
  })

  tags = { Name = "tp10-main-queue" }
}

# ── Rôle Lambda producer (écrit dans SQS) ─────────────────────────────
resource "aws_iam_role" "lambda1_role" {
  name = "tp10-lambda1-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "lambda1_sqs" {
  role = aws_iam_role.lambda1_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["sqs:SendMessage"]
      Resource = aws_sqs_queue.main.arn
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda1_logs" {
  role       = aws_iam_role.lambda1_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# ── Rôle Lambda consumer (lit SQS, écrit DynamoDB) ────────────────────
resource "aws_iam_role" "lambda2_role" {
  name = "tp10-lambda2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "lambda2_policy" {
  role = aws_iam_role.lambda2_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
        Resource = aws_sqs_queue.main.arn
      },
      {
        Effect   = "Allow"
        Action   = ["dynamodb:PutItem"]
        Resource = aws_dynamodb_table.items.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda2_logs" {
  role       = aws_iam_role.lambda2_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# ── Lambda producer ───────────────────────────────────────────────────
data "archive_file" "lambda1_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda1.py"
  output_path = "${path.module}/lambda1.zip"
}

resource "aws_lambda_function" "producer" {
  function_name    = "tp10-producer"
  role             = aws_iam_role.lambda1_role.arn
  handler          = "lambda1.handler"
  runtime          = "python3.12"
  timeout          = 10
  filename         = data.archive_file.lambda1_zip.output_path
  source_code_hash = data.archive_file.lambda1_zip.output_base64sha256

  environment {
    variables = { QUEUE_URL = aws_sqs_queue.main.url }
  }

  tags = { Name = "tp10-producer" }
}

# ── Lambda consumer ───────────────────────────────────────────────────
data "archive_file" "lambda2_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda2.py"
  output_path = "${path.module}/lambda2.zip"
}

resource "aws_lambda_function" "consumer" {
  function_name    = "tp10-consumer"
  role             = aws_iam_role.lambda2_role.arn
  handler          = "lambda2.handler"
  runtime          = "python3.12"
  timeout          = 30
  filename         = data.archive_file.lambda2_zip.output_path
  source_code_hash = data.archive_file.lambda2_zip.output_base64sha256

  environment {
    variables = {
      TABLE_NAME  = aws_dynamodb_table.items.name
      FORCE_ERROR = "false"
    }
  }

  tags = { Name = "tp10-consumer" }
}

# ── Mapping SQS → Lambda consumer ─────────────────────────────────────
resource "aws_lambda_event_source_mapping" "sqs_to_consumer" {
  event_source_arn = aws_sqs_queue.main.arn
  function_name    = aws_lambda_function.consumer.arn
  batch_size       = 1
}

# ── API Gateway HTTP ───────────────────────────────────────────────────
resource "aws_apigatewayv2_api" "api" {
  name          = "tp10-api"
  protocol_type = "HTTP"
  tags          = { Name = "tp10-api" }
}

resource "aws_apigatewayv2_integration" "lambda1" {
  api_id                 = aws_apigatewayv2_api.api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.producer.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "post_items" {
  api_id    = aws_apigatewayv2_api.api.id
  route_key = "POST /items"
  target    = "integrations/${aws_apigatewayv2_integration.lambda1.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.api.id
  name        = "$default"
  auto_deploy = true
  tags        = { Name = "tp10-api-stage" }
}

resource "aws_lambda_permission" "api_gw" {
  statement_id  = "AllowAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.producer.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.api.execution_arn}/*/*"
}