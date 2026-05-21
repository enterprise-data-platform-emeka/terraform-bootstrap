# -----------------------------------------------------------------------------
# Terraform state backend input variables
# -----------------------------------------------------------------------------
# Receives the state bucket, lock table, and environment names.

variable "bucket_name" {
  description = "Name of the S3 bucket used for Terraform remote state"
  type        = string
}

variable "dynamodb_table_name" {
  description = "Name of the DynamoDB table used for Terraform state locking"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}
