# -----------------------------------------------------------------------------
# GitHub Actions OIDC module
# -----------------------------------------------------------------------------
# Creates the account-scoped OIDC trust provider and one IAM role per
# environment (dev, staging, prod). All resources use prevent_destroy so
# they survive test-and-destroy cycles on the platform infrastructure.
#
# Why this lives in terraform-bootstrap and not terraform-platform-infra-live:
#   The OIDC provider and GitHub Actions roles must exist BEFORE the infra
#   workflow can run. If they lived in terraform-platform-infra-live, every
#   fresh session would need a manual local apply to bootstrap auth first.
#   Bootstrap runs once per AWS account and is never destroyed, so these
#   resources are always present when GitHub Actions needs them.

locals {
  environments          = ["dev", "staging", "prod"]
  github_sub_conditions = [for repo in var.github_repos : "repo:${var.github_org}/${repo}:*"]
}

# -----------------------------------------------------------------------------
# 1. GitHub OIDC provider
# -----------------------------------------------------------------------------

# GitHub OIDC provider.
# AWS no longer validates thumbprints for token.actions.githubusercontent.com
# (it pins the endpoint directly), so these values do not need updating when
# GitHub rotates certificates.
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1", "1c58a3a8518e8759bf075b76b750d4f2df264fcd"]

  lifecycle {
    prevent_destroy = true
  }
}

# -----------------------------------------------------------------------------
# 2. GitHub Actions role trust policy
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "github_actions_assume_role" {
  # Restricts to workflows running from the listed repositories only.
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = local.github_sub_conditions
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

# -----------------------------------------------------------------------------
# 3. Environment roles and permissions
# -----------------------------------------------------------------------------

# One role per environment. The deploy workflows in each repo reference
# edp-{env}-github-actions-role by name, so the naming must match exactly.
resource "aws_iam_role" "github_actions" {
  for_each           = toset(local.environments)
  name               = "${var.name_prefix}-${each.value}-github-actions-role"
  assume_role_policy = data.aws_iam_policy_document.github_actions_assume_role.json
  description        = "Assumed by GitHub Actions via OIDC for ${var.github_org} repos (${each.value})"

  lifecycle {
    prevent_destroy = true
  }
}

# AdministratorAccess is intentional. These roles run terraform apply for the
# full platform, which touches every AWS service. Least-privilege is enforced
# at the trust layer (OIDC, scoped to specific repos) rather than the
# permission layer. If individual repos need narrower roles in future, create
# dedicated roles for them and update their workflows.
resource "aws_iam_role_policy_attachment" "github_actions_admin" {
  for_each   = toset(local.environments)
  role       = aws_iam_role.github_actions[each.value].name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
