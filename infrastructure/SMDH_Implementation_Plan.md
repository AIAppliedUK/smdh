# SMDH Implementation Plan

## Executive Summary

This document outlines what needs to be implemented to deploy the Smart Manufacturing Data Hub (SMDH) solution, based on the architecture design and implementation guide. You have:

- ✅ Admin access to Snowflake tenant
- ✅ AWS sandpit with CLI configured
- ✅ Architecture documentation complete

**Estimated Timeline:** 4-6 weeks for initial implementation with single tenant

---

## 1. Implementation Overview

### 1.1 What We're Building

```
┌─────────────────────────────────────────────────────────────┐
│                     SMDH Platform                            │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  IoT Devices → AWS IoT Core → Kinesis → Snowflake Openflow │
│       ↓              ↓           ↓              ↓            │
│  Certificates   Rules Engine   Buffer      Data Warehouse   │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 1.2 Implementation Phases

| Phase | Component | Duration | Dependencies |
|-------|-----------|----------|--------------|
| **1** | Infrastructure as Code (Terraform) | 1-2 weeks | AWS CLI configured |
| **2** | Snowflake Setup Scripts | 1 week | Snowflake admin access |
| **3** | Tenant Onboarding Automation | 1-2 weeks | Phases 1 & 2 complete |
| **4** | Monitoring & Alerting | 1 week | Phase 1 complete |
| **5** | Testing & Validation | 1 week | All phases complete |

---

## 2. What Needs to Be Built

### 2.1 Infrastructure as Code (Terraform)

**Purpose:** Automate AWS resource provisioning and ensure consistent deployments

#### 2.1.1 Core AWS Infrastructure

**Files to create:**
```
infrastructure/terraform/
├── main.tf                          # Root configuration
├── variables.tf                     # Input variables
├── outputs.tf                       # Output values
├── providers.tf                     # AWS provider config
├── modules/
│   ├── iot-core/
│   │   ├── main.tf                  # IoT Core resources
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── iot-policies.tf          # IoT policy templates
│   ├── kinesis/
│   │   ├── main.tf                  # Kinesis stream
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── secrets-manager/
│   │   ├── main.tf                  # Secrets Manager setup
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── cloudwatch/
│   │   ├── main.tf                  # Log groups, alarms
│   │   ├── dashboards.tf            # Dashboard configs
│   │   ├── alarms.tf                # Alarm rules
│   │   └── variables.tf
│   ├── iam/
│   │   ├── main.tf                  # IAM roles for Snowflake
│   │   ├── policies.tf              # IAM policies
│   │   └── outputs.tf
│   └── tenant/
│       ├── main.tf                  # Per-tenant resources
│       ├── iot-thing.tf             # Thing registry
│       ├── iot-rules.tf             # IoT Rules Engine
│       ├── certificates.tf          # Certificate generation
│       └── variables.tf
└── environments/
    ├── dev/
    │   └── terraform.tfvars         # Dev environment vars
    ├── staging/
    │   └── terraform.tfvars         # Staging vars
    └── prod/
        └── terraform.tfvars         # Production vars
```

**Required Resources:**

1. **AWS IoT Core**
   - IoT Thing Type: `LoRaWANGateway`
   - IoT Thing registry (per tenant/gateway)
   - IoT Policies with tenant isolation
   - Certificate generation and attachment
   - IoT Rules Engine rules (per tenant)

2. **Kinesis Data Streams**
   - Stream name: `smdh-sensor-data-stream`
   - Mode: On-demand
   - Retention: 24 hours
   - Encryption: AWS managed keys

3. **Secrets Manager**
   - Secret: `smdh/snowflake/private-key`
   - Rotation: Enabled (55 minutes before expiry)
   - Encryption: KMS

4. **CloudWatch**
   - Log group: `/aws/iot/smdh`
   - Retention: 90 days
   - Dashboards (per tenant)
   - Alarms for critical metrics

5. **IAM Roles**
   - `smdh-iot-kinesis-role` - IoT Rules → Kinesis
   - `smdh-snowflake-kinesis-role` - Snowflake → Kinesis read

**Example Terraform Structure:**

```hcl
# infrastructure/terraform/main.tf
terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket = "smdh-terraform-state"
    key    = "infrastructure/terraform.tfstate"
    region = "eu-west-2"
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

