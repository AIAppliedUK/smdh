 SMDH Implementation Plan

 Executive Summary

This document outlines the implementation plan for the Smart Manufacturing Data Hub (SMDH) solution. **Status: IMPLEMENTED** (December 2025).

**Current State:**
- Core infrastructure deployed (AWS IoT Core, Kinesis, Snowflake OpenFlow)
- Demo tenant `manufacturing_demo` fully operational (5 sites)
- E2E pipeline tested and validated
- Deployment guides complete: `infrastructure/deployment/`

**Prerequisites (completed):**
-  Admin access to Snowflake tenant
-  AWS sandpit with CLI configured
-  Architecture documentation complete

Timeline (actual): ~4 weeks for initial implementation with single tenant

---

 . Implementation Overview

 . What We're Building

```

                     SMDH Platform                            

                                                              
  IoT Devices → AWS IoT Core → Kinesis → Snowflake Openflow 
       ↓              ↓           ↓              ↓            
  Certificates   Rules Engine   Buffer      Data Warehouse   
                                                              

```

 . Implementation Phases

| Phase | Component | Duration | Dependencies |
|-------|-----------|----------|--------------|
|  | Infrastructure as Code (Terraform) | - weeks | AWS CLI configured |
|  | Snowflake Setup Scripts |  week | Snowflake admin access |
|  | Tenant Onboarding Automation | - weeks | Phases  &  complete |
|  | Monitoring & Alerting |  week | Phase  complete |
|  | Testing & Validation |  week | All phases complete |

---

 . What Needs to Be Built

 . Infrastructure as Code (Terraform)

Purpose: Automate AWS resource provisioning and ensure consistent deployments

 .. Core AWS Infrastructure

Files to create:
```
infrastructure/terraform/
 main.tf                           Root configuration
 variables.tf                      Input variables
 outputs.tf                        Output values
 providers.tf                      AWS provider config
 modules/
    iot-core/
       main.tf                   IoT Core resources
       variables.tf
       outputs.tf
       iot-policies.tf           IoT policy templates
    kinesis/
       main.tf                   Kinesis stream
       variables.tf
       outputs.tf
    secrets-manager/
       main.tf                   Secrets Manager setup
       variables.tf
       outputs.tf
    cloudwatch/
       main.tf                   Log groups, alarms
       dashboards.tf             Dashboard configs
       alarms.tf                 Alarm rules
       variables.tf
    iam/
       main.tf                   IAM roles for Snowflake
       policies.tf               IAM policies
       outputs.tf
    tenant/
        main.tf                   Per-tenant resources
        iot-thing.tf              Thing registry
        iot-rules.tf              IoT Rules Engine
        certificates.tf           Certificate generation
        variables.tf
 environments/
     dev/
        01_tags.tfvars            Resource tagging configuration
        02_core.tfvars            Core infrastructure settings
        03_tenants.tfvars         Tenant definitions (modify for new tenants)
     prod/
        01_tags.tfvars            Production tagging
        02_core.tfvars            Production core settings
        03_tenants.tfvars         Production tenant definitions
```

Required Resources:

. AWS IoT Core
   - IoT Thing Type: `LoRaWANGateway`
   - IoT Thing registry (per tenant/gateway)
   - IoT Policies with tenant isolation
   - Certificate generation and attachment
   - IoT Rules Engine rules (per tenant)

. Kinesis Data Streams (Per-Tenant Architecture)
   - **Architecture Decision**: One Kinesis stream per tenant for data isolation
   - Stream naming: `smdh-{tenant_id}-stream` (e.g., `smdh-abc_manufacturing-stream`)
   - Mode: On-demand (auto-scaling)
   - Retention: 24 hours
   - Encryption: AWS managed keys
   - **Rationale**: Per-tenant streams provide:
     - Complete data isolation between tenants
     - Independent scaling per tenant workload
     - Simplified stream-to-table routing in Openflow
     - Easier debugging and monitoring per tenant

. Secrets Manager
   - Secret: `smdh/snowflake/private-key`
   - Rotation: Enabled ( minutes before expiry)
   - Encryption: KMS

. CloudWatch
   - Log group: `/aws/iot/smdh`
   - Retention:  days
   - Dashboards (per tenant)
   - Alarms for critical metrics

. IAM Roles
   - `smdh-iot-kinesis-role` - IoT Rules → Kinesis
   - `smdh-snowflake-kinesis-role` - Snowflake → Kinesis read

Example Terraform Structure:

