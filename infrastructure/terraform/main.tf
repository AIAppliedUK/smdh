# SMDH Root Terraform Configuration
# Orchestrates all modules to deploy complete SMDH infrastructure

# Core Infrastructure Modules

# IoT Core - MQTT broker and thing types
module "iot_core" {
  source = "./modules/iot-core"

  project_name              = var.project_name
  environment               = var.environment
  lorawan_thing_type_name   = "LoRaWANGateway"
  devtank_thing_type_name   = "DevTankOSM"
  log_level                 = var.environment == "prod" ? "INFO" : "DEBUG"
  kinesis_stream_arns       = [module.kinesis.stream_arn]

  tags = merge(
    local.common_tags,
    {
      Component   = "IoT-Core"
      Service     = "AWS-IoT"
      Description = "MQTT broker and device registry"
    }
  )
}

# Kinesis - Data stream for sensor data buffering
module "kinesis" {
  source = "./modules/kinesis"

  stream_name                = "${var.project_name}-sensor-data-stream"
  retention_hours            = var.kinesis_retention_hours
  encryption_type            = "KMS"
  enable_enhanced_monitoring = true
  enable_monitoring          = var.enable_monitoring
  iterator_age_threshold_ms  = 60000 # 60 seconds
  alarm_actions              = var.enable_monitoring ? [module.cloudwatch.sns_topic_arn] : []

  tags = merge(
    local.common_tags,
    {
      Component   = "Data-Ingestion"
      Service     = "Kinesis-Stream"
      Description = "Sensor data buffer and ordering"
      DataFlow    = "IoT-to-Snowflake"
    }
  )
}

# IAM - Roles for Snowflake and service integrations
module "iam" {
  source = "./modules/iam"

  project_name           = var.project_name
  environment            = var.environment
  snowflake_account_id   = var.snowflake_account_id
  snowflake_external_id  = var.snowflake_external_id
  kinesis_stream_arns    = [module.kinesis.stream_arn]
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

# Tenant Resources - Per-tenant IoT things, certificates, policies, rules
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
  kinesis_stream_name            = module.kinesis.stream_name
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

  depends_on = [
    module.iot_core,
    module.kinesis
  ]
}
