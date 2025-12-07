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

variable "network_server_thing_type_name" {
  description = "Name of the Network Server thing type (ChirpStack or similar)"
  type        = string
  default     = "NetworkServer"
}

variable "deployment_mode" {
  description = "Device deployment mode: 'gateway' for Milesight UG65 with built-in NS (one gateway per site), 'network_server' for ChirpStack or similar centralized NS (one NS per tenant)"
  type        = string
  default     = "gateway"

  validation {
    condition     = contains(["gateway", "network_server"], var.deployment_mode)
    error_message = "Deployment mode must be either 'gateway' or 'network_server'"
  }
}

variable "network_server_name" {
  description = "Name/identifier for the network server (only used when deployment_mode = 'network_server')"
  type        = string
  default     = "chirpstack"
}

variable "iot_kinesis_role_arn" {
  description = "ARN of the IAM role for IoT Rules to write to Kinesis"
  type        = string
}

variable "kinesis_retention_hours" {
  description = "Kinesis stream retention period in hours (24-8760)"
  type        = number
  default     = 24

  validation {
    condition     = var.kinesis_retention_hours >= 24 && var.kinesis_retention_hours <= 8760
    error_message = "Kinesis retention must be between 24 hours (1 day) and 8760 hours (365 days)"
  }
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
