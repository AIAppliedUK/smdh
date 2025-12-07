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

variable "aws_region" {
  description = "AWS region for DynamoDB ARN construction"
  type        = string
  default     = "eu-west-2"
}

variable "kinesis_stream_arns" {
  description = "List of Kinesis stream ARNs that OpenFlow can access"
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
