# SMDH Kinesis Data Streams Module
# Creates Kinesis stream for buffering IoT data before Snowflake ingestion

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Kinesis Data Stream - On-demand mode
resource "aws_kinesis_stream" "sensor_data" {
  name = var.stream_name

  # On-demand mode - automatically scales with throughput
  stream_mode_details {
    stream_mode = "ON_DEMAND"
  }

  # Retention period (24 hours default, up to 365 days)
  retention_period = var.retention_hours

  # Encryption at rest using AWS managed keys
  encryption_type = var.encryption_type
  kms_key_id      = var.encryption_type == "KMS" ? var.kms_key_id : null

  # Enable enhanced monitoring
  shard_level_metrics = var.enable_enhanced_monitoring ? [
    "IncomingBytes",
    "IncomingRecords",
    "OutgoingBytes",
    "OutgoingRecords",
    "WriteProvisionedThroughputExceeded",
    "ReadProvisionedThroughputExceeded",
    "IteratorAgeMilliseconds"
  ] : []

  tags = merge(
    var.tags,
    {
      Name        = var.stream_name
      Description = "SMDH sensor data stream for IoT Core to Snowflake"
      Purpose     = "IoT Data Ingestion"
    }
  )
}

# CloudWatch metric alarm for iterator age (data processing lag)
resource "aws_cloudwatch_metric_alarm" "iterator_age" {
  count = var.enable_monitoring ? 1 : 0

  alarm_name          = "${var.stream_name}-iterator-age-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "GetRecords.IteratorAgeMilliseconds"
  namespace           = "AWS/Kinesis"
  period              = 60
  statistic           = "Maximum"
  threshold           = var.iterator_age_threshold_ms
  alarm_description   = "Alert when Kinesis iterator age exceeds ${var.iterator_age_threshold_ms}ms (data processing lag)"
  treat_missing_data  = "notBreaching"

  dimensions = {
    StreamName = aws_kinesis_stream.sensor_data.name
  }

  alarm_actions = var.alarm_actions

  tags = var.tags
}

# CloudWatch metric alarm for write throughput exceeded
resource "aws_cloudwatch_metric_alarm" "write_throughput" {
  count = var.enable_monitoring ? 1 : 0

  alarm_name          = "${var.stream_name}-write-throughput-exceeded"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "WriteProvisionedThroughputExceeded"
  namespace           = "AWS/Kinesis"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Alert when write throughput is exceeded on ${var.stream_name}"
  treat_missing_data  = "notBreaching"

  dimensions = {
    StreamName = aws_kinesis_stream.sensor_data.name
  }

  alarm_actions = var.alarm_actions

  tags = var.tags
}

# CloudWatch metric alarm for read throughput exceeded
resource "aws_cloudwatch_metric_alarm" "read_throughput" {
  count = var.enable_monitoring ? 1 : 0

  alarm_name          = "${var.stream_name}-read-throughput-exceeded"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "ReadProvisionedThroughputExceeded"
  namespace           = "AWS/Kinesis"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Alert when read throughput is exceeded on ${var.stream_name}"
  treat_missing_data  = "notBreaching"

  dimensions = {
    StreamName = aws_kinesis_stream.sensor_data.name
  }

  alarm_actions = var.alarm_actions

  tags = var.tags
}
