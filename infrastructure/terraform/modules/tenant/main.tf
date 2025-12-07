# SMDH Tenant Module
# Creates per-tenant resources: Kinesis Stream, IoT Things, Certificates, Policies, and Rules
#
# ARCHITECTURE: Per-Tenant Kinesis Streams
# Each tenant gets their own dedicated Kinesis stream for Snowflake Openflow integration.
# The Openflow connector cannot filter records from a shared stream, so per-tenant streams
# are required for proper data isolation.

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

locals {
  # Generate site IDs based on num_sites
  site_ids = [for i in range(1, var.num_sites + 1) : format("site_%03d", i)]

  # Deployment mode flags
  is_gateway_mode        = var.deployment_mode == "gateway"
  is_network_server_mode = var.deployment_mode == "network_server"

  # Create gateway thing names (only used in gateway mode)
  gateway_things = local.is_gateway_mode ? [for site_id in local.site_ids : {
    site_id    = site_id
    thing_name = "smdh-gateway-${var.tenant_id}-${site_id}-gw_001"
  }] : []

  # Network server thing name (only used in network_server mode)
  network_server_thing_name = "smdh-ns-${var.tenant_id}-${var.network_server_name}"

  # Per-tenant Kinesis stream name
  kinesis_stream_name = "smdh-${var.tenant_id}-stream"
}

# ============================================================================
# Per-Tenant Kinesis Stream (Required for Snowflake Openflow Integration)
# ============================================================================

# Kinesis Data Stream - On-demand mode for per-tenant data isolation
resource "aws_kinesis_stream" "tenant" {
  name = local.kinesis_stream_name

  # On-demand mode - automatically scales with throughput
  stream_mode_details {
    stream_mode = "ON_DEMAND"
  }

  # Retention period
  retention_period = var.kinesis_retention_hours

  # Encryption at rest using AWS managed keys
  encryption_type = "KMS"
  kms_key_id      = "alias/aws/kinesis"

  # Enable enhanced monitoring for per-tenant visibility
  shard_level_metrics = var.enable_monitoring ? [
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
      Name        = local.kinesis_stream_name
      TenantId    = var.tenant_id
      Description = "Per-tenant sensor data stream for Snowflake Openflow"
      Purpose     = "IoT Data Ingestion"
      DataFlow    = "IoT-to-Snowflake"
    }
  )
}

# CloudWatch alarm for tenant stream iterator age (processing lag)
resource "aws_cloudwatch_metric_alarm" "kinesis_iterator_age" {
  count = var.enable_monitoring ? 1 : 0

  alarm_name          = "${local.kinesis_stream_name}-iterator-age-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "GetRecords.IteratorAgeMilliseconds"
  namespace           = "AWS/Kinesis"
  period              = 60
  statistic           = "Maximum"
  threshold           = 60000 # 60 seconds
  alarm_description   = "Alert when Kinesis iterator age exceeds 60s for tenant ${var.tenant_id}"
  treat_missing_data  = "notBreaching"

  dimensions = {
    StreamName = aws_kinesis_stream.tenant.name
  }

  alarm_actions = [aws_sns_topic.tenant_alerts.arn]

  tags = merge(
    var.tags,
    {
      TenantId = var.tenant_id
    }
  )
}

# Create IoT Things for each gateway
resource "aws_iot_thing" "gateways" {
  for_each = { for gw in local.gateway_things : gw.thing_name => gw }

  name           = each.value.thing_name
  thing_type_name = var.lorawan_thing_type_name

  attributes = {
    tenant_id       = var.tenant_id
    site_id         = each.value.site_id
    device_type     = "gateway"
    deployment_date = timestamp()
    managed_by      = "terraform"
  }
}

# Generate X.509 certificates for each gateway
resource "aws_iot_certificate" "gateways" {
  for_each = { for gw in local.gateway_things : gw.thing_name => gw }

  active = true
}

