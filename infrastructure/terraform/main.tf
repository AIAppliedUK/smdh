# SMDH Root Terraform Configuration
# Orchestrates all modules to deploy complete SMDH infrastructure
#
# ARCHITECTURE: Per-Tenant Kinesis Streams
# Each tenant gets their own dedicated Kinesis stream for Snowflake Openflow integration.
# Streams are created in the tenant module (modules/tenant), NOT as a shared resource.
# This architecture is REQUIRED because Openflow cannot filter records from a shared stream.

# Core Infrastructure Modules

# IoT Core - MQTT broker and thing types
# Note: kinesis_stream_arns uses wildcard pattern to allow writing to any tenant stream
module "iot_core" {
  source = "./modules/iot-core"

  project_name              = var.project_name
  environment               = var.environment
  lorawan_thing_type_name   = "LoRaWANGateway"
  devtank_thing_type_name   = "DevTankOSM"
  log_level                 = var.environment == "prod" ? "INFO" : "DEBUG"
  # Allow IoT rules to write to any tenant stream (smdh-*-stream pattern)
  kinesis_stream_arns       = ["arn:aws:kinesis:${var.aws_region}:${data.aws_caller_identity.current.account_id}:stream/smdh-*-stream"]

  tags = merge(
    local.common_tags,
    {
      Component   = "IoT-Core"
      Service     = "AWS-IoT"
      Description = "MQTT broker and device registry"
    }
  )
}

# NOTE: Per-tenant Kinesis streams are created in modules/tenant
# Each tenant gets their own stream: smdh-{tenant_id}-stream
# This is required for Snowflake Openflow data isolation

# IAM - Roles for Snowflake/Openflow and service integrations
# Uses wildcard pattern for tenant streams since Openflow needs to read from all tenant streams
module "iam" {
  source = "./modules/iam"

  project_name           = var.project_name
  environment            = var.environment
  aws_region             = var.aws_region
  snowflake_account_id   = var.snowflake_account_id
  snowflake_external_id  = var.snowflake_external_id
  # Allow Snowflake/Openflow to read from any tenant stream (smdh-*-stream pattern)
  kinesis_stream_arns    = ["arn:aws:kinesis:${var.aws_region}:${data.aws_caller_identity.current.account_id}:stream/smdh-*-stream"]
  create_lambda_role     = false
  secrets_manager_arns   = [module.secrets_manager.secret_arn]

  tags = merge(
    local.common_tags,
    {
      Component   = "Security"
      Service     = "IAM"
      Description = "Cross-account roles and permissions"
      Integration = "Snowflake"
    }
  )
}

# Secrets Manager - Snowflake credentials storage
module "secrets_manager" {
  source = "./modules/secrets-manager"

  secret_name_prefix    = var.project_name
  recovery_window_days  = 30
  enable_rotation       = false
  snowflake_account     = var.snowflake_account_id
  snowflake_region      = var.snowflake_region
  snowflake_user        = "smdh_service_user"
  snowflake_warehouse   = "smdh_etl_wh"

  tags = merge(
    local.common_tags,
    {
      Component           = "Security"
      Service             = "Secrets-Manager"
      Description         = "Snowflake credentials and configuration"
      DataClassification  = "Restricted"
      EncryptionRequired  = "true"
    }
  )
}

# CloudWatch - Monitoring, logging, and alerting
module "cloudwatch" {
  source = "./modules/cloudwatch"

  project_name        = var.project_name
  environment         = var.environment
  aws_region          = var.aws_region
  log_retention_days  = var.log_retention_days
  alert_email         = var.alert_email

  tags = merge(
    local.common_tags,
    {
      Component   = "Monitoring"
      Service     = "CloudWatch"
      Description = "Platform monitoring and alerting"
      Critical    = "true"
    }
  )
}

# Tenant Resources - Per-tenant IoT things, certificates, policies, Kinesis streams, and rules
# Each tenant gets their own dedicated Kinesis stream for Snowflake Openflow data isolation
module "tenants" {
  source   = "./modules/tenant"
  for_each = var.tenants

  tenant_id                      = each.key
  tenant_name                    = each.value.name
  num_sites                      = each.value.num_sites
  aws_region                     = var.aws_region
  aws_account_id                 = data.aws_caller_identity.current.account_id
  lorawan_thing_type_name        = module.iot_core.lorawan_thing_type_name
  network_server_thing_type_name = module.iot_core.network_server_thing_type_name
  iot_kinesis_role_arn           = module.iot_core.iot_kinesis_role_arn
  kinesis_retention_hours        = var.kinesis_retention_hours
  contact_email                  = try(each.value.contact_email, "")
  enable_monitoring              = var.enable_monitoring

  # Deployment mode: "gateway" (default) for Milesight UG65 with built-in NS
  #                  "network_server" for ChirpStack or similar centralized NS
  deployment_mode     = try(each.value.deployment_mode, "gateway")
  network_server_name = try(each.value.network_server_name, "chirpstack")

  tags = merge(
    local.common_tags,
    {
      Component          = "Tenant-Resources"
      TenantId           = each.key
      TenantName         = each.value.name
      NumSites           = each.value.num_sites
      DeploymentMode     = try(each.value.deployment_mode, "gateway")
      Service            = "Multi-Tenant-IoT"
      BillingTenant      = each.key
      ContactEmail       = try(each.value.contact_email, "")
    }
  )

  depends_on = [module.iot_core]
}
