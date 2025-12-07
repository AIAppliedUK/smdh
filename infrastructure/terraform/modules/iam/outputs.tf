# IAM Module Outputs

# OpenFlow IAM User Outputs
output "openflow_user_name" {
  description = "Name of the IAM user for OpenFlow Kinesis connector"
  value       = aws_iam_user.openflow_kinesis.name
}

output "openflow_user_arn" {
  description = "ARN of the IAM user for OpenFlow Kinesis connector"
  value       = aws_iam_user.openflow_kinesis.arn
}

output "openflow_access_key_id" {
  description = "Access Key ID for OpenFlow Kinesis connector (use in Snowsight OpenFlow config)"
  value       = aws_iam_access_key.openflow_kinesis.id
  sensitive   = true
}

output "openflow_secret_access_key" {
  description = "Secret Access Key for OpenFlow Kinesis connector (use in Snowsight OpenFlow config)"
  value       = aws_iam_access_key.openflow_kinesis.secret
  sensitive   = true
}

# Lambda Role Outputs (optional)
output "lambda_role_arn" {
  description = "ARN of the Lambda execution role (if created)"
  value       = var.create_lambda_role ? aws_iam_role.lambda_execution[0].arn : null
}

output "lambda_role_name" {
  description = "Name of the Lambda execution role (if created)"
  value       = var.create_lambda_role ? aws_iam_role.lambda_execution[0].name : null
}
