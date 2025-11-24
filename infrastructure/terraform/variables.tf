# SMDH Terraform Variables
# Define all input variables for the infrastructure

variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "eu-west-2"

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "AWS region must be a valid region identifier (e.g., eu-west-2)"
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod"
  }
}

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "smdh"
}

variable "log_retention_days" {
  description = "CloudWatch log retention period in days"
  type        = number
  default     = 90

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.log_retention_days)
    error_message = "Log retention must be a valid CloudWatch retention period"
  }
}

variable "kinesis_retention_hours" {
  description = "Kinesis data retention in hours"
  type        = number
  default     = 24

  validation {
    condition     = var.kinesis_retention_hours >= 24 && var.kinesis_retention_hours <= 8760
    error_message = "Kinesis retention must be between 24 hours (1 day) and 8760 hours (365 days)"
  }
}

variable "snowflake_account_id" {
  description = "Snowflake AWS account ID for cross-account IAM role trust"
  type        = string
  sensitive   = true
  default     = ""
}

variable "snowflake_external_id" {
  description = "External ID for Snowflake IAM role assumption (security requirement)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "snowflake_region" {
  description = "Snowflake region (should match AWS region)"
  type        = string
  default     = "eu-west-2"
}

variable "alert_email" {
  description = "Email address for CloudWatch alarms and operational alerts"
  type        = string
  default     = ""

  validation {
    condition     = var.alert_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.alert_email))
    error_message = "Alert email must be a valid email address"
  }
}

variable "tenants" {
  description = "Map of tenant configurations"
  type = map(object({
    name              = string
    num_sites         = number
    retention_days    = optional(number, 730)
    warehouse_size    = optional(string, "SMALL")
    contact_email     = optional(string, "")
    sensors_per_site  = optional(number, 10)
  }))
  default = {}

  validation {
    condition = alltrue([
      for tenant_id, tenant in var.tenants :
      can(regex("^[a-z0-9_]+$", tenant_id))
    ])
    error_message = "Tenant IDs must be lowercase alphanumeric with underscores only"
  }
}

variable "enable_monitoring" {
  description = "Enable CloudWatch monitoring and alarms"
  type        = bool
  default     = true
}

variable "enable_deletion_protection" {
  description = "Enable deletion protection on critical resources (recommended for production)"
  type        = bool
  default     = false
}

variable "certificate_expiry_warning_days" {
  description = "Number of days before certificate expiry to trigger warnings"
  type        = number
  default     = 30

  validation {
    condition     = var.certificate_expiry_warning_days >= 7 && var.certificate_expiry_warning_days <= 90
    error_message = "Certificate expiry warning must be between 7 and 90 days"
  }
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# ========================================
# Mandatory Tagging Variables
# ========================================

variable "owner" {
  description = "Owner of the infrastructure (team or individual) - MANDATORY for cost allocation"
  type        = string

  validation {
    condition     = var.owner != ""
    error_message = "Owner tag is mandatory for cost allocation and operational monitoring"
  }
}

variable "cost_center" {
  description = "Cost center code for billing allocation - MANDATORY"
  type        = string

  validation {
    condition     = var.cost_center != ""
    error_message = "Cost center is mandatory for billing allocation"
  }
}

variable "deployed_by" {
  description = "Who deployed this infrastructure (email or username)"
  type        = string
  default     = ""
}

# ========================================
# Compliance and Data Classification Tags
# ========================================

variable "data_classification" {
  description = "Data classification level (Public, Internal, Confidential, Restricted)"
  type        = string
  default     = "Internal"

  validation {
    condition     = contains(["Public", "Internal", "Confidential", "Restricted"], var.data_classification)
    error_message = "Data classification must be one of: Public, Internal, Confidential, Restricted"
  }
}

variable "compliance_requirement" {
  description = "Compliance requirements (e.g., GDPR, ISO27001, None)"
  type        = string
  default     = "None"
}

variable "backup_policy" {
  description = "Backup retention policy (e.g., Daily, Weekly, Monthly, None)"
  type        = string
  default     = "Daily"

  validation {
    condition     = contains(["None", "Daily", "Weekly", "Monthly"], var.backup_policy)
    error_message = "Backup policy must be one of: None, Daily, Weekly, Monthly"
  }
}

# ========================================
# Business and Operational Tags
# ========================================

variable "business_unit" {
  description = "Business unit responsible for this infrastructure"
  type        = string
  default     = ""
}

variable "application_name" {
  description = "Application name for grouping resources"
  type        = string
  default     = "SMDH"
}

variable "service_tier" {
  description = "Service tier (Critical, High, Medium, Low)"
  type        = string
  default     = "High"

  validation {
    condition     = contains(["Critical", "High", "Medium", "Low"], var.service_tier)
    error_message = "Service tier must be one of: Critical, High, Medium, Low"
  }
}
