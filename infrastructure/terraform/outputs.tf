# SMDH Terraform Outputs
# Export important values for use by other systems and documentation
#
# ARCHITECTURE NOTE: Per-Tenant Kinesis Streams
# Each tenant has their own Kinesis stream (smdh-{tenant_id}-stream).
# Stream details are exported per-tenant, not as a shared resource.

output "iot_endpoint" {
  description = "AWS IoT Core endpoint for MQTT connections"
  value       = module.iot_core.iot_endpoint
}

output "iot_endpoint_address" {
  description = "Full IoT Core endpoint address for device configuration"
  value       = module.iot_core.iot_endpoint_address
}

# Per-tenant Kinesis stream outputs
output "tenant_kinesis_streams" {
  description = "Kinesis stream details for each tenant"
  value = {
    for tenant_id, tenant_config in module.tenants : tenant_id => {
      stream_name = tenant_config.kinesis_stream_name
      stream_arn  = tenant_config.kinesis_stream_arn
    }
  }
}

output "openflow_iam_user_arn" {
  description = "IAM user ARN for OpenFlow Kinesis connector"
  value       = module.iam.openflow_user_arn
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
      # Per-tenant Kinesis stream
      kinesis_stream_name      = tenant_config.kinesis_stream_name
      kinesis_stream_arn       = tenant_config.kinesis_stream_arn
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
    kinesis_architecture  = "per-tenant streams (smdh-{tenant_id}-stream)"
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
# Openflow Configuration Outputs
# ============================================================================

output "openflow_aws_credentials_config" {
  description = "Access keys for OpenFlow Kinesis connector (OpenFlow requires IAM access keys, not role assumption)"
  value = {
    access_key_id     = module.iam.openflow_access_key_id
    secret_access_key = module.iam.openflow_secret_access_key
    aws_region        = var.aws_region
    user_name         = module.iam.openflow_user_name
    user_arn          = module.iam.openflow_user_arn
    instructions      = "Use these credentials in Snowsight OpenFlow connector configuration"
  }
  sensitive = true
}

output "openflow_kinesis_config_per_tenant" {
  description = "Per-tenant Kinesis connector configuration for Openflow"
  value = {
    for tenant_id, tenant_config in module.tenants : tenant_id => {
      kinesis_stream_name     = tenant_config.kinesis_stream_name
      kinesis_stream_arn      = tenant_config.kinesis_stream_arn
      aws_region              = var.aws_region
      kinesis_application_name = "smdh-openflow-${tenant_id}"
      target_database         = "SMDH_TENANT_${upper(replace(tenant_id, "-", "_"))}"
      target_schema           = "RAW"
      target_table            = "SENSOR_READINGS"
    }
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
      # Per-tenant Kinesis stream
      kinesis_stream_name      = tenant_config.kinesis_stream_name
      kinesis_stream_arn       = tenant_config.kinesis_stream_arn
      # Openflow connector config
      openflow_config          = tenant_config.kinesis_stream_config
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
    tenants           = {
      for tenant_id, tenant_config in module.tenants : tenant_id => {
        policy_name              = tenant_config.policy_name
        rule_name                = tenant_config.iot_rule_name
        things                   = tenant_config.thing_names
        tenant_thing_group       = tenant_config.tenant_thing_group_name
        site_thing_groups        = tenant_config.site_thing_group_names
        disconnected_group       = tenant_config.disconnected_devices_group_name
        active_devices_group     = tenant_config.active_devices_group_name
        # Per-tenant Kinesis stream
        kinesis_stream_name      = tenant_config.kinesis_stream_name
        kinesis_stream_arn       = tenant_config.kinesis_stream_arn
        openflow_config          = tenant_config.kinesis_stream_config
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

# ============================================================================
# Certificate File Outputs
# ============================================================================

output "certificate_files" {
  description = "Paths to generated certificate files for each tenant device"
  value = {
    for key, thing_data in local.tenant_thing_keys : key => {
      certificate_path = "${local.certificates_base_path}/${thing_data.tenant_id}/${thing_data.thing_name}_certificate.pem"
      private_key_path = "${local.certificates_base_path}/${thing_data.tenant_id}/${thing_data.thing_name}_private_key.pem"
      thing_name       = thing_data.thing_name
      tenant_id        = thing_data.tenant_id
    }
  }
}