# Attach certificates to things
resource "aws_iot_thing_principal_attachment" "gateways" {
  for_each = { for gw in local.gateway_things : gw.thing_name => gw }

  principal = aws_iot_certificate.gateways[each.key].arn
  thing     = aws_iot_thing.gateways[each.key].name
}

# ============================================================================
# Network Server Resources (ChirpStack mode)
# ============================================================================

# Create IoT Thing for network server (only in network_server mode)
resource "aws_iot_thing" "network_server" {
  count = local.is_network_server_mode ? 1 : 0

  name            = local.network_server_thing_name
  thing_type_name = var.network_server_thing_type_name

  attributes = {
    tenant_id       = var.tenant_id
    device_type     = "network_server"
    server_type     = var.network_server_name
    deployment_date = timestamp()
    managed_by      = "terraform"
  }
}

# Generate X.509 certificate for network server
resource "aws_iot_certificate" "network_server" {
  count = local.is_network_server_mode ? 1 : 0

  active = true
}

# Attach certificate to network server thing
resource "aws_iot_thing_principal_attachment" "network_server" {
  count = local.is_network_server_mode ? 1 : 0

  principal = aws_iot_certificate.network_server[0].arn
  thing     = aws_iot_thing.network_server[0].name
}

# ============================================================================
# IoT Policy (supports both gateway and network_server modes)
# ============================================================================

# Create IoT Policy for tenant (with strict topic isolation)
resource "aws_iot_policy" "tenant" {
  name = "smdh-policy-${var.tenant_id}"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Allow connecting with tenant-specific client IDs
      # Supports both gateway pattern (smdh-gateway-{tenant}-*) and NS pattern (smdh-ns-{tenant}-*)
      {
        Effect = "Allow"
        Action = "iot:Connect"
        Resource = [
          "arn:aws:iot:${var.aws_region}:${var.aws_account_id}:client/smdh-gateway-${var.tenant_id}-*",
          "arn:aws:iot:${var.aws_region}:${var.aws_account_id}:client/smdh-ns-${var.tenant_id}-*"
        ]
      },
      # Allow publishing to tenant-specific topics only
      {
        Effect = "Allow"
        Action = "iot:Publish"
        Resource = [
          "arn:aws:iot:${var.aws_region}:${var.aws_account_id}:topic/smdh/${var.tenant_id}/*/sensor-data",
          "arn:aws:iot:${var.aws_region}:${var.aws_account_id}:topic/smdh/${var.tenant_id}/*/device-status"
        ]
      },
      # Allow subscribing to tenant command topics
      {
        Effect = "Allow"
        Action = "iot:Subscribe"
        Resource = "arn:aws:iot:${var.aws_region}:${var.aws_account_id}:topicfilter/smdh/${var.tenant_id}/commands/*"
      },
      # Allow receiving on subscribed topics
      {
        Effect = "Allow"
        Action = "iot:Receive"
        Resource = "arn:aws:iot:${var.aws_region}:${var.aws_account_id}:topic/smdh/${var.tenant_id}/commands/*"
      }
    ]
  })

  # Ignore tag changes due to AWS provider default_tags inconsistency with IoT resources
  lifecycle {
    ignore_changes = [tags, tags_all]
  }
}

# Attach policy to gateway certificates (gateway mode)
resource "aws_iot_policy_attachment" "gateways" {
  for_each = { for gw in local.gateway_things : gw.thing_name => gw }

  policy = aws_iot_policy.tenant.name
  target = aws_iot_certificate.gateways[each.key].arn
}

# Attach policy to network server certificate (network_server mode)
resource "aws_iot_policy_attachment" "network_server" {
  count = local.is_network_server_mode ? 1 : 0

  policy = aws_iot_policy.tenant.name
  target = aws_iot_certificate.network_server[0].arn
}