# Core infrastructure
module "kinesis" {
  source = "./modules/kinesis"

  stream_name = "smdh-sensor-data-stream"
  environment = var.environment
}

module "iot_core" {
  source = "./modules/iot-core"

  thing_type_name = "LoRaWANGateway"
  environment     = var.environment
}

module "cloudwatch" {
  source = "./modules/cloudwatch"

  log_retention_days = var.log_retention_days
  environment        = var.environment
}

module "iam" {
  source = "./modules/iam"

  kinesis_stream_arn = module.kinesis.stream_arn
  snowflake_account_id = var.snowflake_account_id
  snowflake_external_id = var.snowflake_external_id
}

# Per-tenant resources
module "tenants" {
  source = "./modules/tenant"

  for_each = var.tenants

  tenant_id       = each.key
  tenant_name     = each.value.name
  num_sites       = each.value.num_sites
  iot_endpoint    = module.iot_core.endpoint
  kinesis_stream  = module.kinesis.stream_name
  aws_account_id  = data.aws_caller_identity.current.account_id
  aws_region      = var.aws_region
}
```

#### 2.1.2 Terraform Variables

**File: `infrastructure/terraform/variables.tf`**

```hcl
variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "eu-west-2"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 90
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

### 2.2 Snowflake Setup Scripts

**Purpose:** Initialize Snowflake environment and tenant databases

#### 2.2.1 Infrastructure Setup Scripts

**Files to create:**
```
infrastructure/snowflake/
├── 00_prerequisites.sql             # Check Snowflake version, features
├── 01_infrastructure_setup.sql      # Create infrastructure database
├── 02_shared_resources.sql          # Warehouses, roles, users
├── 03_openflow_connector.sql        # Openflow/Kinesis integration
├── tenant/
│   ├── 10_create_tenant_database.sql    # Database creation template
│   ├── 11_create_schemas.sql            # Schema creation
│   ├── 12_create_tables.sql             # Table definitions
│   ├── 13_create_streams.sql            # CDC streams
│   ├── 14_create_tasks.sql              # Processing tasks
│   ├── 15_create_dynamic_tables.sql     # Aggregation tables
│   ├── 16_create_roles.sql              # RBAC setup
│   └── 17_create_monitoring.sql         # Monitoring views
└── scripts/
    ├── onboard_tenant.sh                # Bash wrapper script
    └── validate_tenant.sql              # Validation queries
```

**Key SQL Scripts:**

**File: `infrastructure/snowflake/01_infrastructure_setup.sql`**

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
  tenant_id VARCHAR(100) PRIMARY KEY,
  tenant_name VARCHAR(500) NOT NULL,
  status VARCHAR(50) DEFAULT 'active',
  created_date TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
  aws_region VARCHAR(50) NOT NULL,
  num_sites NUMBER(10),
  num_sensors NUMBER(10),
  kinesis_stream_name VARCHAR(255),
  data_retention_days NUMBER(10) DEFAULT 730,
  warehouse_size VARCHAR(50) DEFAULT 'SMALL',
  contact_email VARCHAR(255),
  notes VARCHAR(5000),
  CONSTRAINT valid_status CHECK (status IN ('active', 'suspended', 'offboarded'))
) COMMENT = 'Master registry of all SMDH tenants';