```hcl
 infrastructure/terraform/main.tf
terraform {
  required_version = ">= ."

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> ."
    }
  }

  backend "s" {
    bucket = "smdh-terraform-state"
    key    = "infrastructure/terraform.tfstate"
    region = "eu-west-"
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "SMDH"
      ManagedBy   = "Terraform"
      Environment = var.environment
    }
  }
}

 Core infrastructure
 NOTE: Kinesis streams are created per-tenant in modules/tenant
 This is REQUIRED because Snowflake Openflow cannot filter from a shared stream

module "iot_core" {
  source = "./modules/iot-core"

  thing_type_name     = "LoRaWANGateway"
  environment         = var.environment
   Allow IoT rules to write to any tenant stream (wildcard pattern)
  kinesis_stream_arns = ["arn:aws:kinesis:${var.aws_region}:${data.aws_caller_identity.current.account_id}:stream/smdh-*-stream"]
}

module "cloudwatch" {
  source = "./modules/cloudwatch"

  log_retention_days = var.log_retention_days
  environment        = var.environment
}

module "iam" {
  source = "./modules/iam"

   Allow Snowflake Openflow to read from any tenant stream
  kinesis_stream_arns   = ["arn:aws:kinesis:${var.aws_region}:${data.aws_caller_identity.current.account_id}:stream/smdh-*-stream"]
  snowflake_account_id  = var.snowflake_account_id
  snowflake_external_id = var.snowflake_external_id
}

 Per-tenant resources (including dedicated Kinesis stream per tenant)
module "tenants" {
  source = "./modules/tenant"

  for_each = var.tenants

  tenant_id              = each.key
  tenant_name            = each.value.name
  num_sites              = each.value.num_sites
  iot_kinesis_role_arn   = module.iot_core.iot_kinesis_role_arn
  kinesis_retention_hours = 24
  aws_account_id         = data.aws_caller_identity.current.account_id
  aws_region             = var.aws_region
   Each tenant gets their own Kinesis stream: smdh-{tenant_id}-stream
}
```

 .. Terraform Variables

File: `infrastructure/terraform/variables.tf`

```hcl
variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "eu-west-"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 
}

variable "snowflake_account_id" {
  description = "Snowflake AWS account ID for cross-account access"
  type        = string
  sensitive   = true
}

variable "snowflake_external_id" {
  description = "External ID for Snowflake IAM role assumption"
  type        = string
  sensitive   = true
}

variable "tenants" {
  description = "Map of tenant configurations"
  type = map(object({
    name      = string
    num_sites = number
    retention_days = number
  }))
  default = {}
}
```

---

 . Snowflake Setup Scripts

Purpose: Initialize Snowflake environment, configure Openflow for Kinesis ingestion, and create tenant databases

 .. Kinesis-to-Snowflake Integration via Openflow

**Architecture Decision**: Use Snowflake Openflow Connector for native Kinesis integration

The Openflow Connector (acquired from Datavolo in 2024) provides native Kinesis Data Stream ingestion without requiring intermediate S3 storage. Key benefits:
- Real-time streaming ingestion (sub-second latency)
- Native stream-to-table routing per tenant
- DynamoDB-based checkpointing for exactly-once delivery
- Managed by Snowflake (no additional infrastructure)

**Stream-to-Table Routing**: Each tenant's Kinesis stream maps directly to their Snowflake table:
```
smdh-abc_manufacturing-stream → SMDH_TENANT_ABC_MANUFACTURING.RAW.sensor_readings
smdh-xyz_corp-stream → SMDH_TENANT_XYZ_CORP.RAW.sensor_readings
```

 .. Infrastructure Setup Scripts

Current directory structure:
```
infrastructure/snowflake/
├── sql/
│   └── core/
│       ├── 01_infrastructure_setup.sql    # Infrastructure database
│       ├── 02_shared_resources.sql        # Warehouses, roles
│       └── 03_openflow_connector.sql      # Openflow Kinesis integration
├── tenant/
│   ├── 10_create_tenant_database.sql      # Database creation
│   ├── 11_create_schemas.sql              # Schema creation
│   ├── 12_create_tables.sql               # Table definitions
│   ├── 13_create_streams.sql              # CDC streams
│   ├── 14_create_tasks.sql                # Processing tasks
│   ├── 15_create_dynamic_tables.sql       # Aggregation tables
│   ├── 16_create_roles.sql                # RBAC setup
│   └── 17_create_monitoring.sql           # Monitoring views
├── scripts/
│   ├── setup_openflow.sh                  # Automated Openflow setup
│   ├── onboard_tenant.sh                  # Tenant onboarding
│   └── validate_setup.sh                  # Validation script
└── deployment/
    ├── Core_Infrastructure_Deployment_Guide.md  # Core infrastructure setup
    └── Tenant_Onboarding_Guide.md               # Tenant onboarding guide
```

 .. Openflow Connector Setup (03_openflow_connector.sql)

This script creates all Snowflake resources needed for Kinesis integration:
- `OPENFLOW_ADMIN` role with deployment/runtime privileges
- `OPENFLOW_RUNTIME_ROLE_KINESIS` role for connector execution
- `OPENFLOW` database with image repository
- Network rules for AWS Kinesis/DynamoDB/STS access (eu-west-2)
- External Access Integration (`OPENFLOW_AWS_EAI`)
- Connector tracking table (`openflow_connectors`)
- Monitoring views for connector health

