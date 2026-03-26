output "api_endpoint" {
  value = aws_apigatewayv2_stage.default.invoke_url
}

output "sqs_queue_url" {
  value = aws_sqs_queue.main.url
}

output "dlq_url" {
  value = aws_sqs_queue.dlq.url
}