-- Create tenant users tracking
CREATE TABLE IF NOT EXISTS smdh_infrastructure.tenant_configs.tenant_users (
  user_id VARCHAR(255),
  tenant_id VARCHAR(100),
  role_name VARCHAR(100),
  email VARCHAR(255),
  created_date TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
  last_login TIMESTAMP_NTZ,
  CONSTRAINT fk_tenant FOREIGN KEY (tenant_id)
    REFERENCES smdh_infrastructure.tenant_configs.tenants(tenant_id)
) COMMENT = 'User access tracking per tenant';

-- Create device registry
CREATE TABLE IF NOT EXISTS smdh_infrastructure.tenant_configs.devices (
  device_id VARCHAR(255) PRIMARY KEY,
  tenant_id VARCHAR(100) NOT NULL,
  site_id VARCHAR(100),
  device_type VARCHAR(100),
  device_name VARCHAR(500),
  iot_thing_name VARCHAR(255),
  certificate_arn VARCHAR(500),
  certificate_expiry TIMESTAMP_NTZ,
  status VARCHAR(50) DEFAULT 'active',
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

**File: `infrastructure/snowflake/tenant/10_create_tenant_database.sql`**

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
  ($tenant_id, $tenant_name, 'active', 'eu-west-2');
```

**File: `infrastructure/snowflake/tenant/12_create_tables.sql`**

```sql
-- SMDH Tenant Table Definitions
-- Purpose: Create all tables for tenant data storage

SET tenant_id = '{{TENANT_ID}}';

USE DATABASE IDENTIFIER($tenant_id);
USE SCHEMA raw;

-- Raw sensor readings table
CREATE TABLE IF NOT EXISTS sensor_readings (
  reading_id VARCHAR(255) DEFAULT UUID_STRING(),
  tenant_id VARCHAR(100) NOT NULL DEFAULT $tenant_id,
  sensor_id VARCHAR(255) NOT NULL,
  site_id VARCHAR(100),
  timestamp TIMESTAMP_NTZ NOT NULL,
  payload VARIANT NOT NULL,
  ingestion_timestamp TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
  source_system VARCHAR(100),
  mqtt_topic VARCHAR(500),
  iot_timestamp TIMESTAMP_NTZ,
  device_id VARCHAR(255),
  PRIMARY KEY (reading_id),
  CONSTRAINT valid_tenant CHECK (tenant_id = $tenant_id)
)
CLUSTER BY (DATE_TRUNC('day', timestamp), sensor_id)
COMMENT = 'Raw sensor readings from IoT devices';

-- Gateway connections log
CREATE TABLE IF NOT EXISTS gateway_connections (
  connection_id VARCHAR(255) DEFAULT UUID_STRING(),
  tenant_id VARCHAR(100) NOT NULL DEFAULT $tenant_id,
  gateway_id VARCHAR(255) NOT NULL,
  site_id VARCHAR(100),
  connection_time TIMESTAMP_NTZ NOT NULL,
  disconnection_time TIMESTAMP_NTZ,
  status VARCHAR(50),
  error_message VARCHAR(1000),
  ip_address VARCHAR(50),
  client_id VARCHAR(255),
  ingestion_timestamp TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
  PRIMARY KEY (connection_id),
  CONSTRAINT valid_tenant CHECK (tenant_id = $tenant_id)
)
COMMENT = 'Gateway connection tracking and diagnostics';

-- Device status events
CREATE TABLE IF NOT EXISTS device_status (
  event_id VARCHAR(255) DEFAULT UUID_STRING(),
  tenant_id VARCHAR(100) NOT NULL DEFAULT $tenant_id,
  device_id VARCHAR(255) NOT NULL,
  site_id VARCHAR(100),
  timestamp TIMESTAMP_NTZ NOT NULL,
  status VARCHAR(50),
  battery_level NUMBER(5,2),
  signal_strength NUMBER(5,2),
  firmware_version VARCHAR(50),
  payload VARIANT,
  ingestion_timestamp TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
  PRIMARY KEY (event_id),
  CONSTRAINT valid_tenant CHECK (tenant_id = $tenant_id)
)
COMMENT = 'Device health and status tracking';

-- File uploads tracking
CREATE TABLE IF NOT EXISTS uploaded_files (
  file_id VARCHAR(255) PRIMARY KEY DEFAULT UUID_STRING(),
  tenant_id VARCHAR(100) NOT NULL DEFAULT $tenant_id,
  file_name VARCHAR(500),
  file_size NUMBER(20),
  upload_timestamp TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
  uploaded_by VARCHAR(255),
  file_path VARCHAR(1000),
  stage_location VARCHAR(1000),
  status VARCHAR(50) DEFAULT 'uploaded',
  rows_processed NUMBER(20),
  processing_error VARCHAR(5000),
  CONSTRAINT valid_tenant CHECK (tenant_id = $tenant_id)
)
COMMENT = 'Manual file upload tracking';

-- Normalized schema tables
USE SCHEMA normalized;

CREATE TABLE IF NOT EXISTS sensor_metrics (
  metric_id VARCHAR(255) DEFAULT UUID_STRING(),
  tenant_id VARCHAR(100) NOT NULL DEFAULT $tenant_id,
  sensor_id VARCHAR(255) NOT NULL,
  site_id VARCHAR(100),
  timestamp TIMESTAMP_NTZ NOT NULL,
  metric_name VARCHAR(255) NOT NULL,
  metric_value FLOAT,
  metric_unit VARCHAR(50),
  quality_flag VARCHAR(50) DEFAULT 'good',
  validation_status VARCHAR(50),
  normalized_timestamp TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
  PRIMARY KEY (metric_id),
  CONSTRAINT valid_tenant CHECK (tenant_id = $tenant_id)
)
CLUSTER BY (DATE_TRUNC('day', timestamp), sensor_id, metric_name)
COMMENT = 'Normalized and validated sensor metrics';

-- Set time travel retention
ALTER TABLE raw.sensor_readings SET DATA_RETENTION_TIME_IN_DAYS = 7;
ALTER TABLE normalized.sensor_metrics SET DATA_RETENTION_TIME_IN_DAYS = 7;
```

---

### 2.3 Tenant Onboarding Automation

**Purpose:** Automate complete tenant provisioning from zero to production

#### 2.3.1 Onboarding Script

**File: `infrastructure/scripts/onboard_tenant.sh`**

```bash
#!/bin/bash
# SMDH Tenant Onboarding Automation
# Usage: ./onboard_tenant.sh --tenant-id company_a --tenant-name "Company A Ltd" --num-sites 5

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Default values
AWS_REGION="${AWS_REGION:-eu-west-2}"
RETENTION_DAYS="${RETENTION_DAYS:-730}"
WAREHOUSE_SIZE="${WAREHOUSE_SIZE:-SMALL}"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --tenant-id)
            TENANT_ID="$2"
            shift 2
            ;;
        --tenant-name)
            TENANT_NAME="$2"
            shift 2
            ;;
        --num-sites)
            NUM_SITES="$2"
            shift 2
            ;;
        --contact-email)
            CONTACT_EMAIL="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Validate required parameters
