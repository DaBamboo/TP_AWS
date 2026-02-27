output "bucket_name" {
  description = "Nom du bucket S3 cree"
  value       = aws_s3_bucket.tp6.id
}

output "bucket_arn" {
  description = "ARN du bucket S3 (utile pour les policies IAM des TPs suivants)"
  value       = aws_s3_bucket.tp6.arn
}

output "bucket_domain_name" {
  description = "URL d acces au bucket"
  value       = aws_s3_bucket.tp6.bucket_regional_domain_name
}
