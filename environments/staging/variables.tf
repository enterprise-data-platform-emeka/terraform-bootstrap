# -----------------------------------------------------------------------------
# Staging bootstrap input variables
# -----------------------------------------------------------------------------
# Defines the AWS profile, region, and GitHub organisation used by bootstrap.

variable "aws_region" {
  type    = string
  default = "eu-central-1"
}

variable "aws_profile" {
  type    = string
  default = "staging-admin"
}

variable "github_org" {
  description = "GitHub organisation that owns the platform repositories"
  type        = string
  default     = "enterprise-data-platform-emeka"
}