if [[ -z "${TENANT_ID:-}" ]]; then
    log_error "Missing required parameter: --tenant-id"
    exit 1
fi

if [[ -z "${TENANT_NAME:-}" ]]; then
    log_error "Missing required parameter: --tenant-name"
    exit 1
fi

if [[ -z "${NUM_SITES:-}" ]]; then
    log_error "Missing required parameter: --num-sites"
    exit 1
fi

# Validate tenant ID format
if ! [[ $TENANT_ID =~ ^[a-z0-9_]+$ ]]; then
    log_error "Tenant ID must be lowercase alphanumeric with underscores only"
    exit 1
fi

log_info "Starting SMDH Tenant Onboarding"
log_info "  Tenant ID: $TENANT_ID"
log_info "  Tenant Name: $TENANT_NAME"
log_info "  Number of Sites: $NUM_SITES"
echo ""

# Phase 1: Terraform deployment
log_info "Phase 1: Deploying AWS infrastructure with Terraform..."
cd "$PROJECT_ROOT/terraform"

# Create tenant variable file
cat > "environments/prod/tenant_${TENANT_ID}.auto.tfvars" <<EOF
tenants = {
  ${TENANT_ID} = {
    name           = "${TENANT_NAME}"
    num_sites      = ${NUM_SITES}
    retention_days = ${RETENTION_DAYS}
  }
}
EOF

