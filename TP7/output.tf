output "rds_endpoint" {
  value     = aws_db_instance.postgres.endpoint
  sensitive = true
}

output "rds_instance_id" {
  value = aws_db_instance.postgres.id
}

output "snapshot_id" {
  value = aws_db_snapshot.tp7_snap.id
}