**Important**: After running the SQL script, manual UI steps are required in Snowsight:
1. Navigate to **Ingestion > Openflow** and create Deployment
2. Create Runtime with `OPENFLOW_RUNTIME_ROLE_KINESIS`
3. Add Kinesis Connector with **critical configuration**:
   - AWS Authentication: **IAM Access Keys** (NOT role assumption)
   - Consumer Type: **Shared Throughput** (NOT Enhanced Fan-Out)
   - Snowflake Auth: **SNOWFLAKE_SESSION_TOKEN**

See: `infrastructure/deployment/Tenant_Onboarding_Guide.md` for complete instructions

Key SQL Scripts:

File: `infrastructure/snowflake/_infrastructure_setup.sql`

```sql
-- SMDH Infrastructure Database Setup
-- Purpose: Create shared infrastructure and metadata

USE ROLE ACCOUNTADMIN;

-- Create infrastructure database
CREATE DATABASE IF NOT EXISTS smdh_infrastructure
  COMMENT = 'SMDH platform infrastructure and shared resources';

-- Create schemas
CREATE SCHEMA IF NOT EXISTS smdh_infrastructure.tenant_configs
  COMMENT = 'Tenant metadata and configuration';

CREATE SCHEMA IF NOT EXISTS smdh_infrastructure.monitoring
  COMMENT = 'Platform monitoring and metrics';

CREATE SCHEMA IF NOT EXISTS smdh_infrastructure.audit
  COMMENT = 'Audit logs and access tracking';

-- Create tenant registry table
CREATE TABLE IF NOT EXISTS smdh_infrastructure.tenant_configs.tenants (
  tenant_id VARCHAR() PRIMARY KEY,
  tenant_name VARCHAR() NOT NULL,
  status VARCHAR() DEFAULT 'active',
  created_date TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
  aws_region VARCHAR() NOT NULL,
  num_sites NUMBER(),
  num_sensors NUMBER(),
  kinesis_stream_name VARCHAR(),
  data_retention_days NUMBER() DEFAULT ,
  warehouse_size VARCHAR() DEFAULT 'SMALL',
  contact_email VARCHAR(),
  notes VARCHAR(),
  CONSTRAINT valid_status CHECK (status IN ('active', 'suspended', 'offboarded'))
) COMMENT = 'Master registry of all SMDH tenants';

-- Create tenant users tracking
CREATE TABLE IF NOT EXISTS smdh_infrastructure.tenant_configs.tenant_users (
  user_id VARCHAR(),
  tenant_id VARCHAR(),
  role_name VARCHAR(),
  email VARCHAR(),
  created_date TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
  last_login TIMESTAMP_NTZ,
  CONSTRAINT fk_tenant FOREIGN KEY (tenant_id)
    REFERENCES smdh_infrastructure.tenant_configs.tenants(tenant_id)
) COMMENT = 'User access tracking per tenant';

-- Create device registry
CREATE TABLE IF NOT EXISTS smdh_infrastructure.tenant_configs.devices (
  device_id VARCHAR() PRIMARY KEY,
  tenant_id VARCHAR() NOT NULL,
  site_id VARCHAR(),
  device_type VARCHAR(),
  device_name VARCHAR(),
  iot_thing_name VARCHAR(),
  certificate_arn VARCHAR(),
  certificate_expiry TIMESTAMP_NTZ,
  status VARCHAR() DEFAULT 'active',
  deployed_date TIMESTAMP_NTZ,
  last_connection TIMESTAMP_NTZ,
  CONSTRAINT fk_device_tenant FOREIGN KEY (tenant_id)
    REFERENCES smdh_infrastructure.tenant_configs.tenants(tenant_id)
) COMMENT = 'Registry of all IoT devices and gateways';

-- Create infrastructure admin role
CREATE ROLE IF NOT EXISTS smdh_infrastructure_admin
  COMMENT = 'Admin role for SMDH platform management';

-- Grant privileges
GRANT ALL ON DATABASE smdh_infrastructure TO ROLE smdh_infrastructure_admin;
GRANT ALL ON ALL SCHEMAS IN DATABASE smdh_infrastructure TO ROLE smdh_infrastructure_admin;
GRANT ALL ON ALL TABLES IN DATABASE smdh_infrastructure TO ROLE smdh_infrastructure_admin;

-- Grant role to SYSADMIN
GRANT ROLE smdh_infrastructure_admin TO ROLE SYSADMIN;
```

File: `infrastructure/snowflake/tenant/_create_tenant_database.sql`

```sql
-- SMDH Tenant Database Creation Template
-- Usage: Replace {{TENANT_ID}} with actual tenant identifier

SET tenant_id = '{{TENANT_ID}}';
SET tenant_name = '{{TENANT_NAME}}';

USE ROLE ACCOUNTADMIN;

-- Create tenant database
CREATE DATABASE IF NOT EXISTS IDENTIFIER($tenant_id)
  COMMENT = CONCAT('SMDH Tenant Database - ', $tenant_name);

-- Create schemas
CREATE SCHEMA IF NOT EXISTS IDENTIFIER(CONCAT($tenant_id, '.raw'))
  COMMENT = 'Raw ingested sensor data';

CREATE SCHEMA IF NOT EXISTS IDENTIFIER(CONCAT($tenant_id, '.normalized'))
  COMMENT = 'Cleaned and validated data';

CREATE SCHEMA IF NOT EXISTS IDENTIFIER(CONCAT($tenant_id, '.aggregated'))
  COMMENT = 'Aggregated metrics and KPIs';

CREATE SCHEMA IF NOT EXISTS IDENTIFIER(CONCAT($tenant_id, '.analytics'))
  COMMENT = 'Analytics views and ML results';

-- Register tenant in infrastructure database
INSERT INTO smdh_infrastructure.tenant_configs.tenants
  (tenant_id, tenant_name, status, aws_region)
VALUES
  ($tenant_id, $tenant_name, 'active', 'eu-west-');
```