terraform init
terraform plan -var-file="environments/prod/terraform.tfvars" \
               -var-file="environments/prod/tenant_${TENANT_ID}.auto.tfvars" \
               -out=tfplan

read -p "Review plan and press ENTER to apply, or Ctrl+C to cancel..."

terraform apply tfplan

# Get outputs
IOT_ENDPOINT=$(terraform output -raw iot_endpoint)
KINESIS_STREAM=$(terraform output -raw kinesis_stream_name)

log_info "✓ AWS infrastructure deployed"
echo ""

# Phase 2: Snowflake setup
log_info "Phase 2: Creating Snowflake database..."

# Execute Snowflake scripts
snowsql -a "$SNOWFLAKE_ACCOUNT" -u "$SNOWFLAKE_USER" \
    -f "$PROJECT_ROOT/snowflake/tenant/10_create_tenant_database.sql" \
    -D tenant_id="smdh_tenant_${TENANT_ID}" \
    -D tenant_name="${TENANT_NAME}"

snowsql -a "$SNOWFLAKE_ACCOUNT" -u "$SNOWFLAKE_USER" \
    -f "$PROJECT_ROOT/snowflake/tenant/11_create_schemas.sql" \
    -D tenant_id="smdh_tenant_${TENANT_ID}"

snowsql -a "$SNOWFLAKE_ACCOUNT" -u "$SNOWFLAKE_USER" \
    -f "$PROJECT_ROOT/snowflake/tenant/12_create_tables.sql" \
    -D tenant_id="smdh_tenant_${TENANT_ID}"

log_info "✓ Snowflake database created"
echo ""

# Phase 3: Download certificates
log_info "Phase 3: Downloading device certificates..."

CERT_DIR="$PROJECT_ROOT/certificates/${TENANT_ID}"
mkdir -p "$CERT_DIR"

# Get certificate ARNs from Terraform output
terraform output -json tenant_certificates | jq -r ".${TENANT_ID}[]" | while read CERT_ID; do
    aws iot describe-certificate \
        --certificate-id "$CERT_ID" \
        --region "$AWS_REGION" \
        --query 'certificateDescription.certificatePem' \
        --output text > "${CERT_DIR}/${CERT_ID}-cert.pem"

    log_info "  Downloaded certificate: ${CERT_ID}"
done

log_info "✓ Certificates downloaded to: $CERT_DIR"
echo ""

# Phase 4: Configure monitoring
log_info "Phase 4: Setting up monitoring and alerts..."

# CloudWatch dashboard and alarms are created by Terraform
# Verify they exist
aws cloudwatch describe-alarms \
    --alarm-name-prefix "smdh-${TENANT_ID}" \
    --region "$AWS_REGION" \
    --query 'MetricAlarms[*].AlarmName' \
    --output table

log_info "✓ Monitoring configured"
echo ""