# Create IoT Rule to route tenant data to tenant's dedicated Kinesis stream
resource "aws_iot_topic_rule" "tenant_to_kinesis" {
  name        = "smdh_route_${replace(var.tenant_id, "-", "_")}"
  description = "Route ${var.tenant_id} sensor data to dedicated Kinesis stream"
  enabled     = true

  sql         = "SELECT *, topic(2) as tenant_id, topic(3) as site_id, timestamp() as iot_timestamp, clientId() as device_id FROM 'smdh/${var.tenant_id}/+/sensor-data'"
  sql_version = "2016-03-23"

  kinesis {
    role_arn      = var.iot_kinesis_role_arn
    stream_name   = aws_kinesis_stream.tenant.name  # Use tenant's dedicated stream
    partition_key = "$${topic(3)}"                  # Partition by site_id for ordering
  }

  error_action {
    republish {
      role_arn = var.iot_kinesis_role_arn
      topic    = "smdh/errors/${var.tenant_id}"
      qos      = 1
    }
  }

  tags = merge(
    var.tags,
    {
      TenantId = var.tenant_id
      Purpose  = "Sensor Data Routing"
    }
  )

  # Ignore tag changes due to AWS provider default_tags inconsistency with IoT resources
  lifecycle {
    ignore_changes = [tags_all]
  }

  depends_on = [aws_kinesis_stream.tenant]
}

# SNS Topic for tenant-specific alerts
resource "aws_sns_topic" "tenant_alerts" {
  name = "smdh-alerts-${var.tenant_id}"

  tags = merge(
    var.tags,
    {
      TenantId = var.tenant_id
      Purpose  = "Tenant Alerts"
    }
  )
}

# SNS subscription for tenant contact email
resource "aws_sns_topic_subscription" "tenant_email" {
  count = var.contact_email != "" ? 1 : 0

  topic_arn = aws_sns_topic.tenant_alerts.arn
  protocol  = "email"
  endpoint  = var.contact_email
}

# CloudWatch Alarm: Connection Failures for this tenant
resource "aws_cloudwatch_metric_alarm" "connection_failures" {
  count = var.enable_monitoring ? 1 : 0

  alarm_name          = "smdh-${var.tenant_id}-connection-failures"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Connect.ClientError"
  namespace           = "AWS/IoT"
  period              = 300
  statistic           = "Sum"
  threshold           = 5
  alarm_description   = "Alert when ${var.tenant_id} connection failures exceed 5 in 5 minutes"
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.tenant_alerts.arn]

  tags = merge(
    var.tags,
    {
      TenantId = var.tenant_id
    }
  )
}

# CloudWatch Alarm: Message failures for this tenant
resource "aws_cloudwatch_metric_alarm" "message_failures" {
  count = var.enable_monitoring ? 1 : 0

  alarm_name          = "smdh-${var.tenant_id}-message-failures"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "RuleMessageThrottled"
  namespace           = "AWS/IoT"
  period              = 300
  statistic           = "Sum"
  threshold           = 10
  alarm_description   = "Alert when ${var.tenant_id} has more than 10 throttled messages in 5 minutes"
  treat_missing_data  = "notBreaching"

  dimensions = {
    RuleName = aws_iot_topic_rule.tenant_to_kinesis.name
  }

  alarm_actions = [aws_sns_topic.tenant_alerts.arn]

  tags = merge(
    var.tags,
    {
      TenantId = var.tenant_id
    }
  )
}

# ============================================================================
# Thing Groups - Hierarchical Device Organization
# ============================================================================

# Create tenant-level thing group (parent group for all sites)
resource "aws_iot_thing_group" "tenant" {
  name = "smdh-tenant-${var.tenant_id}"

  properties {
    description = "All IoT devices for tenant: ${var.tenant_name}"
    attribute_payload {
      attributes = {
        tenant_id   = var.tenant_id
        tenant_name = replace(var.tenant_name, " ", "_")
        managed_by  = "terraform"
        purpose     = "tenant-wide-grouping"
      }
    }
  }

  tags = merge(
    var.tags,
    {
      Name       = "smdh-tenant-${var.tenant_id}"
      TenantId   = var.tenant_id
      TenantName = var.tenant_name
      Purpose    = "Tenant Thing Group"
    }
  )

  # Ignore tag changes due to AWS provider default_tags inconsistency with IoT resources
  lifecycle {
    ignore_changes = [tags_all]
  }
}

