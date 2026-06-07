output "state_bucket_name" {
  value       = aws_s3_bucket.tfstate.id
  description = "Use this as the bucket name in environments/dev backend config"
}

output "state_bucket_arn" {
  value = aws_s3_bucket.tfstate.arn
}

output "dynamodb_table_name" {
  value       = aws_dynamodb_table.tfstate_lock.name
  description = "Use this as the dynamodb_table name in environments/dev backend config"
}
