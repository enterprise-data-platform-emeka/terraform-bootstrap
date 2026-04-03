variable "aws_region" {
  type    = string
  default = "eu-central-1"
}

variable "aws_profile" {
  type    = string
  default = "dev-admin"
}

variable "github_org" {
  description = "GitHub organisation that owns the platform repositories"
  type        = string
  default     = "enterprise-data-platform-emeka"
}
