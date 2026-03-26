# ── Lecture du state de base/ ─────────────────────────────────────────
data "terraform_remote_state" "base" {
  backend = "local"
  config = {
    path = "../base/terraform.tfstate"
  }
}

# ── Dashboard CloudWatch ───────────────────────────────────────────────
resource "aws_cloudwatch_dashboard" "tp11" {
  dashboard_name = "tp11-supervision"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "text"
        properties = { markdown = "# Dashboard TP11 — Supervision AWS" }
        x = 0, y = 0, width = 24, height = 2
      },
      {
        type = "metric"
        properties = {
          title   = "EC2 — CPU Utilization"
          view    = "timeSeries"
          metrics = [["AWS/EC2", "CPUUtilization", "InstanceId",
                      data.terraform_remote_state.base.outputs.instance_id]]
          period  = 300
          stat    = "Average"
          region  = data.terraform_remote_state.base.outputs.region
        }
        x = 0, y = 2, width = 12, height = 6
      },
      {
        type = "metric"
        properties = {
          title   = "SQS — Messages visibles"
          view    = "timeSeries"
          metrics = [
            ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", "tp10-main-queue"],
            ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", "tp10-dlq"]
          ]
          period = 60
          stat   = "Sum"
          region = data.terraform_remote_state.base.outputs.region
        }
        x = 12, y = 2, width = 12, height = 6
      },
      {
        type = "metric"
        properties = {
          title   = "Lambda — Erreurs"
          view    = "timeSeries"
          metrics = [
            ["AWS/Lambda", "Errors", "FunctionName", "tp10-consumer"],
            ["AWS/Lambda", "Errors", "FunctionName", "tp10-producer"]
          ]
          period = 300
          stat   = "Sum"
          region = data.terraform_remote_state.base.outputs.region
        }
        x = 0, y = 8, width = 12, height = 6
      },
      {
        type = "metric"
        properties = {
          title   = "Lambda — Durée (ms)"
          view    = "timeSeries"
          metrics = [["AWS/Lambda", "Duration", "FunctionName", "tp10-consumer"]]
          period  = 300
          stat    = "Average"
          region  = data.terraform_remote_state.base.outputs.region
        }
        x = 12, y = 8, width = 12, height = 6
      }
    ]
  })
}

# ── SNS Topic pour les alertes ─────────────────────────────────────────
resource "aws_sns_topic" "alerts" {
  name = "tp11-alerts"
  tags = { Name = "tp11-alerts" }
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ── Alarme : CPU EC2 > 80% ─────────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "tp11-ec2-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "CPU EC2 > 80% pendant 10 minutes"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    InstanceId = data.terraform_remote_state.base.outputs.instance_id
  }

  tags = { Name = "tp11-ec2-cpu-high" }
}

# ── Alarme : DLQ non vide ──────────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "dlq_not_empty" {
  alarm_name          = "tp11-dlq-not-empty"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Messages en attente dans la DLQ"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = { QueueName = "tp10-dlq" }

  tags = { Name = "tp11-dlq-not-empty" }
}

# ── Alarme : Erreurs Lambda ────────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "tp11-lambda-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Erreurs detectees dans tp10-consumer"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = { FunctionName = "tp10-consumer" }

  tags = { Name = "tp11-lambda-errors" }
}

# ── Bucket S3 pour CloudTrail ──────────────────────────────────────────
resource "aws_s3_bucket" "trail_bucket" {
  bucket        = "tp11-cloudtrail-clement"
  force_destroy = true
  tags          = { Name = "tp11-cloudtrail" }
}

resource "aws_s3_bucket_public_access_block" "trail" {
  bucket                  = aws_s3_bucket.trail_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket_policy" "trail" {
  bucket = aws_s3_bucket.trail_bucket.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AWSCloudTrailAclCheck"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.trail_bucket.arn
      },
      {
        Sid       = "AWSCloudTrailWrite"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.trail_bucket.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
        Condition = {
          StringEquals = { "s3:x-amz-acl" = "bucket-owner-full-control" }
        }
      }
    ]
  })
}

resource "aws_cloudtrail" "tp11" {
  name                          = "tp11-trail"
  s3_bucket_name                = aws_s3_bucket.trail_bucket.id
  include_global_service_events = true
  is_multi_region_trail         = false
  enable_log_file_validation    = true
  tags                          = { Name = "tp11-trail" }

  depends_on = [aws_s3_bucket_policy.trail]
}