File: `infrastructure/snowflake/tenant/_create_tables.sql`

```sql
-- SMDH Tenant Table Definitions
-- Purpose: Create all tables for tenant data storage

SET tenant_id = '{{TENANT_ID}}';

USE DATABASE IDENTIFIER($tenant_id);
USE SCHEMA raw;

-- Raw sensor readings table
CREATE TABLE IF NOT EXISTS sensor_readings (
  reading_id VARCHAR() DEFAULT UUID_STRING(),
  tenant_id VARCHAR() NOT NULL DEFAULT $tenant_id,
  sensor_id VARCHAR() NOT NULL,
  site_id VARCHAR(),
  timestamp TIMESTAMP_NTZ NOT NULL,
  payload VARIANT NOT NULL,
  ingestion_timestamp TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
  source_system VARCHAR(),
  mqtt_topic VARCHAR(),
  iot_timestamp TIMESTAMP_NTZ,
  device_id VARCHAR(),
  PRIMARY KEY (reading_id),
  CONSTRAINT valid_tenant CHECK (tenant_id = $tenant_id)
)
CLUSTER BY (DATE_TRUNC('day', timestamp), sensor_id)
COMMENT = 'Raw sensor readings from IoT devices';

-- Gateway connections log
CREATE TABLE IF NOT EXISTS gateway_connections (
  connection_id VARCHAR() DEFAULT UUID_STRING(),
  tenant_id VARCHAR() NOT NULL DEFAULT $tenant_id,
  gateway_id VARCHAR() NOT NULL,
  site_id VARCHAR(),
  connection_time TIMESTAMP_NTZ NOT NULL,
  disconnection_time TIMESTAMP_NTZ,
  status VARCHAR(),
  error_message VARCHAR(),
  ip_address VARCHAR(),
  client_id VARCHAR(),
  ingestion_timestamp TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
  PRIMARY KEY (connection_id),
  CONSTRAINT valid_tenant CHECK (tenant_id = $tenant_id)
)
COMMENT = 'Gateway connection tracking and diagnostics';

-- Device status events
CREATE TABLE IF NOT EXISTS device_status (
  event_id VARCHAR() DEFAULT UUID_STRING(),
  tenant_id VARCHAR() NOT NULL DEFAULT $tenant_id,
  device_id VARCHAR() NOT NULL,
  site_id VARCHAR(),
  timestamp TIMESTAMP_NTZ NOT NULL,
  status VARCHAR(),
  battery_level NUMBER(,),
  signal_strength NUMBER(,),
  firmware_version VARCHAR(),
  payload VARIANT,
  ingestion_timestamp TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
  PRIMARY KEY (event_id),
  CONSTRAINT valid_tenant CHECK (tenant_id = $tenant_id)
)
COMMENT = 'Device health and status tracking';

-- File uploads tracking
CREATE TABLE IF NOT EXISTS uploaded_files (
  file_id VARCHAR() PRIMARY KEY DEFAULT UUID_STRING(),
  tenant_id VARCHAR() NOT NULL DEFAULT $tenant_id,
  file_name VARCHAR(),
  file_size NUMBER(),
  upload_timestamp TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
  uploaded_by VARCHAR(),
  file_path VARCHAR(),
  stage_location VARCHAR(),
  status VARCHAR() DEFAULT 'uploaded',
  rows_processed NUMBER(),
  processing_error VARCHAR(),
  CONSTRAINT valid_tenant CHECK (tenant_id = $tenant_id)
)
COMMENT = 'Manual file upload tracking';

-- Normalized schema tables
USE SCHEMA normalized;

CREATE TABLE IF NOT EXISTS sensor_metrics (
  metric_id VARCHAR() DEFAULT UUID_STRING(),
  tenant_id VARCHAR() NOT NULL DEFAULT $tenant_id,
  sensor_id VARCHAR() NOT NULL,
  site_id VARCHAR(),
  timestamp TIMESTAMP_NTZ NOT NULL,
  metric_name VARCHAR() NOT NULL,
  metric_value FLOAT,
  metric_unit VARCHAR(),
  quality_flag VARCHAR() DEFAULT 'good',
  validation_status VARCHAR(),
  normalized_timestamp TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
  PRIMARY KEY (metric_id),
  CONSTRAINT valid_tenant CHECK (tenant_id = $tenant_id)
)
CLUSTER BY (DATE_TRUNC('day', timestamp), sensor_id, metric_name)
COMMENT = 'Normalized and validated sensor metrics';

-- Set time travel retention
ALTER TABLE raw.sensor_readings SET DATA_RETENTION_TIME_IN_DAYS = ;
ALTER TABLE normalized.sensor_metrics SET DATA_RETENTION_TIME_IN_DAYS = ;
```

