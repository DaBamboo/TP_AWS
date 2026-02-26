output "alb_dns_name" {
  description = "URL publique de l ALB pour tester le TP5"
  value       = aws_lb.tp5_alb.dns_name
}
