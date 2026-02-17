provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile
}

module "state_backend" {
  source = "../../modules/state-backend"

  bucket_name         = "enterprise-data-platform-tfstate-staging"
  dynamodb_table_name = "enterprise-data-platform-tf-lock-staging"
  environment         = "staging"
}