---

 . Tenant Onboarding Automation

Purpose: Automate complete tenant provisioning from zero to production

**Per-Tenant Resources Created**:
- AWS: Dedicated Kinesis stream, IoT policy, IoT rule routing to tenant stream
- Snowflake: Tenant database with RAW/NORMALIZED/AGGREGATED/ANALYTICS schemas
- Openflow: Stream-to-table mapping added to Kinesis connector configuration

**Detailed Onboarding Guide**: See `infrastructure/deployment/Tenant_Onboarding_Guide.md` for complete step-by-step instructions including:
- AWS Kinesis stream creation
- IAM role configuration
- IoT rule setup
- Snowflake database provisioning
- Openflow connector configuration
- Verification and testing

 .. Onboarding Script

File: `infrastructure/scripts/onboard_tenant.sh`

```bash
!/bin/bash
 SMDH Tenant Onboarding Automation
 Usage: ./onboard_tenant.sh --tenant-id company_a --tenant-name "Company A Ltd" --num-sites 

set -euo pipefail

 Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

 Default values
AWS_REGION="${AWS_REGION:-eu-west-}"
RETENTION_DAYS="${RETENTION_DAYS:-}"
WAREHOUSE_SIZE="${WAREHOUSE_SIZE:-SMALL}"

 Color output
RED='\[;m'
GREEN='\[;m'
YELLOW='\[;m'
NC='\[m'  No Color

 Functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $"
}

 Parse command line arguments
while [[ $ -gt  ]]; do
    case $ in
        --tenant-id)
            TENANT_ID="$"
            shift 
            ;;
        --tenant-name)
            TENANT_NAME="$"
            shift 
            ;;
        --num-sites)
            NUM_SITES="$"
            shift 
            ;;
        --contact-email)
            CONTACT_EMAIL="$"
            shift 
            ;;
        )
            echo "Unknown option: $"
            exit 
            ;;
    esac
done

 Validate required parameters
if [[ -z "${TENANT_ID:-}" ]]; then
    log_error "Missing required parameter: --tenant-id"
    exit 
fi

if [[ -z "${TENANT_NAME:-}" ]]; then
    log_error "Missing required parameter: --tenant-name"
    exit 
fi

if [[ -z "${NUM_SITES:-}" ]]; then
    log_error "Missing required parameter: --num-sites"
    exit 
fi

 Validate tenant ID format
if ! [[ $TENANT_ID =~ ^[a-z-_]+$ ]]; then
    log_error "Tenant ID must be lowercase alphanumeric with underscores only"
    exit 
fi

log_info "Starting SMDH Tenant Onboarding"
log_info "  Tenant ID: $TENANT_ID"
log_info "  Tenant Name: $TENANT_NAME"
log_info "  Number of Sites: $NUM_SITES"
echo ""

 Phase : Terraform deployment
log_info "Phase : Deploying AWS infrastructure with Terraform..."
cd "$PROJECT_ROOT/terraform"

 Add tenant to 03_tenants.tfvars (edit environments/prod/03_tenants.tfvars)
# Add tenant block with: name, num_sites, retention_days, warehouse_size, contact_email, sensors_per_site

terraform init
terraform plan \
  -var-file="environments/prod/01_tags.tfvars" \
  -var-file="environments/prod/02_core.tfvars" \
  -var-file="environments/prod/03_tenants.tfvars" \
  -out=tfplan

read -p "Review plan and press ENTER to apply, or Ctrl+C to cancel..."

terraform apply tfplan

 Get outputs
IOT_ENDPOINT=$(terraform output -raw iot_endpoint)
KINESIS_STREAM=$(terraform output -raw kinesis_stream_name)

log_info " AWS infrastructure deployed"
echo ""

 Phase : Snowflake setup
log_info "Phase : Creating Snowflake database..."

 Execute Snowflake scripts
snowsql -a "$SNOWFLAKE_ACCOUNT" -u "$SNOWFLAKE_USER" \
    -f "$PROJECT_ROOT/snowflake/tenant/_create_tenant_database.sql" \
    -D tenant_id="smdh_tenant_${TENANT_ID}" \
    -D tenant_name="${TENANT_NAME}"

snowsql -a "$SNOWFLAKE_ACCOUNT" -u "$SNOWFLAKE_USER" \
    -f "$PROJECT_ROOT/snowflake/tenant/_create_schemas.sql" \
    -D tenant_id="smdh_tenant_${TENANT_ID}"

snowsql -a "$SNOWFLAKE_ACCOUNT" -u "$SNOWFLAKE_USER" \
    -f "$PROJECT_ROOT/snowflake/tenant/_create_tables.sql" \
    -D tenant_id="smdh_tenant_${TENANT_ID}"

log_info " Snowflake database created"
echo ""

 Phase : Download certificates
log_info "Phase : Downloading device certificates..."

CERT_DIR="$PROJECT_ROOT/certificates/${TENANT_ID}"
mkdir -p "$CERT_DIR"

 Get certificate ARNs from Terraform output
terraform output -json tenant_certificates | jq -r ".${TENANT_ID}[]" | while read CERT_ID; do
    aws iot describe-certificate \
        --certificate-id "$CERT_ID" \
        --region "$AWS_REGION" \
        --query 'certificateDescription.certificatePem' \
        --output text > "${CERT_DIR}/${CERT_ID}-cert.pem"

    log_info "  Downloaded certificate: ${CERT_ID}"
done

log_info " Certificates downloaded to: $CERT_DIR"
echo ""

 Phase : Configure monitoring
log_info "Phase : Setting up monitoring and alerts..."

 CloudWatch dashboard and alarms are created by Terraform
 Verify they exist
aws cloudwatch describe-alarms \
    --alarm-name-prefix "smdh-${TENANT_ID}" \
    --region "$AWS_REGION" \
    --query 'MetricAlarms[].AlarmName' \
    --output table

log_info " Monitoring configured"
echo ""

 Summary
log_info "========================================="
log_info "Tenant Onboarding Complete!"
log_info "========================================="
echo ""
echo " Deliverables:"
echo "    AWS IoT Core: Things, policies, rules created"
echo "    Kinesis Stream: smdh-${TENANT_ID}-stream (dedicated per-tenant stream)"
echo "    Snowflake Database: smdh_tenant_${TENANT_ID}"
echo "    Certificates: $CERT_DIR"
echo "    CloudWatch Dashboard: https://console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}dashboards:name=smdh-${TENANT_ID}"
echo ""
echo " Next Steps:"
echo "   . Deploy certificates to gateways"
echo "   . Configure gateway MQTT settings:"
echo "      - Server: $IOT_ENDPOINT"
echo "      - Port: "
echo "      - Topic: smdh/${TENANT_ID}/{site_id}/sensor-data"
echo "   . Create Openflow connector in Snowsight for smdh-${TENANT_ID}-stream"
echo "   . Test data flow with: infrastructure/scripts/test_data_flow.sh ${TENANT_ID}"
echo "   . Verify data in Snowflake"
echo ""
```

