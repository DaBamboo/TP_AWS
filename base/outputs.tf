output "vpc_id" {
  value = aws_vpc.main.id
}

output "subnet_public_a_id" {
  value = aws_subnet.public_a.id
}

output "subnet_public_b_id" {
  value = aws_subnet.public_b.id
}

output "subnet_private_a_id" {
  value = aws_subnet.private_a.id
}

output "subnet_private_b_id" {
  value = aws_subnet.private_b.id
}

output "sg_web_id" {
  value = aws_security_group.sg_web.id
}

output "sg_app_id" {
  value = aws_security_group.sg_app.id
}

output "sg_db_id" {
  value = aws_security_group.sg_db.id
}

output "instance_id" {
  value = aws_instance.app.id
}

output "region" {
  value = var.region
}