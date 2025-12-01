# Tenant Module Outputs

output "tenant_id" {
  description = "Tenant identifier"
  value       = var.tenant_id
}

output "deployment_mode" {
  description = "Deployment mode: 'gateway' or 'network_server'"
  value       = var.deployment_mode
}

output "thing_names" {
  description = "List of IoT Thing names created for this tenant"
  value = var.deployment_mode == "gateway" ? [
    for thing in aws_iot_thing.gateways : thing.name
  ] : [
    aws_iot_thing.network_server[0].name
  ]
}

output "thing_arns" {
  description = "List of IoT Thing ARNs"
  value = var.deployment_mode == "gateway" ? [
    for thing in aws_iot_thing.gateways : thing.arn
  ] : [
    aws_iot_thing.network_server[0].arn
  ]
}

output "certificate_arns" {
  description = "List of certificate ARNs for this tenant's devices"
  value = var.deployment_mode == "gateway" ? [
    for cert in aws_iot_certificate.gateways : cert.arn
  ] : [
    aws_iot_certificate.network_server[0].arn
  ]
  sensitive = true
}

output "certificate_pems" {
  description = "Map of thing names to certificate PEMs"
  value = var.deployment_mode == "gateway" ? {
    for thing_name, cert in aws_iot_certificate.gateways : thing_name => cert.certificate_pem
  } : {
    (aws_iot_thing.network_server[0].name) = aws_iot_certificate.network_server[0].certificate_pem
  }
  sensitive = true
}

output "private_keys" {
  description = "Map of thing names to private keys"
  value = var.deployment_mode == "gateway" ? {
    for thing_name, cert in aws_iot_certificate.gateways : thing_name => cert.private_key
  } : {
    (aws_iot_thing.network_server[0].name) = aws_iot_certificate.network_server[0].private_key
  }
  sensitive = true
}

# Network Server specific outputs (only populated in network_server mode)
output "network_server_thing_name" {
  description = "Name of the network server IoT thing (only in network_server mode)"
  value       = var.deployment_mode == "network_server" ? aws_iot_thing.network_server[0].name : null
}

output "network_server_thing_arn" {
  description = "ARN of the network server IoT thing (only in network_server mode)"
  value       = var.deployment_mode == "network_server" ? aws_iot_thing.network_server[0].arn : null
}

output "network_server_certificate_pem" {
  description = "Certificate PEM for network server (only in network_server mode)"
  value       = var.deployment_mode == "network_server" ? aws_iot_certificate.network_server[0].certificate_pem : null
  sensitive   = true
}

output "network_server_private_key" {
  description = "Private key for network server (only in network_server mode)"
  value       = var.deployment_mode == "network_server" ? aws_iot_certificate.network_server[0].private_key : null
  sensitive   = true
}

output "policy_name" {
  description = "Name of the IoT policy for this tenant"
  value       = aws_iot_policy.tenant.name
}

output "policy_arn" {
  description = "ARN of the IoT policy"
  value       = aws_iot_policy.tenant.arn
}

output "iot_rule_name" {
  description = "Name of the IoT Rules Engine rule for this tenant"
  value       = aws_iot_topic_rule.tenant_to_kinesis.name
}

output "iot_rule_arn" {
  description = "ARN of the IoT rule"
  value       = aws_iot_topic_rule.tenant_to_kinesis.arn
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for tenant alerts"
  value       = aws_sns_topic.tenant_alerts.arn
}

output "sns_topic_name" {
  description = "Name of the SNS topic"
  value       = aws_sns_topic.tenant_alerts.name
}

output "mqtt_topics" {
  description = "MQTT topics for this tenant"
  value = {
    sensor_data   = "smdh/${var.tenant_id}/+/sensor-data"
    device_status = "smdh/${var.tenant_id}/+/device-status"
    commands      = "smdh/${var.tenant_id}/commands/+"
    errors        = "smdh/errors/${var.tenant_id}"
  }
}

output "deployment_config" {
  description = "Configuration for device deployment"
  value = {
    tenant_id       = var.tenant_id
    deployment_mode = var.deployment_mode
    num_devices     = var.deployment_mode == "gateway" ? length(aws_iot_thing.gateways) : 1
    device_type     = var.deployment_mode == "gateway" ? "LoRaWAN Gateway" : "Network Server"
    mqtt_topics     = {
      publish   = ["smdh/${var.tenant_id}/{site_id}/sensor-data"]
      subscribe = ["smdh/${var.tenant_id}/commands/#"]
    }
    network_server_name = var.deployment_mode == "network_server" ? var.network_server_name : null
  }
}

# ============================================================================
# Thing Group Outputs
# ============================================================================

output "tenant_thing_group_name" {
  description = "Name of the tenant-level thing group"
  value       = aws_iot_thing_group.tenant.name
}

output "tenant_thing_group_arn" {
  description = "ARN of the tenant-level thing group"
  value       = aws_iot_thing_group.tenant.arn
}

output "site_thing_group_names" {
  description = "Map of site IDs to thing group names"
  value = {
    for site_id, group in aws_iot_thing_group.sites : site_id => group.name
  }
}

output "site_thing_group_arns" {
  description = "Map of site IDs to thing group ARNs"
  value = {
    for site_id, group in aws_iot_thing_group.sites : site_id => group.arn
  }
}

output "disconnected_devices_group_name" {
  description = "Name of the dynamic disconnected devices thing group"
  value       = aws_iot_thing_group.disconnected_devices.name
}

output "active_devices_group_name" {
  description = "Name of the dynamic active devices thing group"
  value       = aws_iot_thing_group.active_devices.name
}

output "thing_groups_hierarchy" {
  description = "Complete thing group hierarchy for the tenant"
  value = {
    tenant_group = aws_iot_thing_group.tenant.name
    site_groups  = [for group in aws_iot_thing_group.sites : group.name]
    dynamic_groups = {
      disconnected = aws_iot_thing_group.disconnected_devices.name
      active       = aws_iot_thing_group.active_devices.name
    }
  }
}


# ============================================================================
# Management Outputs
# ============================================================================

output "site_device_mapping" {
  description = "Mapping of sites to their devices and thing groups"
  value = {
    for site_id in local.site_ids : site_id => {
      thing_group_name = aws_iot_thing_group.sites[site_id].name
      devices          = [for gw in local.gateway_things : gw.thing_name if gw.site_id == site_id]
    }
  }
}
