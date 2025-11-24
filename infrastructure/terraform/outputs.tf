# SMDH Terraform Outputs
# Export important values for use by other systems and documentation

output "iot_endpoint" {
  description = "AWS IoT Core endpoint for MQTT connections"
  value       = module.iot_core.iot_endpoint
}

output "iot_endpoint_address" {
  description = "Full IoT Core endpoint address for device configuration"
  value       = module.iot_core.iot_endpoint_address
}

output "kinesis_stream_name" {
  description = "Name of the Kinesis data stream"
  value       = module.kinesis.stream_name
}

output "kinesis_stream_arn" {
  description = "ARN of the Kinesis data stream"
  value       = module.kinesis.stream_arn
}

output "snowflake_iam_role_arn" {
  description = "IAM role ARN for Snowflake to assume (for Openflow connector)"
  value       = module.iam.snowflake_role_arn
  sensitive   = true
}

output "secrets_manager_secret_arn" {
  description = "ARN of Secrets Manager secret for Snowflake credentials"
  value       = module.secrets_manager.secret_arn
  sensitive   = true
}

output "cloudwatch_log_group" {
  description = "CloudWatch log group name for IoT Core logs"
  value       = module.cloudwatch.log_group_name
}

output "cloudwatch_dashboard_url" {
  description = "URL to CloudWatch dashboard"
  value       = "https://console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${module.cloudwatch.dashboard_name}"
}

output "tenant_configurations" {
  description = "Configuration details for each tenant"
  value = {
    for tenant_id, tenant_config in module.tenants : tenant_id => {
      thing_names              = tenant_config.thing_names
      policy_name              = tenant_config.policy_name
      iot_rule_name            = tenant_config.iot_rule_name
      certificate_count        = length(tenant_config.certificate_arns)
      sns_topic_arn            = tenant_config.sns_topic_arn
      tenant_thing_group_name  = tenant_config.tenant_thing_group_name
      tenant_thing_group_arn   = tenant_config.tenant_thing_group_arn
      site_thing_groups        = tenant_config.site_thing_group_names
      num_sites                = length(tenant_config.site_thing_group_names)
    }
  }
  sensitive = true
}

output "tenant_certificate_arns" {
  description = "Certificate ARNs for each tenant (sensitive)"
  value = {
    for tenant_id, tenant_config in module.tenants : tenant_id => tenant_config.certificate_arns
  }
  sensitive = true
}

output "deployment_summary" {
  description = "Summary of deployed resources"
  value = {
    aws_account_id        = data.aws_caller_identity.current.account_id
    aws_region            = var.aws_region
    environment           = var.environment
    iot_endpoint          = module.iot_core.iot_endpoint
    kinesis_stream        = module.kinesis.stream_name
    tenant_count          = length(var.tenants)
    monitoring_enabled    = var.enable_monitoring
    deletion_protection   = var.enable_deletion_protection
    deployed_at           = timestamp()
  }
}

# ============================================================================
# Thing Group Outputs
# ============================================================================

output "thing_group_hierarchy" {
  description = "Complete thing group hierarchy for all tenants"
  value = {
    for tenant_id, tenant_config in module.tenants : tenant_id => {
      tenant_group  = tenant_config.tenant_thing_group_name
      site_groups   = tenant_config.site_thing_group_names
      dynamic_groups = {
        disconnected = tenant_config.disconnected_devices_group_name
        active       = tenant_config.active_devices_group_name
      }
    }
  }
}

output "site_device_mapping" {
  description = "Mapping of sites to devices and thing groups"
  value = {
    for tenant_id, tenant_config in module.tenants : tenant_id => tenant_config.site_device_mapping
  }
}

# ============================================================================
# Snowflake Integration Outputs
# ============================================================================

output "snowflake_sync_data" {
  description = "Structured data for syncing to Snowflake infrastructure tables"
  value = {
    for tenant_id, tenant_config in module.tenants : tenant_id => {
      tenant_id                = tenant_id
      tenant_thing_group_name  = tenant_config.tenant_thing_group_name
      tenant_thing_group_arn   = tenant_config.tenant_thing_group_arn
      aws_region               = var.aws_region
      iot_endpoint             = module.iot_core.iot_endpoint
      kinesis_stream_name      = module.kinesis.stream_name
      sites = {
        for site_id, group_name in tenant_config.site_thing_group_names : site_id => {
          site_thing_group_name = group_name
          site_thing_group_arn  = tenant_config.site_thing_group_arns[site_id]
          devices               = tenant_config.site_device_mapping[site_id].devices
        }
      }
    }
  }
}

# Export for use in scripts
output "configuration_json" {
  description = "Complete configuration in JSON format for scripts"
  value = jsonencode({
    aws_account_id    = data.aws_caller_identity.current.account_id
    aws_region        = var.aws_region
    iot_endpoint      = module.iot_core.iot_endpoint
    kinesis_stream    = module.kinesis.stream_name
    tenants           = {
      for tenant_id, tenant_config in module.tenants : tenant_id => {
        policy_name              = tenant_config.policy_name
        rule_name                = tenant_config.iot_rule_name
        things                   = tenant_config.thing_names
        tenant_thing_group       = tenant_config.tenant_thing_group_name
        site_thing_groups        = tenant_config.site_thing_group_names
        disconnected_group       = tenant_config.disconnected_devices_group_name
        active_devices_group     = tenant_config.active_devices_group_name
      }
    }
  })
  sensitive = true
}

# ============================================================================
# Monitoring and Operations Outputs
# ============================================================================

output "monitoring_commands" {
  description = "Useful commands for monitoring thing groups"
  value = {
    check_health = "cd infrastructure/scripts && ./check_system_health.sh --tenant-id <tenant_id>"
    sync_to_snowflake = "cd infrastructure/snowflake/scripts && ./sync_aws_iot_metadata.sh --tenant-id <tenant_id>"
    list_thing_groups = "aws iot list-thing-groups --region ${var.aws_region}"
  }
}

output "thing_group_queries" {
  description = "AWS CLI queries for thing group operations"
  value = {
    for tenant_id, tenant_config in module.tenants : tenant_id => {
      list_all_devices = "aws iot list-things-in-thing-group --thing-group-name ${tenant_config.tenant_thing_group_name} --recursive --region ${var.aws_region}"
      check_disconnected = "aws iot list-things-in-thing-group --thing-group-name ${tenant_config.disconnected_devices_group_name} --region ${var.aws_region}"
    }
  }
}