---

 . Monitoring and Alerting

Purpose: Proactive monitoring and automated alerting for operational issues

 .. Monitoring Scripts

File: `infrastructure/scripts/check_system_health.sh`

```bash
!/bin/bash
 SMDH System Health Check
 Usage: ./check_system_health.sh --tenant-id company_a

set -euo pipefail

TENANT_ID="$"
AWS_REGION="${AWS_REGION:-eu-west-}"

echo "========================================="
echo "SMDH System Health Check"
echo "Tenant: $TENANT_ID"
echo "Region: $AWS_REGION"
echo "========================================="
echo ""

 Check : IoT Core Connections
echo ". IoT Core Device Connections"
CONNECTED_DEVICES=$(aws iot search-index \
    --index-name "AWS_Things" \
    --query-string "thingName:smdh--${TENANT_ID}- AND connectivity.connected:true" \
    --region "$AWS_REGION" \
    --query 'things | length(@)')

echo "   Connected Devices: $CONNECTED_DEVICES"

 Check : MQTT Message Rate
echo ""
echo ". MQTT Message Ingestion (last hour)"
aws cloudwatch get-metric-statistics \
    --namespace AWS/IoT \
    --metric-name PublishIn.Success \
    --start-time "$(date -u -d ' hour ago' +%Y-%m-%dT%H:%M:%S)" \
    --end-time "$(date -u +%Y-%m-%dT%H:%M:%S)" \
    --period  \
    --statistics Sum \
    --region "$AWS_REGION" \
    --query 'Datapoints[].Sum' \
    --output text

 Check : Kinesis Stream Status (Per-Tenant Stream)
echo ""
echo ". Tenant Kinesis Stream Health"
aws kinesis describe-stream-summary \
    --stream-name "smdh-${TENANT_ID}-stream" \
    --region "$AWS_REGION" \
    --query 'StreamDescriptionSummary.{Status:StreamStatus,OpenShards:OpenShardCount}' \
    --output table

 Check : Certificate Expiry
echo ""
echo ". Certificate Expiry Check"
aws iot list-certificates \
    --region "$AWS_REGION" \
    --query "certificates[?contains(certificateArn, '${TENANT_ID}')].{ID:certificateId,Status:status,Expiry:certificateExpirationDate}" \
    --output table

 Check : CloudWatch Alarms
echo ""
echo ". Active CloudWatch Alarms"
aws cloudwatch describe-alarms \
    --alarm-name-prefix "smdh-${TENANT_ID}" \
    --state-value ALARM \
    --region "$AWS_REGION" \
    --query 'MetricAlarms[].{Name:AlarmName,State:StateValue,Reason:StateReason}' \
    --output table

echo ""
echo "Health check complete."
```

