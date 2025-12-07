# Kinesis Module Variables

variable "stream_name" {
  description = "Name of the Kinesis data stream"
  type        = string
  default     = "smdh-sensor-data-stream"
}

variable "retention_hours" {
  description = "Data retention period in hours (24-8760)"
  type        = number
  default     = 24

  validation {
    condition     = var.retention_hours >= 24 && var.retention_hours <= 8760
    error_message = "Retention period must be between 24 hours (1 day) and 8760 hours (365 days)"
  }
}

variable "encryption_type" {
  description = "Encryption type (NONE or KMS)"
  type        = string
  default     = "KMS"

  validation {
    condition     = contains(["NONE", "KMS"], var.encryption_type)
    error_message = "Encryption type must be NONE or KMS"
  }
}

variable "kms_key_id" {
  description = "KMS key ID for encryption (use AWS managed key if null)"
  type        = string
  default     = "alias/aws/kinesis"
}

variable "enable_enhanced_monitoring" {
  description = "Enable enhanced (shard-level) CloudWatch metrics"
  type        = bool
  default     = true
}

variable "enable_monitoring" {
  description = "Enable CloudWatch alarms for the stream"
  type        = bool
  default     = true
}

variable "iterator_age_threshold_ms" {
  description = "Threshold for iterator age alarm in milliseconds"
  type        = number
  default     = 60000 # 60 seconds
}

variable "alarm_actions" {
  description = "List of ARNs to notify when alarms trigger (e.g., SNS topic ARNs)"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}
