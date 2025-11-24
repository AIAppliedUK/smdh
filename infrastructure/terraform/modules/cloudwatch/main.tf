# SMDH CloudWatch Module
# Creates log groups, dashboards, and alarms for monitoring

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# CloudWatch Log Group for IoT Core logs
resource "aws_cloudwatch_log_group" "iot" {
  name              = "/aws/iot/${var.project_name}"
  retention_in_days = var.log_retention_days

  tags = merge(
    var.tags,
    {
      Name        = "/aws/iot/${var.project_name}"
      Description = "IoT Core logs for SMDH platform"
    }
  )
}

# CloudWatch Dashboard for platform monitoring
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.project_name}-platform-${var.environment}"

  dashboard_body = jsonencode({
    widgets = [
      # IoT Core Metrics
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/IoT", "PublishIn.Success", { stat = "Sum", label = "Messages Published (Success)" }],
            [".", "PublishIn.Failure", { stat = "Sum", label = "Messages Published (Failure)" }],
            [".", "Connect.Success", { stat = "Sum", label = "Connections (Success)" }],
            [".", "Connect.ClientError", { stat = "Sum", label = "Connections (Client Error)" }]
          ]
          period = 300
          stat   = "Sum"
          region = var.aws_region
          title  = "IoT Core - Message & Connection Metrics"
          yAxis = {
            left = {
              min = 0
            }
          }
        }
      },
      # Kinesis Metrics
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/Kinesis", "GetRecords.IteratorAgeMilliseconds", { stat = "Maximum", label = "Iterator Age (ms)" }],
            [".", "IncomingRecords", { stat = "Sum", label = "Incoming Records" }],
            [".", "IncomingBytes", { stat = "Sum", label = "Incoming Bytes" }]
          ]
          period = 300
          stat   = "Average"
          region = var.aws_region
          title  = "Kinesis Stream - Performance Metrics"
          yAxis = {
            left = {
              min = 0
            }
          }
        }
      },
      # Certificate Expiry
      {
        type = "metric"
        properties = {
          metrics = [
            ["AWS/IoT", "Ping.Success", { stat = "Sum", label = "Active Connections" }]
          ]
          period = 300
          stat   = "Sum"
          region = var.aws_region
          title  = "IoT Core - Active Device Connections"
        }
      }
    ]
  })
}

# SNS Topic for alarms
resource "aws_sns_topic" "alarms" {
  name = "${var.project_name}-platform-alarms-${var.environment}"

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-platform-alarms"
      Description = "Platform-level alarm notifications"
    }
  )
}

# SNS Topic Subscription (email)
resource "aws_sns_topic_subscription" "alarm_email" {
  count = var.alert_email != "" ? 1 : 0

  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# Alarm: IoT Connection Failures
resource "aws_cloudwatch_metric_alarm" "iot_connection_failures" {
  alarm_name          = "${var.project_name}-iot-connection-failures-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Connect.ClientError"
  namespace           = "AWS/IoT"
  period              = 300
  statistic           = "Sum"
  threshold           = 5
  alarm_description   = "Alert when IoT connection failures exceed 5 in 5 minutes"
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.alarms.arn]

  tags = var.tags
}

# Alarm: IoT Message Publish Failures
resource "aws_cloudwatch_metric_alarm" "iot_publish_failures" {
  alarm_name          = "${var.project_name}-iot-publish-failures-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "PublishIn.Failure"
  namespace           = "AWS/IoT"
  period              = 300
  statistic           = "Sum"
  threshold           = 10
  alarm_description   = "Alert when IoT message publish failures exceed 10 in 5 minutes"
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.alarms.arn]

  tags = var.tags
}

# Alarm: No Data Received (Zero messages for 30 minutes)
resource "aws_cloudwatch_metric_alarm" "no_data_received" {
  alarm_name          = "${var.project_name}-no-data-received-${var.environment}"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "PublishIn.Success"
  namespace           = "AWS/IoT"
  period              = 1800
  statistic           = "Sum"
  threshold           = 1
  alarm_description   = "Alert when no IoT messages received for 30 minutes"
  treat_missing_data  = "breaching"

  alarm_actions = [aws_sns_topic.alarms.arn]

  tags = var.tags
}