---

 . Testing and Validation

Purpose: Comprehensive testing framework to validate end-to-end data flow

 .. End-to-End Test Script

File: `infrastructure/scripts/test_data_flow.sh`

```bash
!/bin/bash
 SMDH End-to-End Data Flow Test
 Usage: ./test_data_flow.sh company_a

set -euo pipefail

TENANT_ID="$"
AWS_REGION="${AWS_REGION:-eu-west-}"

echo "========================================="
echo "SMDH End-to-End Data Flow Test"
echo "Tenant: $TENANT_ID"
echo "========================================="
echo ""

 Test : MQTT Publish Test
echo "Test : Publishing test message to IoT Core..."

TEST_PAYLOAD=$(cat <<EOF
{
  "sensor_id": "test-sensor-",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "temperature": .,
  "humidity": .,
  "test": true
}
EOF
)

 Publish using AWS IoT MQTT test client
aws iot-data publish \
    --topic "smdh/${TENANT_ID}/site-/sensor-data" \
    --payload "$TEST_PAYLOAD" \
    --region "$AWS_REGION"

echo " Test message published"
echo ""

 Test : Verify message in tenant's Kinesis stream
echo "Test : Checking tenant Kinesis stream (waiting  seconds)..."
sleep

 Each tenant has their own stream: smdh-{tenant_id}-stream
SHARD_ITERATOR=$(aws kinesis get-shard-iterator \
    --stream-name "smdh-${TENANT_ID}-stream" \
    --shard-id shardId- \
    --shard-iterator-type LATEST \
    --region "$AWS_REGION" \
    --query 'ShardIterator' \
    --output text)

RECORDS=$(aws kinesis get-records \
    --shard-iterator "$SHARD_ITERATOR" \
    --region "$AWS_REGION" \
    --query 'Records | length(@)')

if [ "$RECORDS" -gt  ]; then
    echo " Found $RECORDS records in smdh-${TENANT_ID}-stream"
else
    echo " No records found in smdh-${TENANT_ID}-stream (may need to wait longer)"
fi
echo ""

 Test : Verify data in Snowflake
echo "Test : Checking Snowflake database (waiting  seconds)..."
sleep 

snowsql -a "$SNOWFLAKE_ACCOUNT" -u "$SNOWFLAKE_USER" \
    -q "SELECT COUNT() as record_count, MAX(ingestion_timestamp) as latest
        FROM smdh_tenant_${TENANT_ID}.raw.sensor_readings
        WHERE sensor_id = 'test-sensor-';" \
    -o output_format=plain

echo ""
echo "========================================="
echo "Test complete. Check results above."
echo "========================================="
```

---

 . Implementation Checklist

 . Prerequisites Checklist

- [ ] AWS CLI configured with admin credentials
- [ ] Terraform installed (v.+)
- [ ] Snowflake account accessible via SnowSQL
- [ ] Git repository initialized
- [ ] S bucket created for Terraform state
- [ ] Snowflake account ID and external ID obtained

 . Phase : Infrastructure as Code (Week -)

- [ ] Create Terraform directory structure
- [ ] Implement AWS IoT Core module
- [ ] Implement Kinesis module
- [ ] Implement Secrets Manager module
- [ ] Implement CloudWatch module
- [ ] Implement IAM roles module
- [ ] Implement tenant module
- [ ] Create variable files for environments
- [ ] Test Terraform plan/apply in dev environment
- [ ] Document Terraform usage

 . Phase : Snowflake Setup (Week )

- [x] Create infrastructure setup SQL scripts (`01_infrastructure_setup.sql`)
- [x] Create shared resources scripts (`02_shared_resources.sql`)
- [x] Create Openflow connector configuration (`03_openflow_connector.sql`)
- [x] Create tenant database template scripts (`10_create_tenant_database.sql`)
- [x] Create table definition scripts (`12_create_tables.sql`)
- [x] Create streams and tasks scripts (`13_create_streams.sql`, `14_create_tasks.sql`)
- [x] Create RBAC scripts (`16_create_roles.sql`)
- [x] Create setup automation script (`setup_openflow.sh`)
- [x] Document Snowflake setup process (`Tenant_Onboarding_Guide.md`)
- [ ] Complete Openflow UI configuration (Deployment, Runtime, Kinesis Connector)
- [ ] Test end-to-end data flow from IoT → Kinesis → Snowflake

 . Phase : Automation (Week -)

- [ ] Create tenant onboarding script
- [ ] Create tenant offboarding script
- [ ] Create certificate rotation script
- [ ] Create health check script
- [ ] Create backup/restore scripts
- [ ] Test automation end-to-end
- [ ] Create runbook documentation

 . Phase : Monitoring (Week )

- [ ] Configure CloudWatch dashboards
- [ ] Configure CloudWatch alarms
- [ ] Configure SNS topics for alerts
- [ ] Create monitoring queries for Snowflake
- [ ] Set up log aggregation
- [ ] Test alerting workflows

 . Phase : Testing & Validation (Week )

