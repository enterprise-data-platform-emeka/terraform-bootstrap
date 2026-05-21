# -----------------------------------------------------------------------------
# Dev bootstrap composition
# -----------------------------------------------------------------------------
# Bootstrap creates the resources that must survive normal platform destroy
# sessions: Terraform state storage and GitHub Actions AWS authentication.

# -----------------------------------------------------------------------------
# 1. AWS provider
# -----------------------------------------------------------------------------

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile
}

# -----------------------------------------------------------------------------
# 2. Terraform state backend
# -----------------------------------------------------------------------------

module "state_backend" {
  source = "../../modules/state-backend"

  bucket_name         = "enterprise-data-platform-tfstate-dev"
  dynamodb_table_name = "enterprise-data-platform-tf-lock-dev"
  environment         = "dev"
}

# -----------------------------------------------------------------------------
# 3. GitHub Actions OpenID Connect access
# -----------------------------------------------------------------------------

# GitHub Actions OIDC provider and IAM roles for all three environments.
# Lives here (not in terraform-platform-infra-live) so CI/CD auth always exists
# even after a full platform destroy. Bootstrap is the only thing never torn down.
module "github_oidc" {
  source     = "../../modules/github-oidc"
  github_org = var.github_org
}