# Create site-level thing groups (one per site)
resource "aws_iot_thing_group" "sites" {
  for_each = { for site_id in local.site_ids : site_id => site_id }

  name              = "smdh-${var.tenant_id}-${each.value}"
  parent_group_name = aws_iot_thing_group.tenant.name

  properties {
    description = "IoT devices at ${var.tenant_name} - ${each.value}"
    attribute_payload {
      attributes = {
        tenant_id  = var.tenant_id
        site_id    = each.value
        managed_by = "terraform"
        purpose    = "site-grouping"
      }
    }
  }

  tags = merge(
    var.tags,
    {
      Name       = "smdh-${var.tenant_id}-${each.value}"
      TenantId   = var.tenant_id
      SiteId     = each.value
      Purpose    = "Site Thing Group"
    }
  )

  # Ignore tag changes due to AWS provider default_tags inconsistency with IoT resources
  lifecycle {
    ignore_changes = [tags_all]
  }
}

# Add gateways to their respective site thing groups (gateway mode)
resource "aws_iot_thing_group_membership" "gateways_to_sites" {
  for_each = { for gw in local.gateway_things : gw.thing_name => gw }

  thing_name       = aws_iot_thing.gateways[each.key].name
  thing_group_name = aws_iot_thing_group.sites[each.value.site_id].name

  # Override the group's configuration if needed
  override_dynamic_group = false
}

# Add network server to tenant thing group (network_server mode)
# Network server is added directly to tenant group since it serves all sites
resource "aws_iot_thing_group_membership" "network_server_to_tenant" {
  count = local.is_network_server_mode ? 1 : 0

  thing_name       = aws_iot_thing.network_server[0].name
  thing_group_name = aws_iot_thing_group.tenant.name

  override_dynamic_group = false
}

# Dynamic Thing Group: Disconnected devices (query-based)
resource "aws_iot_thing_group" "disconnected_devices" {
  name = "smdh-${var.tenant_id}-disconnected"

  properties {
    description = "Dynamically tracks disconnected devices for ${var.tenant_name}"
    attribute_payload {
      attributes = {
        tenant_id  = var.tenant_id
        managed_by = "terraform"
        purpose    = "connectivity-monitoring"
        type       = "dynamic"
      }
    }
  }

  tags = merge(
    var.tags,
    {
      Name       = "smdh-${var.tenant_id}-disconnected"
      TenantId   = var.tenant_id
      Purpose    = "Dynamic Group - Disconnected Devices"
      GroupType  = "Dynamic"
    }
  )

  # Ignore tag changes due to AWS provider default_tags inconsistency with IoT resources
  lifecycle {
    ignore_changes = [tags_all]
  }
}

# Dynamic Thing Group: Recently active devices (connected in last hour)
resource "aws_iot_thing_group" "active_devices" {
  name = "smdh-${var.tenant_id}-active"

  properties {
    description = "Dynamically tracks active devices for ${var.tenant_name}"
    attribute_payload {
      attributes = {
        tenant_id  = var.tenant_id
        managed_by = "terraform"
        purpose    = "activity-monitoring"
        type       = "dynamic"
      }
    }
  }

  tags = merge(
    var.tags,
    {
      Name       = "smdh-${var.tenant_id}-active"
      TenantId   = var.tenant_id
      Purpose    = "Dynamic Group - Active Devices"
      GroupType  = "Dynamic"
    }
  )

  # Ignore tag changes due to AWS provider default_tags inconsistency with IoT resources
  lifecycle {
    ignore_changes = [tags_all]
  }
}