# Summary
log_info "========================================="
log_info "Tenant Onboarding Complete!"
log_info "========================================="
echo ""
echo "📦 Deliverables:"
echo "   ✓ AWS IoT Core: Things, policies, rules created"
echo "   ✓ Kinesis Stream: $KINESIS_STREAM (partition key: $TENANT_ID)"
echo "   ✓ Snowflake Database: smdh_tenant_${TENANT_ID}"
echo "   ✓ Certificates: $CERT_DIR"
echo "   ✓ CloudWatch Dashboard: https://console.aws.amazon.com/cloudwatch/home?region=${AWS_REGION}#dashboards:name=smdh-${TENANT_ID}"
echo ""
echo "📝 Next Steps:"
echo "   1. Deploy certificates to gateways"
echo "   2. Configure gateway MQTT settings:"
echo "      - Server: $IOT_ENDPOINT"
echo "      - Port: 8883"
echo "      - Topic: smdh/${TENANT_ID}/{site_id}/sensor-data"
echo "   3. Test data flow with: infrastructure/scripts/test_data_flow.sh ${TENANT_ID}"
echo "   4. Verify data in Snowflake"
echo ""
```

---

### 2.4 Monitoring and Alerting

**Purpose:** Proactive monitoring and automated alerting for operational issues

#### 2.4.1 Monitoring Scripts

**File: `infrastructure/scripts/check_system_health.sh`**

```bash
#!/bin/bash
# SMDH System Health Check
# Usage: ./check_system_health.sh --tenant-id company_a

set -euo pipefail

TENANT_ID="$1"
AWS_REGION="${AWS_REGION:-eu-west-2}"

echo "========================================="
echo "SMDH System Health Check"
echo "Tenant: $TENANT_ID"
echo "Region: $AWS_REGION"
echo "========================================="
echo ""

# Check 1: IoT Core Connections
echo "1. IoT Core Device Connections"
CONNECTED_DEVICES=$(aws iot search-index \
    --index-name "AWS_Things" \
    --query-string "thingName:smdh-*-${TENANT_ID}-* AND connectivity.connected:true" \
    --region "$AWS_REGION" \
    --query 'things | length(@)')

echo "   Connected Devices: $CONNECTED_DEVICES"

# Check 2: MQTT Message Rate
echo ""
echo "2. MQTT Message Ingestion (last hour)"
aws cloudwatch get-metric-statistics \
    --namespace AWS/IoT \
    --metric-name PublishIn.Success \
    --start-time "$(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S)" \
    --end-time "$(date -u +%Y-%m-%dT%H:%M:%S)" \
    --period 3600 \
    --statistics Sum \
    --region "$AWS_REGION" \
    --query 'Datapoints[0].Sum' \
    --output text

# Check 3: Kinesis Stream Status
echo ""
echo "3. Kinesis Stream Health"
aws kinesis describe-stream \
    --stream-name smdh-sensor-data-stream \
    --region "$AWS_REGION" \
    --query 'StreamDescription.StreamStatus' \
    --output text

# Check 4: Certificate Expiry
echo ""
echo "4. Certificate Expiry Check"
aws iot list-certificates \
    --region "$AWS_REGION" \
    --query "certificates[?contains(certificateArn, '${TENANT_ID}')].{ID:certificateId,Status:status,Expiry:certificateExpirationDate}" \
    --output table

# Check 5: CloudWatch Alarms
echo ""
echo "5. Active CloudWatch Alarms"
aws cloudwatch describe-alarms \
    --alarm-name-prefix "smdh-${TENANT_ID}" \
    --state-value ALARM \
    --region "$AWS_REGION" \
    --query 'MetricAlarms[*].{Name:AlarmName,State:StateValue,Reason:StateReason}' \
    --output table

echo ""
echo "Health check complete."
```

---

### 2.5 Testing and Validation

**Purpose:** Comprehensive testing framework to validate end-to-end data flow

#### 2.5.1 End-to-End Test Script

**File: `infrastructure/scripts/test_data_flow.sh`**

```bash
#!/bin/bash
# SMDH End-to-End Data Flow Test
# Usage: ./test_data_flow.sh company_a

set -euo pipefail

TENANT_ID="$1"
AWS_REGION="${AWS_REGION:-eu-west-2}"

echo "========================================="
echo "SMDH End-to-End Data Flow Test"
echo "Tenant: $TENANT_ID"
echo "========================================="
echo ""

# Test 1: MQTT Publish Test
echo "Test 1: Publishing test message to IoT Core..."

