# Kinesis Module Outputs

output "stream_name" {
  description = "Name of the Kinesis data stream"
  value       = aws_kinesis_stream.sensor_data.name
}

output "stream_arn" {
  description = "ARN of the Kinesis data stream"
  value       = aws_kinesis_stream.sensor_data.arn
}

output "stream_id" {
  description = "Unique identifier for the stream"
  value       = aws_kinesis_stream.sensor_data.id
}

output "shard_count" {
  description = "Current number of shards (for on-demand, this is managed automatically)"
  value       = aws_kinesis_stream.sensor_data.shard_count
}

output "retention_hours" {
  description = "Data retention period in hours"
  value       = aws_kinesis_stream.sensor_data.retention_period
}

output "encryption_type" {
  description = "Encryption type used"
  value       = aws_kinesis_stream.sensor_data.encryption_type
}

output "iterator_age_alarm_arn" {
  description = "ARN of the iterator age CloudWatch alarm"
  value       = var.enable_monitoring ? aws_cloudwatch_metric_alarm.iterator_age[0].arn : null
}

output "stream_mode" {
  description = "Stream mode (ON_DEMAND or PROVISIONED)"
  value       = aws_kinesis_stream.sensor_data.stream_mode_details[0].stream_mode
}
