# -----------------------------------------------------------------------------
# Terraform state backend outputs
# -----------------------------------------------------------------------------
# Exposes the bucket and lock table names created by bootstrap.

output "state_bucket_name" {
  value = aws_s3_bucket.state.id
}

output "lock_table_name" {
  value = aws_dynamodb_table.locks.name
}