- [ ] Create end-to-end test scripts
- [ ] Create load testing scripts
- [ ] Perform security testing
- [ ] Validate multi-tenancy isolation
- [ ] Document test results
- [ ] Create operational runbooks

---

 . Development Workflow

 . Local Development Setup

```bash
 . Clone repository
git clone <repo-url>
cd smdh

 . Install dependencies
brew install terraform awscli jq
pip install snowflake-cli-client

 . Configure AWS credentials
aws configure
 Enter: Access Key ID, Secret Access Key, Region (eu-west-)

 . Configure Snowflake
snowsql -a <account> -u <user>
 Configure connection profile

 . Initialize Terraform
cd infrastructure/terraform
terraform init

 . Create dev environment
# Edit environments/dev/ tfvars files:
#   - 01_tags.tfvars (project tags)
#   - 02_core.tfvars (AWS settings)
#   - 03_tenants.tfvars (tenant definitions)
```

 . Testing Workflow

```bash
 . Plan infrastructure changes
cd infrastructure/terraform
terraform plan \
  -var-file=environments/dev/01_tags.tfvars \
  -var-file=environments/dev/02_core.tfvars \
  -var-file=environments/dev/03_tenants.tfvars

 . Apply to dev environment
terraform apply \
  -var-file=environments/dev/01_tags.tfvars \
  -var-file=environments/dev/02_core.tfvars \
  -var-file=environments/dev/03_tenants.tfvars

 . Test Snowflake scripts
snowsql -f snowflake/_infrastructure_setup.sql

 . Run health checks
./scripts/check_system_health.sh manufacturing_demo

 . Run end-to-end tests
./scripts/test_iot_pipeline.sh manufacturing_demo SITE_001 5
```

 . Deployment Workflow

```bash
 . Create feature branch
git checkout -b feature/add-monitoring

 . Make changes and test locally
terraform plan
terraform apply

 . Commit changes
git add .
git commit -m "Add CloudWatch monitoring dashboards"

 . Push and create PR
git push origin feature/add-monitoring

 . After review, merge to main

 . Deploy to production
git checkout main
git pull
cd infrastructure/terraform
terraform plan \
  -var-file=environments/prod/01_tags.tfvars \
  -var-file=environments/prod/02_core.tfvars \
  -var-file=environments/prod/03_tenants.tfvars
terraform apply \
  -var-file=environments/prod/01_tags.tfvars \
  -var-file=environments/prod/02_core.tfvars \
  -var-file=environments/prod/03_tenants.tfvars
```

---

 . Key Deliverables Summary

 . Code Artifacts

| Artifact | Location | Purpose |
|----------|----------|---------|
| Terraform modules | `infrastructure/terraform/modules/` | AWS resource provisioning |
| Snowflake SQL scripts | `infrastructure/snowflake/` | Database setup and config |
| Automation scripts | `infrastructure/scripts/` | Operational automation |
| Test scripts | `infrastructure/scripts/` | Validation and testing |
| Documentation | `docs/` | Architecture and operations |

 . Configuration Files

| File | Purpose |
|------|---------|
| `01_tags.tfvars` | Project tags configuration |
| `02_core.tfvars` | AWS and core settings |
| `03_tenants.tfvars` | Tenant definitions |
| `.sql` | Snowflake DDL scripts |
| `.sh` | Bash automation scripts |
| `.env` | Environment variables (not committed) |

 . Documentation Deliverables

- [ ] Architecture diagrams (Draw.io/PNG exports)
- [ ] Infrastructure as Code README
- [ ] Snowflake setup guide
- [ ] Tenant onboarding runbook
- [ ] Operations playbook
- [ ] Disaster recovery procedures
- [ ] Security documentation
- [ ] Cost optimization guide

---

 . Success Criteria

 . Technical Success Criteria

- [ ] Terraform successfully provisions all AWS resources
- [ ] Snowflake databases created and accessible
- [ ] IoT devices can connect and authenticate
- [ ] MQTT messages flow to Snowflake within  seconds
- [ ] Multi-tenancy isolation validated
- [ ] Monitoring dashboards show real-time metrics
- [ ] Alerts trigger correctly for error conditions
- [ ] Certificates can be rotated without downtime

 . Operational Success Criteria

- [ ] Tenant onboarding completes in < hours
- [ ] Zero manual steps in deployment
- [ ] Health checks run automatically
- [ ] Documentation is complete and accurate
- [ ] Runbooks cover all operational scenarios
- [ ] Team trained on operations

---

 . Next Steps

**Implementation complete.** For ongoing operations:

1. To onboard new tenants: See `infrastructure/deployment/Tenant_Onboarding_Guide.md`
2. To deploy core infrastructure: See `infrastructure/deployment/Core_Infrastructure_Deployment_Guide.md`
3. To run health checks: `./scripts/check_system_health.sh <tenant_id>`
4. To test E2E pipeline: `./scripts/test_iot_pipeline.sh <tenant_id> <site_id> <count>`

For architecture details, see `SMDH_Infrastructure_Implementation.md`.