TEST_PAYLOAD=$(cat <<EOF
{
  "sensor_id": "test-sensor-001",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "temperature": 22.5,
  "humidity": 45.2,
  "test": true
}
EOF
)

# Publish using AWS IoT MQTT test client
aws iot-data publish \
    --topic "smdh/${TENANT_ID}/site-001/sensor-data" \
    --payload "$TEST_PAYLOAD" \
    --region "$AWS_REGION"

echo "✓ Test message published"
echo ""

# Test 2: Verify message in Kinesis
echo "Test 2: Checking Kinesis stream (waiting 10 seconds)..."
sleep 10

SHARD_ITERATOR=$(aws kinesis get-shard-iterator \
    --stream-name smdh-sensor-data-stream \
    --shard-id shardId-000000000000 \
    --shard-iterator-type LATEST \
    --region "$AWS_REGION" \
    --query 'ShardIterator' \
    --output text)

RECORDS=$(aws kinesis get-records \
    --shard-iterator "$SHARD_ITERATOR" \
    --region "$AWS_REGION" \
    --query 'Records | length(@)')

if [ "$RECORDS" -gt 0 ]; then
    echo "✓ Found $RECORDS records in Kinesis"
else
    echo "⚠ No records found in Kinesis (may need to wait longer)"
fi
echo ""

# Test 3: Verify data in Snowflake
echo "Test 3: Checking Snowflake database (waiting 30 seconds)..."
sleep 30

snowsql -a "$SNOWFLAKE_ACCOUNT" -u "$SNOWFLAKE_USER" \
    -q "SELECT COUNT(*) as record_count, MAX(ingestion_timestamp) as latest
        FROM smdh_tenant_${TENANT_ID}.raw.sensor_readings
        WHERE sensor_id = 'test-sensor-001';" \
    -o output_format=plain

echo ""
echo "========================================="
echo "Test complete. Check results above."
echo "========================================="
```

---

## 3. Implementation Checklist

### 3.1 Prerequisites Checklist

- [ ] AWS CLI configured with admin credentials
- [ ] Terraform installed (v1.0+)
- [ ] Snowflake account accessible via SnowSQL
- [ ] Git repository initialized
- [ ] S3 bucket created for Terraform state
- [ ] Snowflake account ID and external ID obtained

### 3.2 Phase 1: Infrastructure as Code (Week 1-2)

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

### 3.3 Phase 2: Snowflake Setup (Week 3)

- [ ] Create infrastructure setup SQL scripts
- [ ] Create tenant database template scripts
- [ ] Create table definition scripts
- [ ] Create streams and tasks scripts
- [ ] Create RBAC scripts
- [ ] Test scripts in Snowflake dev account
- [ ] Create Openflow connector configuration
- [ ] Document Snowflake setup process

### 3.4 Phase 3: Automation (Week 4-5)

- [ ] Create tenant onboarding script
- [ ] Create tenant offboarding script
- [ ] Create certificate rotation script
- [ ] Create health check script
- [ ] Create backup/restore scripts
- [ ] Test automation end-to-end
- [ ] Create runbook documentation

### 3.5 Phase 4: Monitoring (Week 5)

- [ ] Configure CloudWatch dashboards
- [ ] Configure CloudWatch alarms
- [ ] Configure SNS topics for alerts
- [ ] Create monitoring queries for Snowflake
- [ ] Set up log aggregation
- [ ] Test alerting workflows

### 3.6 Phase 5: Testing & Validation (Week 6)

- [ ] Create end-to-end test scripts
- [ ] Create load testing scripts
- [ ] Perform security testing
- [ ] Validate multi-tenancy isolation
- [ ] Document test results
- [ ] Create operational runbooks

---

## 4. Development Workflow

### 4.1 Local Development Setup

```bash
# 1. Clone repository
git clone <repo-url>
cd smdh

# 2. Install dependencies
brew install terraform awscli jq
pip install snowflake-cli-client

# 3. Configure AWS credentials
aws configure
# Enter: Access Key ID, Secret Access Key, Region (eu-west-2)

