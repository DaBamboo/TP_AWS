output "ecr_url" {
  value = aws_ecr_repository.app.repository_url
}

output "alb_url" {
  value = "http://${aws_lb.alb.dns_name}"
}