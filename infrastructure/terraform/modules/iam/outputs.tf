# IAM Module Outputs

output "snowflake_role_arn" {
  description = "ARN of the IAM role for Snowflake to assume"
  value       = aws_iam_role.snowflake_kinesis.arn
}

output "snowflake_role_name" {
  description = "Name of the IAM role for Snowflake"
  value       = aws_iam_role.snowflake_kinesis.name
}

output "snowflake_role_id" {
  description = "Unique ID of the IAM role for Snowflake"
  value       = aws_iam_role.snowflake_kinesis.id
}

output "lambda_role_arn" {
  description = "ARN of the Lambda execution role (if created)"
  value       = var.create_lambda_role ? aws_iam_role.lambda_execution[0].arn : null
}

output "lambda_role_name" {
  description = "Name of the Lambda execution role (if created)"
  value       = var.create_lambda_role ? aws_iam_role.lambda_execution[0].name : null
}
