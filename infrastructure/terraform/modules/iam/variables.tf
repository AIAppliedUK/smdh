# IAM Module Variables

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "smdh"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "snowflake_account_id" {
  description = "Snowflake AWS account ID for cross-account trust"
  type        = string
  sensitive   = true
  default     = ""
}

variable "snowflake_external_id" {
  description = "External ID for Snowflake role assumption (security requirement)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "kinesis_stream_arns" {
  description = "List of Kinesis stream ARNs that Snowflake can access"
  type        = list(string)
}

variable "create_lambda_role" {
  description = "Create IAM role for Lambda functions (optional for custom processing)"
  type        = bool
  default     = false
}

variable "secrets_manager_arns" {
  description = "List of Secrets Manager ARNs that Lambda can access"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}
