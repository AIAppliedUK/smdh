# IAM Module Outputs

output "snowflake_role_arn" {
  description = "ARN of the IAM role for Snowflake/Openflow to assume"
  value       = aws_iam_role.snowflake_kinesis.arn
}

output "snowflake_role_name" {
  description = "Name of the IAM role for Snowflake/Openflow"
  value       = aws_iam_role.snowflake_kinesis.name
}

output "snowflake_role_id" {
  description = "Unique ID of the IAM role for Snowflake/Openflow"
  value       = aws_iam_role.snowflake_kinesis.id
}

output "snowflake_external_id" {
  description = "External ID for secure role assumption (configure in Openflow AWSCredentialsProviderControllerService)"
  value       = var.snowflake_external_id
  sensitive   = true
}

output "openflow_config" {
  description = "Configuration values for Openflow AWSCredentialsProviderControllerService"
  value = {
    assume_role_arn         = aws_iam_role.snowflake_kinesis.arn
    assume_role_external_id = var.snowflake_external_id
    assume_role_sts_region  = var.aws_region
  }
  sensitive = true
}

output "lambda_role_arn" {
  description = "ARN of the Lambda execution role (if created)"
  value       = var.create_lambda_role ? aws_iam_role.lambda_execution[0].arn : null
}

output "lambda_role_name" {
  description = "Name of the Lambda execution role (if created)"
  value       = var.create_lambda_role ? aws_iam_role.lambda_execution[0].name : null
}
