# -----------------------------------------------------------------------------
# Terraform state backend module
# -----------------------------------------------------------------------------
# Creates the S3 bucket and DynamoDB lock table used by Terraform remote state.
# Both resources use prevent_destroy because losing them would break state
# management for the environment.

# -----------------------------------------------------------------------------
# 1. State bucket
# -----------------------------------------------------------------------------

resource "aws_s3_bucket" "state" {
  bucket = var.bucket_name

  tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
    Project     = "EnterpriseDataPlatform"
  }

  lifecycle {
    prevent_destroy = true
  }
}

# -----------------------------------------------------------------------------
# 2. State bucket controls
# -----------------------------------------------------------------------------

resource "aws_s3_bucket_versioning" "versioning" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "encryption" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# -----------------------------------------------------------------------------
# 3. Lock table
# -----------------------------------------------------------------------------

resource "aws_dynamodb_table" "locks" {
  name         = var.dynamodb_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
    Project     = "EnterpriseDataPlatform"
  }

  lifecycle {
    prevent_destroy = true
  }
}