# 4. Configure Snowflake
snowsql -a <account> -u <user>
# Configure connection profile

# 5. Initialize Terraform
cd infrastructure/terraform
terraform init

# 6. Create dev environment
cp environments/dev/terraform.tfvars.example environments/dev/terraform.tfvars
# Edit with your values
```

### 4.2 Testing Workflow

```bash
# 1. Plan infrastructure changes
cd infrastructure/terraform
terraform plan -var-file=environments/dev/terraform.tfvars

# 2. Apply to dev environment
terraform apply -var-file=environments/dev/terraform.tfvars

# 3. Test Snowflake scripts
snowsql -f snowflake/01_infrastructure_setup.sql

# 4. Run health checks
./scripts/check_system_health.sh test_tenant

# 5. Run end-to-end tests
./scripts/test_data_flow.sh test_tenant
```

### 4.3 Deployment Workflow

```bash
# 1. Create feature branch
git checkout -b feature/add-monitoring

# 2. Make changes and test locally
terraform plan
terraform apply

# 3. Commit changes
git add .
git commit -m "Add CloudWatch monitoring dashboards"

# 4. Push and create PR
git push origin feature/add-monitoring

# 5. After review, merge to main

# 6. Deploy to production
git checkout main
git pull
cd infrastructure/terraform
terraform plan -var-file=environments/prod/terraform.tfvars
terraform apply -var-file=environments/prod/terraform.tfvars
```

---

## 5. Key Deliverables Summary

### 5.1 Code Artifacts

| Artifact | Location | Purpose |
|----------|----------|---------|
| Terraform modules | `infrastructure/terraform/modules/` | AWS resource provisioning |
| Snowflake SQL scripts | `infrastructure/snowflake/` | Database setup and config |
| Automation scripts | `infrastructure/scripts/` | Operational automation |
| Test scripts | `infrastructure/scripts/` | Validation and testing |
| Documentation | `docs/` | Architecture and operations |

### 5.2 Configuration Files

| File | Purpose |
|------|---------|
| `terraform.tfvars` | Terraform variable values |
| `tenant_*.auto.tfvars` | Per-tenant configuration |
| `*.sql` | Snowflake DDL scripts |
| `*.sh` | Bash automation scripts |
| `.env` | Environment variables |

### 5.3 Documentation Deliverables

- [ ] Architecture diagrams (Draw.io/PNG exports)
- [ ] Infrastructure as Code README
- [ ] Snowflake setup guide
- [ ] Tenant onboarding runbook
- [ ] Operations playbook
- [ ] Disaster recovery procedures
- [ ] Security documentation
- [ ] Cost optimization guide

---

## 6. Success Criteria

### 6.1 Technical Success Criteria

- [ ] Terraform successfully provisions all AWS resources
- [ ] Snowflake databases created and accessible
- [ ] IoT devices can connect and authenticate
- [ ] MQTT messages flow to Snowflake within 30 seconds
- [ ] Multi-tenancy isolation validated
- [ ] Monitoring dashboards show real-time metrics
- [ ] Alerts trigger correctly for error conditions
- [ ] Certificates can be rotated without downtime

### 6.2 Operational Success Criteria

- [ ] Tenant onboarding completes in <4 hours
- [ ] Zero manual steps in deployment
- [ ] Health checks run automatically
- [ ] Documentation is complete and accurate
- [ ] Runbooks cover all operational scenarios
- [ ] Team trained on operations

---

## 7. Next Steps

1. **Review this plan** with your team and stakeholders
2. **Set up development environment** following Section 4.1
3. **Start with Phase 1** (Infrastructure as Code) from Section 3.2
4. **Create a GitHub project board** to track progress
5. **Schedule weekly reviews** to assess progress

**Recommended Start:** Begin with creating the Terraform module for AWS IoT Core, as it's the foundation of the architecture.

Would you like me to start implementing any specific component?
