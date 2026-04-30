variable "github_org" {
  description = "GitHub organisation or username that owns the platform repositories (e.g. enterprise-data-platform-emeka)"
  type        = string
}

variable "github_repos" {
  description = "Repository names allowed to assume the GitHub Actions IAM roles via OIDC"
  type        = list(string)
  default = [
    "terraform-platform-infra-live",
    "platform-glue-jobs",
    "platform-dbt-analytics",
    "platform-orchestration-mwaa-airflow",
    "platform-cdc-simulator",
    "platform-analytics-agent",
    "platform-slack-mcp-gateway",
    "platform-teardown",
    "platform-session-orchestrator",
  ]
}

variable "name_prefix" {
  description = "Global naming prefix used in role names (e.g. edp)"
  type        = string
  default     = "edp"
}
