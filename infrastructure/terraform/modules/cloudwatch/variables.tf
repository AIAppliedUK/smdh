# CloudWatch Module Variables

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
  description = "AWS region for CloudWatch resources"
  type        = string
  default     = "eu-west-2"
}

variable "log_retention_days" {
  description = "CloudWatch log retention period in days"
  type        = number
  default     = 90
}

variable "alert_email" {
  description = "Email address for alarm notifications"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}
