# Tenant Module Variables

variable "tenant_id" {
  description = "Unique tenant identifier (lowercase alphanumeric with underscores)"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9_]+$", var.tenant_id))
    error_message = "Tenant ID must be lowercase alphanumeric with underscores only"
  }
}

variable "tenant_name" {
  description = "Human-readable tenant name"
  type        = string
}

variable "num_sites" {
  description = "Number of sites/locations for this tenant"
  type        = number
  default     = 1

  validation {
    condition     = var.num_sites >= 1 && var.num_sites <= 100
    error_message = "Number of sites must be between 1 and 100"
  }
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "aws_account_id" {
  description = "AWS account ID"
  type        = string
}

variable "lorawan_thing_type_name" {
  description = "Name of the LoRaWAN Gateway thing type"
  type        = string
}

variable "iot_kinesis_role_arn" {
  description = "ARN of the IAM role for IoT Rules to write to Kinesis"
  type        = string
}

variable "kinesis_stream_name" {
  description = "Name of the Kinesis data stream"
  type        = string
}

variable "contact_email" {
  description = "Contact email for tenant alerts (optional)"
  type        = string
  default     = ""
}

variable "enable_monitoring" {
  description = "Enable CloudWatch alarms for this tenant"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}
