# -----------------------------------------------------------------------------
# GitHub OIDC outputs
# -----------------------------------------------------------------------------
# Exposes the OIDC provider ARN and environment role ARNs for workflow setup.

output "oidc_provider_arn" {
  description = "ARN of the GitHub Actions OIDC provider"
  value       = aws_iam_openid_connect_provider.github.arn
}

output "github_actions_role_arns" {
  description = "ARNs of the GitHub Actions IAM roles, keyed by environment name"
  value       = { for env, role in aws_iam_role.github_actions : env => role.arn }
}
