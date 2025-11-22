# Smart Manufacturing Data Hub (SMDH) - Infrastructure Implementation Guide

## Overview

This document provides detailed step-by-step implementation instructions for deploying and configuring the SMDH platform. It complements the [SMDH AWS Design Document](../docs/detailed-design/SMDH%20AWS%20design.md) which explains the architectural concepts.

**🚀 Quick Start**: For immediate deployment, use the Terraform infrastructure in [terraform/](terraform/). See [Terraform Deployment](#terraform-deployment-recommended) below.

For high-level architecture and design decisions, refer to the AWS Design Document. This guide focuses on:

- **Terraform-based Infrastructure as Code deployment** (Recommended)
- Detailed configuration procedures
- SQL table definitions and schemas
- AWS CLI scripts (for reference and manual operations)
- Snowflake setup and scripts
- Gateway device configuration
- Monitoring and alerting setup
- Tenant onboarding automation
- Validation and testing procedures
- Rollback and disaster recovery

---

## Table of Contents

1. [Terraform Deployment (Recommended)](#terraform-deployment-recommended)
2. [Pre-requisites](#1-pre-requisites)
3. [AWS Account Setup](#2-aws-account-setup)
4. [Snowflake Configuration](#3-snowflake-configuration)
5. [Tenant Onboarding Procedures](#4-tenant-onboarding-procedures)
6. [Table Definitions](#5-table-definitions)
7. [Gateway Device Setup](#6-gateway-device-setup)
8. [Monitoring and Alerting](#7-monitoring-and-alerting)
9. [Automation Scripts](#8-automation-scripts)
10. [Validation and Testing](#9-validation-and-testing)
11. [Rollback Procedures](#10-rollback-procedures)
12. [Cost Estimates](#11-cost-estimates)

---

## Terraform Deployment (Recommended)

### Overview

The SMDH platform is deployed using Terraform Infrastructure as Code. This approach provides:

- **Reproducible deployments** across environments
- **Version-controlled infrastructure** with git history
- **Automated resource provisioning** (48 resources in ~5 minutes)
- **Comprehensive tagging** for cost allocation and compliance
- **State management** with S3 backend and DynamoDB locking

### Deployment Summary

**Successfully Deployed**: 21 November 2025 14:04 UTC
**Environment**: Development (eu-west-2)
**Resources Created**: 48 AWS resources
**Tenant**: test_tenant (2 sites, 2 gateways)

### Quick Start

```bash
# Navigate to Terraform directory
cd infrastructure/terraform

# Review the comprehensive README
cat README.md

# Copy and configure your environment
cp environments/dev/terraform.tfvars.example environments/dev/terraform.tfvars
# Edit terraform.tfvars with your values

# Initialize Terraform (one-time setup)
terraform init

# Review the deployment plan
terraform plan -var-file="environments/dev/terraform.tfvars"

# Deploy infrastructure
terraform apply -var-file="environments/dev/terraform.tfvars"
```

### What Gets Deployed

The Terraform configuration automatically creates:

#### **Core Infrastructure**
- **IoT Core**: Thing Types (LoRaWAN, DevTank), logging, IAM roles
- **Kinesis**: On-demand data stream for sensor data
- **IAM**: Cross-account roles for Snowflake integration
- **Secrets Manager**: Secure credential storage for Snowflake
- **CloudWatch**: Log groups, dashboards, alarms, SNS topics

#### **Per-Tenant Resources**
- **IoT Things**: Gateways and sensors with proper attributes
- **X.509 Certificates**: Automatically generated with private keys
- **IoT Policies**: Tenant-isolated topic access control
- **IoT Rules**: Route sensor data to Kinesis with tenant partition keys
- **SNS Topics**: Tenant-specific alerting
- **CloudWatch Alarms**: Connection failures, message failures

### Deployed Configuration

#### IoT Endpoint
```
IoT Endpoint: a28fbiixmeupm0-ats.iot.eu-west-2.amazonaws.com
MQTT Address: mqtt://a28fbiixmeupm0-ats.iot.eu-west-2.amazonaws.com:8883
```

#### Kinesis Stream
```
Stream Name: smdh-sensor-data-stream
Stream ARN: arn:aws:kinesis:eu-west-2:471112943820:stream/smdh-sensor-data-stream
Mode: ON_DEMAND (auto-scaling)
```

#### Monitoring
```
Dashboard: https://console.aws.amazon.com/cloudwatch/home?region=eu-west-2#dashboards:name=smdh-platform-dev
Log Group: /aws/iot/smdh (30-day retention)
SNS Topic: smdh-platform-alarms-dev
```

#### Test Tenant Configuration
```
Tenant ID: test_tenant
Sites: 2 (site_001, site_002)
Gateways: 2 (one per site)
IoT Policy: smdh-policy-test_tenant
IoT Rule: smdh_route_test_tenant
Certificates: 2 X.509 certificates with private keys
```

### Terraform Outputs

View all deployment outputs:

```bash
# All outputs
terraform output

# Specific outputs
terraform output iot_endpoint
terraform output kinesis_stream_name
terraform output cloudwatch_dashboard_url

# Sensitive outputs (certificates, IAM roles)
terraform output -json tenant_certificate_arns
terraform output snowflake_iam_role_arn
```

### Post-Deployment Steps

After Terraform deployment completes:

1. **Confirm SNS Subscriptions**
   - Check email for subscription confirmations
   - Confirm both platform and tenant alert topics

2. **Download Device Certificates**
   ```bash
   terraform output -json tenant_configurations | jq .
   ```
   - Note: Private keys are in Terraform state, extract carefully

3. **Configure Snowflake Integration**
   - Update `snowflake_account_id` in terraform.tfvars
   - Update `snowflake_external_id` (generate UUID)
   - Re-run `terraform apply` to update IAM role trust policy

4. **Test MQTT Connectivity**
   - Use certificates to test gateway connections
   - See [Gateway Device Setup](#6-gateway-device-setup) below

### Known Issues

#### AWS Provider Default Tags Bug
During deployment, you may see errors about "Provider produced inconsistent final plan" related to tags on IoT Policy resources. This is a known AWS provider issue and **does not affect functionality**. All resources are created successfully.

**Workaround**: After the initial error, run `terraform refresh` and `terraform apply` again. The state will sync correctly.

#### IoT Thing Type Searchable Attributes
AWS IoT supports a maximum of 3 searchable attributes per Thing Type. The current configuration uses:
- `tenant_id`
- `site_id`
- `device_type`

#### IoT Rule SQL Syntax
IoT Rules SQL does not support checking built-in functions in WHERE clauses. For example:
- **Invalid**: `WHERE timestamp() IS NOT NULL`
- **Valid**: `SELECT *, timestamp() as iot_timestamp FROM 'topic'`

The `timestamp()` function generates a timestamp at message processing time and doesn't need validation. Remove WHERE clause checks on function results.

### Terraform Module Structure

```
terraform/
├── main.tf                    # Root module orchestration
├── providers.tf              # AWS provider with default tags
├── variables.tf              # Input variables
├── outputs.tf               # Output values
├── tags.tf                  # Centralized tagging strategy
├── modules/
│   ├── iot-core/           # IoT Thing Types, logging
│   ├── kinesis/            # Kinesis stream, alarms
│   ├── iam/                # Snowflake cross-account roles
│   ├── secrets-manager/    # Credential storage
│   ├── cloudwatch/         # Monitoring, dashboards, alarms
│   └── tenant/             # Per-tenant resources
└── environments/
    ├── dev/               # Development environment
    └── prod/              # Production environment
```

For comprehensive documentation, see [terraform/README.md](terraform/README.md) and [terraform/TAGGING_STRATEGY.md](terraform/TAGGING_STRATEGY.md).

### Next Steps

- **Manual Operations**: Continue to [AWS Account Setup](#2-aws-account-setup) for manual CLI commands (reference only)
- **Snowflake Setup**: Proceed to [Snowflake Configuration](#3-snowflake-configuration)
- **Device Setup**: Configure gateways with generated certificates in [Gateway Device Setup](#6-gateway-device-setup)
- **Testing**: Validate deployment with [Validation and Testing](#9-validation-and-testing)

---

## 1. Pre-requisites

### Required Permissions

**AWS:**
- IoT Core administrator
- Kinesis administrator
- Secrets Manager administrator
- CloudWatch administrator
- IAM administrator

**Snowflake:**
- Account admin role
- Ability to create databases and roles

### Required Tools

```bash
# AWS CLI (v2.x minimum)
aws --version

# Snowflake CLI
snowsql --version

# jq (JSON processor)
jq --version

# openssl (certificate generation)
openssl version
```

### Environment Setup

```bash
# Set these environment variables
export AWS_REGION="eu-west-2"
export AWS_ACCOUNT_ID="YOUR_ACCOUNT_ID"
export SNOWFLAKE_ACCOUNT="YOUR_ACCOUNT"
export SNOWFLAKE_USER="admin_user"
```

---

## 2. AWS Account Setup

> **Note**: This section documents manual AWS CLI commands for reference. For production deployments, use the [Terraform infrastructure](#terraform-deployment-recommended) which automates all these steps.

The manual commands below are useful for:
- Understanding the underlying AWS resources
- Troubleshooting and debugging
- One-off operations outside Terraform management
- Learning the SMDH architecture

### 2.1 Enable AWS IoT Core

```bash
# Verify IoT Core is available in region
aws iot describe-endpoint \
  --endpoint-type iot:Data-ATS \
  --region $AWS_REGION

# Save endpoint for later
IOT_ENDPOINT=$(aws iot describe-endpoint \
  --endpoint-type iot:Data-ATS \
  --region $AWS_REGION \
  --query 'endpointAddress' \
  --output text)

echo "IoT Endpoint: $IOT_ENDPOINT"
```

### 2.2 Create Kinesis Stream

```bash
# Create on-demand Kinesis stream for sensor data
aws kinesis create-stream \
  --stream-name smdh-sensor-data-stream \
  --stream-mode-details StreamMode=ON_DEMAND \
  --region $AWS_REGION

# Wait for stream to be active
aws kinesis wait stream-exists \
  --stream-name smdh-sensor-data-stream \
  --region $AWS_REGION

echo "✓ Kinesis stream created successfully"
```

### 2.3 Create Secrets Manager Secret for Snowflake

```bash
# Create secret for Snowflake private key (placeholder)
# This will be populated during tenant onboarding

aws secretsmanager create-secret \
  --name smdh/snowflake/private-key \
  --description "Snowflake private key for Openflow connector" \
  --secret-string '{"private_key": "placeholder"}' \
  --region $AWS_REGION

echo "✓ Secrets Manager secret created"
```

### 2.4 Create CloudWatch Log Group

```bash
# Create log group for IoT logs
aws logs create-log-group \
  --log-group-name /aws/iot/smdh \
  --region $AWS_REGION

# Set retention policy (90 days)
aws logs put-retention-policy \
  --log-group-name /aws/iot/smdh \
  --retention-in-days 90 \
  --region $AWS_REGION

echo "✓ CloudWatch log group created"
```

### 2.5 Create IAM Role for Snowflake Integration

```bash
# Create trust policy for Snowflake
cat > /tmp/snowflake-trust-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::SNOWFLAKE_ACCOUNT_ID:root"
      },
      "Action": "sts:AssumeRole",
      "Condition": {
        "StringEquals": {
          "sts:ExternalId": "SNOWFLAKE_EXTERNAL_ID"
        }
      }
    }
  ]
}
EOF

# Create role
aws iam create-role \
  --role-name smdh-snowflake-kinesis-role \
  --assume-role-policy-document file:///tmp/snowflake-trust-policy.json \
  --region $AWS_REGION

# Create policy for Kinesis access
cat > /tmp/snowflake-kinesis-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "kinesis:GetRecords",
        "kinesis:GetShardIterator",
        "kinesis:DescribeStream",
        "kinesis:ListStreams"
      ],
      "Resource": "arn:aws:kinesis:eu-west-2:*:stream/smdh-*"
    }
  ]
}
EOF

# Attach policy to role
aws iam put-role-policy \
  --role-name smdh-snowflake-kinesis-role \
  --policy-name smdh-snowflake-kinesis-policy \
  --policy-document file:///tmp/snowflake-kinesis-policy.json

echo "✓ IAM role for Snowflake created"
```

---

## 3. Snowflake Configuration

> **✅ Status**: Fully implemented and validated (November 22, 2025)
>
> All Snowflake scripts have been tested and are production-ready. The implementation includes:
> - Automated setup via `validate_setup.sh`
> - Proper handling of Snowflake's dual variable system
> - Complete tenant isolation with database-per-tenant architecture
> - Comprehensive logging and error handling

### 3.1 Initialize Snowflake Account

> **Note**: All Snowflake scripts have been validated and are available in `infrastructure/snowflake/`

#### Quick Start - Complete Snowflake Setup

```bash
# Navigate to Snowflake scripts directory
cd infrastructure/snowflake

# Set your Snowflake password
export SNOWSQL_PWD="your_password"

# Run the complete setup with validation
./validate_setup.sh test_tenant "Test Tenant" eu-west-2 5

# Check the logs if needed
ls -la /tmp/smdh_*.log
```

#### What Gets Created

Running the validation script creates:

1. **Infrastructure Database** (`SMDH_INFRASTRUCTURE`)
   - Tenant registry and configuration
   - Monitoring and audit schemas
   - Platform-wide roles and permissions

2. **Tenant Database** (`SMDH_TENANT_<tenant_id>`)
   - Four data schemas: raw, normalized, aggregated, analytics
   - File formats for JSON, CSV, and Parquet
   - Internal stages for file uploads and error handling
   - Tenant-specific roles with proper permissions

3. **Shared Resources**
   - Multiple warehouses with auto-suspend
   - Base roles for inheritance
   - Monitoring views and procedures

#### Core Infrastructure Setup (01_infrastructure_setup.sql)

```sql
-- Connect to Snowflake as account admin
-- snowsql -a <account> -u <user> -r ACCOUNTADMIN

USE ROLE ACCOUNTADMIN;

-- Create organizational database
CREATE DATABASE IF NOT EXISTS smdh_infrastructure
    DATA_RETENTION_TIME_IN_DAYS = 7
    COMMENT = 'SMDH platform infrastructure and shared resources. Contains tenant metadata, monitoring data, and audit logs.';

USE DATABASE smdh_infrastructure;

-- Create shared schemas
CREATE SCHEMA IF NOT EXISTS tenant_configs
    DATA_RETENTION_TIME_IN_DAYS = 7
    COMMENT = 'Tenant metadata, configuration, and registry. Central source of truth for all SMDH tenants.';

CREATE SCHEMA IF NOT EXISTS monitoring
    DATA_RETENTION_TIME_IN_DAYS = 30
    COMMENT = 'Platform-wide monitoring, metrics, and health checks. Used for operational dashboards.';

CREATE SCHEMA IF NOT EXISTS audit
    DATA_RETENTION_TIME_IN_DAYS = 90
    COMMENT = 'Audit logs, access tracking, and compliance records. Retained for 90 days for security compliance.';

-- Create tenant registry table
USE SCHEMA tenant_configs;

CREATE TABLE IF NOT EXISTS tenants (
    tenant_id VARCHAR(100) PRIMARY KEY,
    tenant_name VARCHAR(500) NOT NULL,
    status VARCHAR(50) DEFAULT 'provisioning',
    created_date TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    updated_date TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    aws_region VARCHAR(50),
    num_sites NUMBER(10),
    warehouse_size VARCHAR(50) DEFAULT 'XSMALL',
    data_retention_days NUMBER(10) DEFAULT 730,
    billing_contact VARCHAR(255),
    technical_contact VARCHAR(255),
    metadata VARIANT,
    CONSTRAINT valid_status CHECK (status IN ('provisioning', 'active', 'suspended', 'offboarded'))
);

-- Create site registry
CREATE TABLE IF NOT EXISTS sites (
    site_id VARCHAR(100) PRIMARY KEY,
    tenant_id VARCHAR(100) NOT NULL,
    site_name VARCHAR(500),
    location VARCHAR(1000),
    gateway_count NUMBER(10) DEFAULT 0,
    sensor_count NUMBER(10) DEFAULT 0,
    created_date TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    updated_date TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    metadata VARIANT,
    CONSTRAINT fk_tenant FOREIGN KEY (tenant_id) REFERENCES tenants(tenant_id)
);

-- Create role for infrastructure management
CREATE ROLE IF NOT EXISTS smdh_infrastructure_admin
    COMMENT = 'Admin role for SMDH platform management. Has full access to infrastructure database.';

GRANT ALL ON DATABASE smdh_infrastructure TO ROLE smdh_infrastructure_admin;
GRANT ALL ON ALL SCHEMAS IN DATABASE smdh_infrastructure TO ROLE smdh_infrastructure_admin;
```

### 3.2 Create Shared Warehouse

```sql
-- Create shared warehouse for infrastructure operations
CREATE WAREHOUSE IF NOT EXISTS smdh_infrastructure_wh
  WAREHOUSE_SIZE = 'xsmall'
  AUTO_SUSPEND = 60
  AUTO_RESUME = true
  INITIALLY_SUSPENDED = false;

-- Create warehouses for tenant ETL
CREATE WAREHOUSE IF NOT EXISTS smdh_etl_wh
  WAREHOUSE_SIZE = 'small'
  AUTO_SUSPEND = 120
  AUTO_RESUME = true
  INITIALLY_SUSPENDED = false;

CREATE WAREHOUSE IF NOT EXISTS smdh_analytics_wh
  WAREHOUSE_SIZE = 'medium'
  AUTO_SUSPEND = 300
  AUTO_RESUME = true
  INITIALLY_SUSPENDED = false;
```

### 3.3 Snowflake Directory Structure

The Snowflake implementation is organized as follows:

```
infrastructure/snowflake/
├── validate_setup.sh                    # Master validation script
├── 00_drop_all.sql                     # Clean slate script (use with caution)
├── 01_infrastructure_setup.sql         # Core infrastructure database
├── 02_shared_resources.sql             # Warehouses and shared roles
├── 03_openflow_connector.sql           # Kinesis connector configuration
└── tenant/
    ├── 10_create_tenant_database.sql   # Tenant database and schemas
    ├── 11_create_schemas.sql            # Additional schema setup
    ├── 12_create_tables.sql             # Core data tables
    ├── 13_create_streams.sql            # Change data capture streams
    ├── 14_create_tasks.sql              # Processing tasks
    ├── 15_create_dynamic_tables.sql    # Aggregation tables
    ├── 16_create_roles.sql              # Tenant-specific roles
    └── 17_create_monitoring.sql         # Monitoring views and alerts
```

### 3.4 Snowflake Validation Script

The `validate_setup.sh` script automates the entire Snowflake setup and verification:

```bash
#!/bin/bash
# Usage: ./validate_setup.sh [tenant_id] [tenant_name] [aws_region] [num_sites]
# Example: ./validate_setup.sh test_tenant "Test Tenant" eu-west-2 5

# Key features:
# - Validates all required parameters
# - Sets up SnowSQL with proper variable substitution (-o variable_substitution=true)
# - Runs all scripts in the correct order
# - Handles both infrastructure and tenant setup
# - Provides detailed logging to /tmp/smdh_*.log
# - Verifies successful creation of all resources

# The script correctly handles Snowflake's dual variable system:
# - Passes SnowSQL variables via -D flags
# - Uses proper SQL session variables with SET statements
# - References variables correctly (& for SnowSQL, $ for SQL session)
```

#### Successfully Deployed Configuration

As of November 22, 2025, the following Snowflake resources have been successfully created and validated:

**Infrastructure Database:**
- Database: `SMDH_INFRASTRUCTURE`
- Schemas: `TENANT_CONFIGS`, `MONITORING`, `AUDIT`
- Tables: `tenants`, `sites`, `devices`, `gateway_registry`

**Test Tenant Configuration:**
- Database: `SMDH_TENANT_TEST_TENANT`
- Schemas: `RAW`, `NORMALIZED`, `AGGREGATED`, `ANALYTICS`
- Roles: `smdh_tenant_test_tenant_admin`, `smdh_tenant_test_tenant_user`, `smdh_tenant_test_tenant_readonly`
- File Formats: `ff_json`, `ff_csv`, `ff_parquet`
- Stages: `stage_uploads`, `stage_errors`

### 3.5 Implementation Status Summary

**✅ Fully Implemented and Working:**
- Infrastructure database setup (`SMDH_INFRASTRUCTURE`)
- Tenant database creation (`SMDH_TENANT_<tenant_id>`)
- All schemas (raw, normalized, aggregated, analytics)
- Role-based access control (admin, user, readonly roles)
- File formats and internal stages
- Tenant metadata tables
- Validation and verification scripts
- Proper variable handling in all SQL scripts

**🔄 Partially Implemented:**
- Dynamic tables (DDL created, not yet populated with real data)
- Tasks and streams (created but not processing real sensor data yet)
- Monitoring views (structure in place, awaiting real data)

**⏳ Not Yet Implemented (Requires Additional Setup):**
- Openflow/Snowpipe connector for Kinesis integration
- Real-time data ingestion from IoT Core
- Streamlit portal for tenant analytics
- Production monitoring and alerting

### 3.6 Create Openflow Connector Integration

```sql
-- Note: This step requires Snowflake Enterprise or higher
-- and Openflow connector to be configured by Snowflake

-- Create connector object (run as account admin)
-- This is a placeholder - actual configuration requires Snowflake support
CREATE OR REPLACE EXTERNAL VOLUME smdh_kinesis_volume
  TYPE = S3
  LOCATION = (
    URL = 's3://smdh-openflow-bucket/'
  );

-- Configure connector permissions
GRANT READ, WRITE ON EXTERNAL VOLUME smdh_kinesis_volume
  TO ROLE smdh_infrastructure_admin;

-- Alternative: Use Snowpipe for S3-based ingestion
-- If Kinesis writes to S3, you can use Snowpipe instead
CREATE OR REPLACE PIPE smdh_sensor_data_pipe
  AUTO_INGEST = TRUE
  AS
  COPY INTO smdh_tenant_test_tenant.raw.sensor_readings
  FROM @smdh_s3_stage
  FILE_FORMAT = (TYPE = 'JSON');
```

---

## 4. Tenant Onboarding Procedures

### 4.1 Tenant Onboarding Checklist and Timeline

| Phase | Component | Steps | Est. Time |
| --- | --- | --- | --- |
| Planning | Business Setup | Gather requirements, SLA definition | 30 min |
| Identity | AWS & Snowflake | Create accounts, assign roles | 30 min |
| AWS Setup | IoT Core | Thing registry, certificates, policies, rules | 45 min |
| Snowflake Setup | Database | Database, schemas, tables, streams, tasks | 45 min |
| Application | Portal | Streamlit config, UI customization | 30 min |
| Validation | Testing | E2E test, monitoring verification | 30 min |
| **Total** | | | ~3.5 hours |

### 4.2 Phase 1: Gathering Requirements

```bash
#!/bin/bash
# Tenant Requirements Gathering Script

read -p "Tenant ID (lowercase, alphanumeric): " TENANT_ID
read -p "Tenant Name: " TENANT_NAME
read -p "Number of sites: " NUM_SITES
read -p "Number of sensors per site: " SENSORS_PER_SITE
read -p "Data retention (days): " RETENTION_DAYS
read -p "Primary contact email: " CONTACT_EMAIL

# Validation
if ! [[ $TENANT_ID =~ ^[a-z0-9_]+$ ]]; then
  echo "Error: Tenant ID must be lowercase alphanumeric"
  exit 1
fi

# Save to configuration file
cat > tenant_config_${TENANT_ID}.env << EOF
TENANT_ID=$TENANT_ID
TENANT_NAME=$TENANT_NAME
NUM_SITES=$NUM_SITES
SENSORS_PER_SITE=$SENSORS_PER_SITE
RETENTION_DAYS=$RETENTION_DAYS
CONTACT_EMAIL=$CONTACT_EMAIL
AWS_REGION=eu-west-2
CREATED_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF

echo "✓ Configuration saved to tenant_config_${TENANT_ID}.env"
```

### 4.3 Phase 2: AWS IoT Setup

#### Step 2.1: Create IoT Thing Type

```bash
#!/bin/bash
source tenant_config_${TENANT_ID}.env

aws iot create-thing-type \
  --thing-type-name "LoRaWANGateway" \
  --thing-type-properties searchableAttributes=tenant_id,site_id,location \
  --region $AWS_REGION \
  --output json > thing-type-response.json

echo "✓ IoT Thing Type created"
```

#### Step 2.2: Create IoT Thing Registry Entries

```bash
#!/bin/bash
source tenant_config_${TENANT_ID}.env

# Create a thing for each site/gateway combination
for ((site=1; site<=$NUM_SITES; site++)); do
  SITE_ID="site_$(printf '%03d' $site)"
  THING_NAME="smdh-gateway-${TENANT_ID}-${SITE_ID}-gw_001"

  aws iot create-thing \
    --thing-name "$THING_NAME" \
    --thing-type-name "LoRaWANGateway" \
    --attribute-payload "{
      \"attributes\": {
        \"tenant_id\": \"${TENANT_ID}\",
        \"site_id\": \"${SITE_ID}\",
        \"deployment_date\": \"$(date -u +%Y-%m-%d)\",
        \"location\": \"Site $site\",
        \"device_type\": \"gateway\"
      }
    }" \
    --region $AWS_REGION

  echo "✓ Created Thing: $THING_NAME"
done
```

#### Step 2.3: Generate X.509 Certificates

```bash
#!/bin/bash
source tenant_config_${TENANT_ID}.env

# Create certificates directory
mkdir -p certificates/${TENANT_ID}
cd certificates/${TENANT_ID}

for ((site=1; site<=$NUM_SITES; site++)); do
  SITE_ID=$(printf '%03d' $site)
  CERT_NAME="${TENANT_ID}-site-${SITE_ID}"

  # Generate certificate
  CERT_ARN=$(aws iot create-keys-and-certificate \
    --set-as-active \
    --certificate-pem-outfile "${CERT_NAME}-cert.pem" \
    --private-key-outfile "${CERT_NAME}-private.key" \
    --region $AWS_REGION \
    --query 'certificateArn' \
    --output text)

  # Download CA certificate
  curl -o AmazonRootCA1.pem https://www.amazontrust.com/repository/AmazonRootCA1.pem

  echo "✓ Certificate generated: $CERT_NAME"
  echo "ARN: $CERT_ARN"
done

cd ../..
```

#### Step 2.4: Create IoT Policy

```bash
#!/bin/bash
source tenant_config_${TENANT_ID}.env

# Create policy document
cat > iot-policy-${TENANT_ID}.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "iot:Connect",
      "Resource": "arn:aws:iot:${AWS_REGION}:${AWS_ACCOUNT_ID}:client/smdh-*-${TENANT_ID}-*"
    },
    {
      "Effect": "Allow",
      "Action": "iot:Publish",
      "Resource": [
        "arn:aws:iot:${AWS_REGION}:${AWS_ACCOUNT_ID}:topic/smdh/${TENANT_ID}/*/sensor-data",
        "arn:aws:iot:${AWS_REGION}:${AWS_ACCOUNT_ID}:topic/smdh/${TENANT_ID}/*/device-status"
      ]
    },
    {
      "Effect": "Allow",
      "Action": "iot:Subscribe",
      "Resource": "arn:aws:iot:${AWS_REGION}:${AWS_ACCOUNT_ID}:topicfilter/smdh/${TENANT_ID}/commands/*"
    },
    {
      "Effect": "Allow",
      "Action": "iot:Receive",
      "Resource": "arn:aws:iot:${AWS_REGION}:${AWS_ACCOUNT_ID}:topic/smdh/${TENANT_ID}/commands/*"
    }
  ]
}
EOF

# Create policy
aws iot create-policy \
  --policy-name "smdh-policy-${TENANT_ID}" \
  --policy-document file://iot-policy-${TENANT_ID}.json \
  --region $AWS_REGION

echo "✓ IoT Policy created: smdh-policy-${TENANT_ID}"
```

#### Step 2.5: Attach Certificates to Policy

```bash
#!/bin/bash
source tenant_config_${TENANT_ID}.env

# Get all certificates
CERTS=$(aws iot list-certificates \
  --region $AWS_REGION \
  --query "certificates[?certificateStatus=='ACTIVE'].certificateArn" \
  --output text)

# Attach policy to certificates for this tenant
for CERT_ARN in $CERTS; do
  # Only attach to this tenant's certificates
  if [[ $CERT_ARN == *"${TENANT_ID}"* ]]; then
    CERT_ID=$(echo $CERT_ARN | awk -F'/' '{print $NF}')

    aws iot attach-policy \
      --policy-name "smdh-policy-${TENANT_ID}" \
      --target $CERT_ARN \
      --region $AWS_REGION

    echo "✓ Policy attached to certificate: $CERT_ID"
  fi
done
```

#### Step 2.6: Create IoT Rules Engine Rule

```bash
#!/bin/bash
source tenant_config_${TENANT_ID}.env

# Create IoT rule for tenant
cat > iot-rule-${TENANT_ID}.json << 'EOF'
{
  "sql": "SELECT *, topic(2) as tenant_id, topic(3) as site_id, timestamp() as iot_timestamp, clientId() as device_id FROM 'smdh/+/+/sensor-data' WHERE topic(2) = '${TENANT_ID}' AND timestamp IS NOT NULL",
  "actions": [
    {
      "kinesis": {
        "roleArn": "arn:aws:iam::${AWS_ACCOUNT_ID}:role/iot-core-kinesis-role",
        "streamName": "smdh-sensor-data-stream",
        "partitionKey": "${TENANT_ID}"
      }
    }
  ],
  "errorAction": {
    "republish": {
      "roleArn": "arn:aws:iam::${AWS_ACCOUNT_ID}:role/iot-core-kinesis-role",
      "topic": "smdh/errors/${TENANT_ID}"
    }
  }
}
EOF

aws iot create-topic-rule \
  --rule-name "smdh_route_${TENANT_ID}" \
  --topic-rule-payload file://iot-rule-${TENANT_ID}.json \
  --region $AWS_REGION

echo "✓ IoT Rule created: smdh_route_${TENANT_ID}"
```

### 4.4 Phase 3: Snowflake Setup

#### Step 3.1: Create Tenant Database

> **Important**: Snowflake has two variable systems:
> - **SnowSQL variables** (`&variable`): Client-side substitution via `-D` flag
> - **SQL session variables** (`$variable`): Server-side variables created with `SET`

```bash
# Using the automated script
cd infrastructure/snowflake
export SNOWSQL_PWD="your_password"

# Run tenant creation for a specific tenant
snowsql -r ACCOUNTADMIN -o variable_substitution=true \
  -D tenant_id=company_a \
  -D tenant_name="Company A Ltd" \
  -D aws_region=eu-west-2 \
  -D num_sites=5 \
  -f tenant/10_create_tenant_database.sql
```

Or run manually with proper variable handling:

```sql
-- Connect as account admin
-- snowsql -a <account> -u admin_user -r ACCOUNTADMIN -o variable_substitution=true

-- For manual execution, pass variables via -D flag
-- snowsql ... -D tenant_id=company_a -D tenant_name="Company A"

-- The script uses both variable types correctly:
SET database_name = 'smdh_tenant_' || '&tenant_id';  -- Creates SQL session variable

-- Create database with proper variable reference
CREATE DATABASE IF NOT EXISTS IDENTIFIER($database_name)
    DATA_RETENTION_TIME_IN_DAYS = 7
    COMMENT = 'SMDH Tenant Database for &tenant_name. Isolated database per tenant for complete data separation.';

-- Use the database
USE DATABASE IDENTIFIER($database_name);

-- Create schemas
CREATE SCHEMA IF NOT EXISTS raw
    DATA_RETENTION_TIME_IN_DAYS = 7
    COMMENT = 'Raw ingested sensor data from IoT devices. Minimal transformation, preserves original payload structure.';

CREATE SCHEMA IF NOT EXISTS normalized
    DATA_RETENTION_TIME_IN_DAYS = 7
    COMMENT = 'Cleaned, normalized, and validated data. Ready for analytics and aggregation.';

CREATE SCHEMA IF NOT EXISTS aggregated
    DATA_RETENTION_TIME_IN_DAYS = 30
    COMMENT = 'Pre-aggregated metrics and KPIs. Used for dashboards and reporting. Longer retention for historical analysis.';

CREATE SCHEMA IF NOT EXISTS analytics
    DATA_RETENTION_TIME_IN_DAYS = 30
    COMMENT = 'Analytics views, ML model results, and business intelligence objects.';
```

#### Step 3.2: Create Tables

```sql
-- Set tenant ID variable
SET TENANT_ID = 'company_a';

-- Raw sensor readings table
CREATE TABLE IF NOT EXISTS smdh_tenant_&{TENANT_ID}.raw.sensor_readings (
  sensor_id VARCHAR(255) NOT NULL,
  tenant_id VARCHAR(100) NOT NULL,
  timestamp TIMESTAMP_NTZ NOT NULL,
  payload VARIANT NOT NULL,
  ingestion_timestamp TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
  source_system VARCHAR(100),
  mqtt_topic VARCHAR(500),
  PRIMARY KEY (tenant_id, sensor_id, timestamp),
  CONSTRAINT valid_tenant CHECK (tenant_id = '&{TENANT_ID}')
)
CLUSTER BY (DATE_TRUNC('day', timestamp), sensor_id);

-- Gateway connection log table
CREATE TABLE IF NOT EXISTS smdh_tenant_&{TENANT_ID}.raw.gateway_connections (
  gateway_id VARCHAR(255) NOT NULL,
  tenant_id VARCHAR(100) NOT NULL,
  connection_time TIMESTAMP_NTZ NOT NULL,
  disconnection_time TIMESTAMP_NTZ,
  status VARCHAR(50),
  error_message VARCHAR(1000),
  ingestion_timestamp TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
  PRIMARY KEY (tenant_id, gateway_id, connection_time)
);

-- File upload tracking table
CREATE TABLE IF NOT EXISTS smdh_tenant_&{TENANT_ID}.raw.uploaded_files (
  file_id VARCHAR(255) PRIMARY KEY,
  tenant_id VARCHAR(100) NOT NULL,
  file_name VARCHAR(500),
  file_size NUMBER(20),
  upload_timestamp TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
  uploaded_by VARCHAR(255),
  file_path VARCHAR(1000),
  status VARCHAR(50),
  CONSTRAINT valid_tenant CHECK (tenant_id = '&{TENANT_ID}')
);

-- API events table
CREATE TABLE IF NOT EXISTS smdh_tenant_&{TENANT_ID}.raw.api_events (
  event_id VARCHAR(255) PRIMARY KEY,
  tenant_id VARCHAR(100) NOT NULL,
  event_type VARCHAR(100),
  timestamp TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
  user_id VARCHAR(255),
  details VARIANT,
  CONSTRAINT valid_tenant CHECK (tenant_id = '&{TENANT_ID}')
);

-- Normalized sensor metrics table
CREATE TABLE IF NOT EXISTS smdh_tenant_&{TENANT_ID}.normalized.sensor_metrics (
  sensor_id VARCHAR(255) NOT NULL,
  tenant_id VARCHAR(100) NOT NULL,
  timestamp TIMESTAMP_NTZ NOT NULL,
  metric_name VARCHAR(255),
  metric_value FLOAT,
  metric_unit VARCHAR(50),
  quality_flag VARCHAR(50),
  normalized_timestamp TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
  PRIMARY KEY (tenant_id, sensor_id, timestamp, metric_name),
  CONSTRAINT valid_tenant CHECK (tenant_id = '&{TENANT_ID}')
)
CLUSTER BY (DATE_TRUNC('day', timestamp), sensor_id);
```

#### Step 3.3: Create Streams for CDC

```sql
SET TENANT_ID = 'company_a';

-- Create stream on raw sensor data for real-time processing
CREATE STREAM IF NOT EXISTS smdh_tenant_&{TENANT_ID}.raw.sensor_readings_stream
  ON TABLE smdh_tenant_&{TENANT_ID}.raw.sensor_readings
  APPEND_ONLY = TRUE
  COMMENT = 'Captures new sensor readings for processing';

-- Create stream on file uploads
CREATE STREAM IF NOT EXISTS smdh_tenant_&{TENANT_ID}.raw.uploaded_files_stream
  ON TABLE smdh_tenant_&{TENANT_ID}.raw.uploaded_files
  COMMENT = 'Captures file upload events';
```

#### Step 3.4: Create Processing Tasks

```sql
SET TENANT_ID = 'company_a';
USE WAREHOUSE smdh_etl_wh;

-- Task 1: Process sensor readings
CREATE TASK IF NOT EXISTS smdh_tenant_&{TENANT_ID}.raw.process_sensor_data
  WAREHOUSE = smdh_etl_wh
  SCHEDULE = '1 minute'
  WHEN SYSTEM$STREAM_HAS_DATA('smdh_tenant_&{TENANT_ID}.raw.sensor_readings_stream')
AS
  INSERT INTO smdh_tenant_&{TENANT_ID}.normalized.sensor_metrics
  SELECT
    sensor_id,
    tenant_id,
    timestamp,
    'sensor_value' as metric_name,
    TRY_CAST(payload:value as FLOAT) as metric_value,
    TRY_CAST(payload:unit as VARCHAR) as metric_unit,
    CASE
      WHEN payload:quality IS NOT NULL THEN payload:quality
      ELSE 'good'
    END as quality_flag,
    CURRENT_TIMESTAMP() as normalized_timestamp
  FROM smdh_tenant_&{TENANT_ID}.raw.sensor_readings_stream
  WHERE payload:value IS NOT NULL;

-- Enable the task (initially suspended)
ALTER TASK smdh_tenant_&{TENANT_ID}.raw.process_sensor_data RESUME;
```

#### Step 3.5: Create Dynamic Tables for Aggregation

```sql
SET TENANT_ID = 'company_a';

-- Hourly aggregation of sensor metrics
CREATE DYNAMIC TABLE IF NOT EXISTS smdh_tenant_&{TENANT_ID}.aggregated.sensor_hourly
  TARGET_LAG = '10 minutes'
  WAREHOUSE = smdh_etl_wh
AS
SELECT
  sensor_id,
  tenant_id,
  DATE_TRUNC('hour', timestamp) as hour,
  metric_name,
  COUNT(*) as reading_count,
  AVG(CASE WHEN TRY_CAST(metric_value as FLOAT) IS NOT NULL THEN TRY_CAST(metric_value as FLOAT) END) as avg_value,
  MIN(CASE WHEN TRY_CAST(metric_value as FLOAT) IS NOT NULL THEN TRY_CAST(metric_value as FLOAT) END) as min_value,
  MAX(CASE WHEN TRY_CAST(metric_value as FLOAT) IS NOT NULL THEN TRY_CAST(metric_value as FLOAT) END) as max_value,
  STDDEV_POP(CASE WHEN TRY_CAST(metric_value as FLOAT) IS NOT NULL THEN TRY_CAST(metric_value as FLOAT) END) as stddev_value
FROM smdh_tenant_&{TENANT_ID}.normalized.sensor_metrics
GROUP BY sensor_id, tenant_id, DATE_TRUNC('hour', timestamp), metric_name;

-- Daily aggregation
CREATE DYNAMIC TABLE IF NOT EXISTS smdh_tenant_&{TENANT_ID}.aggregated.sensor_daily
  TARGET_LAG = '1 hour'
  WAREHOUSE = smdh_etl_wh
AS
SELECT
  sensor_id,
  tenant_id,
  DATE_TRUNC('day', timestamp) as day,
  metric_name,
  COUNT(*) as reading_count,
  AVG(CASE WHEN TRY_CAST(metric_value as FLOAT) IS NOT NULL THEN TRY_CAST(metric_value as FLOAT) END) as avg_value,
  MIN(CASE WHEN TRY_CAST(metric_value as FLOAT) IS NOT NULL THEN TRY_CAST(metric_value as FLOAT) END) as min_value,
  MAX(CASE WHEN TRY_CAST(metric_value as FLOAT) IS NOT NULL THEN TRY_CAST(metric_value as FLOAT) END) as max_value
FROM smdh_tenant_&{TENANT_ID}.normalized.sensor_metrics
GROUP BY sensor_id, tenant_id, DATE_TRUNC('day', timestamp), metric_name;
```

#### Step 3.6: Create Roles and User Access

```sql
SET TENANT_ID = 'company_a';

-- Create tenant user role
CREATE ROLE IF NOT EXISTS tenant_&{TENANT_ID}_user;

-- Create tenant admin role
CREATE ROLE IF NOT EXISTS tenant_&{TENANT_ID}_admin;

-- Grant database access to user role
GRANT USAGE ON DATABASE smdh_tenant_&{TENANT_ID}
  TO ROLE tenant_&{TENANT_ID}_user;

-- Grant schema access
GRANT USAGE ON ALL SCHEMAS IN DATABASE smdh_tenant_&{TENANT_ID}
  TO ROLE tenant_&{TENANT_ID}_user;

-- Grant table read access
GRANT SELECT ON ALL TABLES IN DATABASE smdh_tenant_&{TENANT_ID}
  TO ROLE tenant_&{TENANT_ID}_user;

-- Grant warehouse access
GRANT USAGE ON WAREHOUSE smdh_analytics_wh
  TO ROLE tenant_&{TENANT_ID}_user;

-- Grant admin role full ownership
GRANT OWNERSHIP ON DATABASE smdh_tenant_&{TENANT_ID}
  TO ROLE tenant_&{TENANT_ID}_admin;

-- Create actual users (example)
CREATE USER IF NOT EXISTS john.smith_&{TENANT_ID}
  EMAIL = 'john.smith@company.com'
  DISPLAY_NAME = 'John Smith'
  DEFAULT_WAREHOUSE = smdh_analytics_wh
  DEFAULT_ROLE = tenant_&{TENANT_ID}_user;

-- Grant role to user
GRANT ROLE tenant_&{TENANT_ID}_user TO USER john.smith_&{TENANT_ID};
```

#### Step 3.7: Configure Data Retention

```sql
SET TENANT_ID = 'company_a';
SET RETENTION_DAYS = 730;  -- 2 years

-- Set time travel retention (for failsafe storage)
ALTER TABLE smdh_tenant_&{TENANT_ID}.raw.sensor_readings
  SET DATA_RETENTION_TIME_IN_DAYS = &{RETENTION_DAYS};

ALTER TABLE smdh_tenant_&{TENANT_ID}.normalized.sensor_metrics
  SET DATA_RETENTION_TIME_IN_DAYS = &{RETENTION_DAYS};
```

---

## 5. Table Definitions

### 5.1 Data Model Overview

```
smdh_tenant_{tenant_id}
├── raw (incoming data)
│   ├── sensor_readings
│   ├── gateway_connections
│   ├── uploaded_files
│   ├── api_events
│   └── [streams for CDC]
├── normalized (cleaned data)
│   ├── sensor_metrics
│   └── [enriched data]
├── aggregated (materialized views)
│   ├── sensor_hourly
│   └── sensor_daily
└── analytics (derived tables)
    └── [custom metrics]
```

### 5.2 Complete Table Schema Reference

See section 3.2 above for full CREATE TABLE statements.

### 5.3 Indexing Strategy

```sql
-- Clustering keys are defined in CREATE TABLE statements
-- Primary keys provide implicit indexes

-- Add explicit secondary indexes if needed:
CREATE INDEX idx_sensor_timestamp
  ON smdh_tenant_&{TENANT_ID}.raw.sensor_readings(timestamp);

CREATE INDEX idx_gateway_connections
  ON smdh_tenant_&{TENANT_ID}.raw.gateway_connections(gateway_id, connection_time);
```

---

## 6. Gateway Device Setup

### 6.1 Milesight UG65 LoRaWAN Gateway Setup

**Physical Configuration:**

1. Power on gateway
2. Connect to local Wi-Fi network
3. Access web interface at `http://<gateway-ip>`
4. Login with default credentials (check device documentation)

**MQTT Configuration in Web UI:**

```
MQTT Server Address: <IOT_ENDPOINT>
MQTT Server Port: 8883
Enable TLS: YES
Protocol Version: MQTT v3.1.1

Client ID: smdh-gateway-{tenant_id}-{site_id}
Username: [Leave blank]
Password: [Leave blank]

Certificate Method: Certificate File
CA Certificate: AmazonRootCA1.pem
Device Certificate: {tenant_id}-site-{site_id}-cert.pem
Device Key: {tenant_id}-site-{site_id}-private.key

MQTT Publish Topic: smdh/{tenant_id}/sensor-data
MQTT Subscribe Topic: smdh/{tenant_id}/commands/#
QoS: 1 (At least once)
Keep Alive: 60 seconds
Offline Message Buffer: 10000

Reconnect Interval: 30 seconds
Max Reconnect Interval: 300 seconds
```

**Steps:**
1. Upload AmazonRootCA1.pem
2. Upload device certificate ({tenant_id}-site-{site_id}-cert.pem)
3. Upload device private key ({tenant_id}-site-{site_id}-private.key)
4. Set MQTT server address to {IOT_ENDPOINT}
5. Verify connection shows "Connected"

### 6.2 DevTank OpenSmartMonitor (OSM) Wi-Fi Setup

**Network Configuration:**

1. Power on DevTank device
2. Scan for Wi-Fi network: "DevTank-Setup-{XXXX}"
3. Connect to DevTank Wi-Fi with default password
4. Access configuration portal at `http://192.168.4.1`
5. Select production Wi-Fi network and enter credentials

**MQTT Configuration:**

```
MQTT Broker: {IOT_ENDPOINT}
Port: 8883
Protocol: MQTT over TLS

Client ID: smdh-osm-{tenant_id}-{site_id}
TLS Enabled: TRUE

Certificate Setup:
- CA Certificate: AmazonRootCA1.pem
- Client Certificate: {tenant_id}-site-{site_id}-cert.pem
- Client Key: {tenant_id}-site-{site_id}-private.key

Publish Topics:
- Air Quality: smdh/{tenant_id}/devtank-data/air-quality
- Energy: smdh/{tenant_id}/devtank-data/energy
- Environment: smdh/{tenant_id}/devtank-data/environment

QoS: 1
Frequency: 5 minutes (configurable)
```

### 6.3 Certificate Deployment to Devices

```bash
#!/bin/bash
# Script to copy certificates to gateway via SCP

GATEWAY_IP=$1
TENANT_ID=$2
SITE_ID=$(printf '%03d' $3)

# Connect to gateway
ssh -i gateway_key.pem ubuntu@${GATEWAY_IP} << EOF
  # Create certificate directory
  mkdir -p /etc/ssl/certs/mqtt

  # Copy certificates (via SCP or manual upload)
  # They should be placed in /etc/ssl/certs/mqtt/

  # Verify permissions
  chmod 600 /etc/ssl/certs/mqtt/*-private.key
  chmod 644 /etc/ssl/certs/mqtt/*-cert.pem
  chmod 644 /etc/ssl/certs/mqtt/AmazonRootCA1.pem

  # Restart MQTT client service
  systemctl restart mqtt-client

  # Verify connection
  journalctl -u mqtt-client -n 20
EOF

echo "✓ Certificates deployed to ${GATEWAY_IP}"
```

---

## 7. Monitoring and Alerting

### 7.1 CloudWatch Dashboard Setup

```bash
#!/bin/bash
source tenant_config_${TENANT_ID}.env

# Create CloudWatch dashboard for tenant
cat > dashboard-${TENANT_ID}.json << 'EOF'
{
  "widgets": [
    {
      "type": "metric",
      "properties": {
        "metrics": [
          [ "AWS/IoT", "PublishIn.Success", { "stat": "Sum" } ],
          [ ".", "PublishIn.Failure", { "stat": "Sum" } ],
          [ ".", "Connect.Success", { "stat": "Sum" } ],
          [ ".", "Connect.Failure", { "stat": "Sum" } ]
        ],
        "period": 60,
        "stat": "Sum",
        "region": "${AWS_REGION}",
        "title": "IoT Core Metrics"
      }
    },
    {
      "type": "metric",
      "properties": {
        "metrics": [
          [ "AWS/Kinesis", "GetRecords.IteratorAgeMilliseconds", { "stat": "Maximum" } ],
          [ ".", "GetRecords.Success", { "stat": "Sum" } ],
          [ ".", "PutRecord.Success", { "stat": "Sum" } ]
        ],
        "period": 60,
        "stat": "Average",
        "region": "${AWS_REGION}",
        "title": "Kinesis Stream Metrics"
      }
    }
  ]
}
EOF

aws cloudwatch put-dashboard \
  --dashboard-name "smdh-${TENANT_ID}-dashboard" \
  --dashboard-body file://dashboard-${TENANT_ID}.json \
  --region $AWS_REGION

echo "✓ CloudWatch dashboard created"
```

### 7.2 CloudWatch Alarms

```bash
#!/bin/bash
source tenant_config_${TENANT_ID}.env

# Alarm 1: Connection failures
aws cloudwatch put-metric-alarm \
  --alarm-name "smdh-${TENANT_ID}-connection-failures" \
  --alarm-description "Alert on connection failures" \
  --metric-name Connect.Failure \
  --namespace AWS/IoT \
  --statistic Sum \
  --period 300 \
  --evaluation-periods 1 \
  --threshold 5 \
  --comparison-operator GreaterThanOrEqualToThreshold \
  --alarm-actions "arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:smdh-alerts-${TENANT_ID}" \
  --region $AWS_REGION

# Alarm 2: Kinesis iterator age
aws cloudwatch put-metric-alarm \
  --alarm-name "smdh-${TENANT_ID}-kinesis-iterator-age" \
  --alarm-description "Alert on high iterator age" \
  --metric-name GetRecords.IteratorAgeMilliseconds \
  --namespace AWS/Kinesis \
  --statistic Maximum \
  --period 60 \
  --evaluation-periods 1 \
  --threshold 60000 \
  --comparison-operator GreaterThanThreshold \
  --alarm-actions "arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:smdh-alerts-${TENANT_ID}" \
  --region $AWS_REGION

# Alarm 3: Certificate expiry
aws cloudwatch put-metric-alarm \
  --alarm-name "smdh-${TENANT_ID}-cert-expiry-warning" \
  --alarm-description "Alert when certificate expires in 7 days" \
  --metric-name CertificateDaysToExpiry \
  --namespace AWS/IoT \
  --statistic Minimum \
  --period 3600 \
  --evaluation-periods 1 \
  --threshold 7 \
  --comparison-operator LessThanOrEqualToThreshold \
  --alarm-actions "arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:smdh-alerts-${TENANT_ID}" \
  --region $AWS_REGION

echo "✓ CloudWatch alarms created"
```

### 7.3 SNS Topics for Alerts

```bash
#!/bin/bash
source tenant_config_${TENANT_ID}.env

# Create SNS topic for tenant alerts
aws sns create-topic \
  --name "smdh-alerts-${TENANT_ID}" \
  --region $AWS_REGION

# Subscribe email
aws sns subscribe \
  --topic-arn "arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:smdh-alerts-${TENANT_ID}" \
  --protocol email \
  --notification-endpoint "${CONTACT_EMAIL}" \
  --region $AWS_REGION

echo "✓ SNS topic and subscription created"
echo "Note: Confirm subscription via email"
```

### 7.4 Snowflake Monitoring

```sql
-- Query ingestion metrics
SET TENANT_ID = 'company_a';

SELECT
  TABLE_NAME,
  ROW_COUNT,
  BYTES,
  LAST_ALTERED,
  CREATED_ON
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = 'RAW'
  AND DATABASE_NAME = 'smdh_tenant_&{TENANT_ID}'
ORDER BY LAST_ALTERED DESC;

-- Monitor task execution
SELECT
  NAME,
  STATE,
  LAST_SCHEDULED_TIME,
  LAST_COMPLETED_TIME,
  LAST_ERROR_MESSAGE
FROM INFORMATION_SCHEMA.TASK_HISTORY
WHERE DATABASE_NAME = 'smdh_tenant_&{TENANT_ID}'
ORDER BY LAST_SCHEDULED_TIME DESC
LIMIT 50;
```

---

## 8. Automation Scripts

### 8.1 Complete Tenant Onboarding Script

```bash
#!/bin/bash
# SMDH Tenant Onboarding Automation Script
# Usage: ./onboard-tenant.sh company_a "Company A Ltd" 5 8 730

set -e

# Configuration
TENANT_ID=${1:-test_tenant}
TENANT_NAME=${2:-Test Tenant}
NUM_SITES=${3:-5}
SENSORS_PER_SITE=${4:-8}
RETENTION_DAYS=${5:-730}
AWS_REGION=${AWS_REGION:-eu-west-2}

# Validation
if ! [[ $TENANT_ID =~ ^[a-z0-9_]+$ ]]; then
  echo "❌ Error: Tenant ID must be lowercase alphanumeric"
  exit 1
fi

echo "🚀 Starting SMDH Tenant Onboarding"
echo "   Tenant ID: $TENANT_ID"
echo "   Tenant Name: $TENANT_NAME"
echo "   Sites: $NUM_SITES"
echo "   Sensors/Site: $SENSORS_PER_SITE"
echo ""

# Step 1: AWS IoT Setup
echo "📋 Step 1: Creating AWS IoT Resources..."

# Create thing type
aws iot create-thing-type \
  --thing-type-name "LoRaWANGateway" \
  --region $AWS_REGION 2>/dev/null || true

# Create things and certificates
mkdir -p certificates/${TENANT_ID}
cd certificates/${TENANT_ID}

for ((site=1; site<=$NUM_SITES; site++)); do
  SITE_ID=$(printf '%03d' $site)
  THING_NAME="smdh-gateway-${TENANT_ID}-site-${SITE_ID}"
  CERT_NAME="${TENANT_ID}-site-${SITE_ID}"

  # Create thing
  aws iot create-thing \
    --thing-name "$THING_NAME" \
    --thing-type-name "LoRaWANGateway" \
    --attribute-payload "{
      \"attributes\": {
        \"tenant_id\": \"${TENANT_ID}\",
        \"site_id\": \"site-${SITE_ID}\"
      }
    }" \
    --region $AWS_REGION

  # Generate certificate
  aws iot create-keys-and-certificate \
    --set-as-active \
    --certificate-pem-outfile "${CERT_NAME}-cert.pem" \
    --private-key-outfile "${CERT_NAME}-private.key" \
    --region $AWS_REGION

  # Download CA certificate
  curl -s -o AmazonRootCA1.pem \
    https://www.amazontrust.com/repository/AmazonRootCA1.pem

  echo "  ✓ Created: $THING_NAME"
done

cd ../..

# Create policy
cat > iot-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "iot:Connect",
      "Resource": "arn:aws:iot:${AWS_REGION}:*:client/smdh-gateway-${TENANT_ID}-*"
    },
    {
      "Effect": "Allow",
      "Action": "iot:Publish",
      "Resource": "arn:aws:iot:${AWS_REGION}:*:topic/smdh/${TENANT_ID}/*"
    }
  ]
}
EOF

aws iot create-policy \
  --policy-name "smdh-policy-${TENANT_ID}" \
  --policy-document file://iot-policy.json \
  --region $AWS_REGION

# Attach policy to certificates
for CERT in certificates/${TENANT_ID}/*-cert.pem; do
  CERT_ID=$(aws iot describe-certificate --certificate-id $(basename $CERT .pem) --region $AWS_REGION --query 'certificateDescription.certificateId' --output text 2>/dev/null)
  if [ ! -z "$CERT_ID" ]; then
    CERT_ARN=$(aws iot describe-certificate --certificate-id $CERT_ID --region $AWS_REGION --query 'certificateDescription.certificateArn' --output text)
    aws iot attach-policy --policy-name "smdh-policy-${TENANT_ID}" --target $CERT_ARN --region $AWS_REGION
  fi
done

echo "✅ AWS IoT setup complete"
echo ""

# Step 2: Snowflake Setup
echo "📋 Step 2: Creating Snowflake Database..."

# Option 1: Use the validated scripts
cd infrastructure/snowflake
export SNOWSQL_PWD="$SNOWFLAKE_PASSWORD"
snowsql -r ACCOUNTADMIN -o variable_substitution=true \
  -D tenant_id="${TENANT_ID}" \
  -D tenant_name="${TENANT_NAME}" \
  -D aws_region="${AWS_REGION}" \
  -D num_sites="${NUM_SITES}" \
  -f tenant/10_create_tenant_database.sql

# Option 2: Inline SQL with proper variable handling
snowsql -a $SNOWFLAKE_ACCOUNT -u $SNOWFLAKE_USER -r ACCOUNTADMIN \
  -o variable_substitution=true \
  -D tenant_id="${TENANT_ID}" \
  -f - << EOSQL
-- Set database name variable
SET database_name = 'smdh_tenant_' || '&tenant_id';

-- Create database with proper variable reference
CREATE DATABASE IF NOT EXISTS IDENTIFIER(\$database_name)
    DATA_RETENTION_TIME_IN_DAYS = 7
    COMMENT = 'SMDH Tenant Database. Isolated database per tenant for complete data separation.';

-- Use the database
USE DATABASE IDENTIFIER(\$database_name);

-- Create schemas
CREATE SCHEMA IF NOT EXISTS raw;
CREATE SCHEMA IF NOT EXISTS normalized;
CREATE SCHEMA IF NOT EXISTS aggregated;
CREATE SCHEMA IF NOT EXISTS analytics;

-- Create tables
CREATE TABLE IF NOT EXISTS smdh_tenant_${TENANT_ID}.raw.sensor_readings (
  sensor_id VARCHAR(255) NOT NULL,
  tenant_id VARCHAR(100) NOT NULL,
  timestamp TIMESTAMP_NTZ NOT NULL,
  payload VARIANT NOT NULL,
  ingestion_timestamp TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
  source_system VARCHAR(100),
  PRIMARY KEY (tenant_id, sensor_id, timestamp)
)
CLUSTER BY (DATE_TRUNC('day', timestamp), sensor_id);

-- Create roles
CREATE ROLE IF NOT EXISTS tenant_${TENANT_ID}_user;
GRANT USAGE ON DATABASE smdh_tenant_${TENANT_ID} TO ROLE tenant_${TENANT_ID}_user;
GRANT ALL ON ALL SCHEMAS IN DATABASE smdh_tenant_${TENANT_ID} TO ROLE tenant_${TENANT_ID}_user;
GRANT SELECT ON ALL TABLES IN DATABASE smdh_tenant_${TENANT_ID} TO ROLE tenant_${TENANT_ID}_user;

-- Register tenant in infrastructure db
INSERT INTO smdh_infrastructure.tenant_configs.tenants
VALUES ('${TENANT_ID}', '${TENANT_NAME}', 'active', CURRENT_TIMESTAMP(), '${AWS_REGION}', '${TENANT_ID}', ${RETENTION_DAYS}, 'small', '');
EOSQL

echo "✅ Snowflake setup complete"
echo ""

# Step 3: Create IoT Rules
echo "📋 Step 3: Creating IoT Rules..."

cat > iot-rule.json << 'EOF'
{
  "sql": "SELECT *, '${TENANT_ID}' as tenant_id FROM 'smdh/${TENANT_ID}/+'",
  "actions": [
    {
      "kinesis": {
        "roleArn": "arn:aws:iam::${AWS_ACCOUNT_ID}:role/iot-core-kinesis-role",
        "streamName": "smdh-sensor-data-stream",
        "partitionKey": "${TENANT_ID}"
      }
    }
  ]
}
EOF

aws iot create-topic-rule \
  --rule-name "smdh_route_${TENANT_ID}" \
  --topic-rule-payload file://iot-rule.json \
  --region $AWS_REGION

echo "✅ IoT Rules created"
echo ""

# Step 4: Create Alerts
echo "📋 Step 4: Creating Monitoring Alerts..."

aws sns create-topic --name "smdh-alerts-${TENANT_ID}" --region $AWS_REGION || true

aws cloudwatch put-metric-alarm \
  --alarm-name "smdh-${TENANT_ID}-connection-failures" \
  --alarm-description "Connection failures for ${TENANT_ID}" \
  --metric-name Connect.Failure \
  --namespace AWS/IoT \
  --statistic Sum \
  --period 300 \
  --threshold 5 \
  --comparison-operator GreaterThanOrEqualToThreshold \
  --region $AWS_REGION

echo "✅ Monitoring alerts created"
echo ""

# Cleanup
rm -f iot-policy.json iot-rule.json

echo "🎉 Tenant onboarding complete!"
echo ""
echo "📦 Deliverables:"
echo "   ✓ Certificates: certificates/${TENANT_ID}/"
echo "   ✓ Snowflake Database: smdh_tenant_${TENANT_ID}"
echo "   ✓ IoT Core configured with tenant policies"
echo "   ✓ Monitoring and alerts enabled"
echo ""
echo "📝 Next steps:"
echo "   1. Distribute certificates to gateways"
echo "   2. Configure gateway MQTT settings with endpoint"
echo "   3. Test data flow with sample messages"
echo "   4. Verify data appears in Snowflake"
```

### 8.2 Certificate Rotation Script

```bash
#!/bin/bash
# Certificate Rotation Script

TENANT_ID=$1
SITE_ID=$2
AWS_REGION=${AWS_REGION:-eu-west-2}

echo "🔄 Rotating certificate for ${TENANT_ID} - Site ${SITE_ID}..."

# Generate new certificate
CERT_ARN=$(aws iot create-keys-and-certificate \
  --set-as-active \
  --certificate-pem-outfile "${TENANT_ID}-site-${SITE_ID}-cert-new.pem" \
  --private-key-outfile "${TENANT_ID}-site-${SITE_ID}-private-new.key" \
  --region $AWS_REGION \
  --query 'certificateArn' \
  --output text)

# Attach policy to new certificate
aws iot attach-policy \
  --policy-name "smdh-policy-${TENANT_ID}" \
  --target $CERT_ARN \
  --region $AWS_REGION

# Update gateway with new certificate
echo "Upload new certificates to gateway and restart MQTT client"
echo "Old certificate will be automatically revoked after grace period"

# Schedule old certificate deactivation (30 days later)
echo "Certificate rotation scheduled. Old cert will be deactivated on $(date -u -d "+30 days" +%Y-%m-%d)"
```

---

## 9. Validation and Testing

### 9.1 End-to-End Test Procedure

```bash
#!/bin/bash
# E2E Validation Test

TENANT_ID=$1
GATEWAY_THING_NAME="smdh-gateway-${TENANT_ID}-site-001"
AWS_REGION=${AWS_REGION:-eu-west-2}

echo "🧪 Running E2E validation for ${TENANT_ID}..."

# Test 1: MQTT Connection
echo ""
echo "Test 1: MQTT Connection"
echo "  - Gateway should appear as 'Connected' in AWS IoT Core"
aws iot describe-thing \
  --thing-name $GATEWAY_THING_NAME \
  --region $AWS_REGION

# Test 2: Message Ingestion
echo ""
echo "Test 2: Publishing test message..."
# This requires publishing from gateway or via test client

# Test 3: Snowflake Data Verification
echo ""
echo "Test 3: Verifying data in Snowflake..."
snowsql -a $SNOWFLAKE_ACCOUNT -u $SNOWFLAKE_USER \
  -q "SELECT COUNT(*) FROM smdh_tenant_${TENANT_ID}.raw.sensor_readings;"

# Test 4: Topic ACLs
echo ""
echo "Test 4: Verifying topic ACLs (should fail for cross-tenant)..."
# Cross-tenant publish should fail

echo ""
echo "✅ Validation complete!"
```

### 9.2 Data Quality Checks

```sql
-- Monitor data ingestion quality
SET TENANT_ID = 'company_a';

-- Check ingestion rate
SELECT
  DATE_TRUNC('hour', ingestion_timestamp) as hour,
  COUNT(*) as record_count,
  COUNT(DISTINCT sensor_id) as unique_sensors
FROM smdh_tenant_&{TENANT_ID}.raw.sensor_readings
GROUP BY DATE_TRUNC('hour', ingestion_timestamp)
ORDER BY hour DESC
LIMIT 24;

-- Check data quality
SELECT
  sensor_id,
  COUNT(*) as total_readings,
  COUNT(CASE WHEN payload IS NULL THEN 1 END) as null_payloads,
  COUNT(CASE WHEN DATEDIFF('minute', timestamp, ingestion_timestamp) > 60 THEN 1 END) as late_readings
FROM smdh_tenant_&{TENANT_ID}.raw.sensor_readings
GROUP BY sensor_id;
```

---

## 10. Rollback Procedures

### 10.1 Complete Tenant Offboarding

```bash
#!/bin/bash
# Tenant Offboarding Script

TENANT_ID=$1
read -p "Are you sure you want to offboard $TENANT_ID? (yes/no): " confirmation

if [ "$confirmation" != "yes" ]; then
  echo "Offboarding cancelled"
  exit 1
fi

AWS_REGION=${AWS_REGION:-eu-west-2}

echo "🗑️  Starting tenant offboarding for ${TENANT_ID}..."

# Step 1: Backup Snowflake database
echo "Step 1: Creating backup..."
snowsql -a $SNOWFLAKE_ACCOUNT -u $SNOWFLAKE_USER \
  -q "CREATE DATABASE smdh_tenant_${TENANT_ID}_backup CLONE smdh_tenant_${TENANT_ID};"

# Step 2: Export data (optional)
echo "Step 2: Exporting data..."
snowsql -a $SNOWFLAKE_ACCOUNT -u $SNOWFLAKE_USER \
  -q "COPY (SELECT * FROM smdh_tenant_${TENANT_ID}.raw.sensor_readings LIMIT 10000000)
      TO '@~/offboard_${TENANT_ID}/'
      FILE_FORMAT = (TYPE = PARQUET) PARALLEL = 10;"

# Step 3: Suspend Snowflake tasks
echo "Step 3: Suspending tasks..."
snowsql -a $SNOWFLAKE_ACCOUNT -u $SNOWFLAKE_USER \
  -q "ALTER TASK smdh_tenant_${TENANT_ID}.raw.process_sensor_data SUSPEND;"

# Step 4: Disable IoT certificates
echo "Step 4: Disabling IoT certificates..."
for CERT_ID in $(aws iot list-certificates --region $AWS_REGION --query 'certificates[].certificateId' --output text); do
  aws iot update-certificate \
    --certificate-id $CERT_ID \
    --new-status INACTIVE \
    --region $AWS_REGION 2>/dev/null || true
done

# Step 5: Delete IoT rules
echo "Step 5: Deleting IoT rules..."
aws iot delete-topic-rule \
  --rule-name "smdh_route_${TENANT_ID}" \
  --region $AWS_REGION

# Step 6: Delete IoT policy
echo "Step 6: Deleting IoT policy..."
aws iot delete-policy \
  --policy-name "smdh-policy-${TENANT_ID}" \
  --region $AWS_REGION

# Step 7: Delete Snowflake database (after backup confirmation)
echo "Step 7: Cleaning up Snowflake..."
snowsql -a $SNOWFLAKE_ACCOUNT -u $SNOWFLAKE_USER \
  -q "DROP DATABASE smdh_tenant_${TENANT_ID};"

# Step 8: Update infrastructure metadata
snowsql -a $SNOWFLAKE_ACCOUNT -u $SNOWFLAKE_USER \
  -q "UPDATE smdh_infrastructure.tenant_configs.tenants SET status='offboarded', offboard_date=CURRENT_TIMESTAMP() WHERE tenant_id='${TENANT_ID}';"

echo "✅ Tenant offboarding complete"
echo "   Backup available: smdh_tenant_${TENANT_ID}_backup"
echo "   Exported data: ~/offboard_${TENANT_ID}/"
```

### 10.2 Disaster Recovery

```sql
-- Restore from backup
CREATE DATABASE smdh_tenant_company_a CLONE smdh_tenant_company_a_backup;

-- Restore specific table from Time Travel
CREATE TABLE smdh_tenant_company_a.raw.sensor_readings CLONE smdh_tenant_company_a.raw.sensor_readings AT (TIMESTAMP => '2024-01-15'::timestamp_ntz);

-- Recreate streams and tasks
CREATE STREAM smdh_tenant_company_a.raw.sensor_readings_stream
  ON TABLE smdh_tenant_company_a.raw.sensor_readings
  APPEND_ONLY = TRUE;
```

---

## 11. Cost Estimates

### 11.1 AWS Pricing Breakdown (30 Tenants, 26M messages/day)

| Service | Usage | Monthly Cost | Annual Cost | Per-Tenant/Month |
|---------|-------|--------------|-------------|-----------------|
| **IoT Core** | 26M messages/day | ~$130 | ~$1,560 | ~$4.33 |
| **Kinesis** | On-demand, 1 shard | ~$18 | ~$216 | ~$0.60 |
| **Secrets Manager** | 1 secret | ~$0.40 | ~$4.80 | ~$0.01 |
| **CloudWatch** | 200GB logs/month | ~$100 | ~$1,200 | ~$3.33 |
| **IAM Roles** | Minimal | ~$5 | ~$60 | ~$0.17 |
| **AWS Total** | | **~$253/mo** | **~$3,040/year** | **~$8.44** |

### 11.2 Snowflake Cost Estimation

```
Snowflake pricing varies by edition and region.
Example for 30 tenants (estimate):

- Standard Edition: $4/credit
- Compute credits (ETL): 3,000 credits/month = $12,000
- Storage: 1TB average = $40
- Openflow connector: ~$0.50/million messages = ~$130

Estimated Snowflake: $12,170/month or $146,040/year
Estimated per-tenant: $406/month or $4,868/year
```

### 11.3 Cost Optimization Tips

1. **Use Kinesis on-demand** - Scales to zero when no data
2. **Auto-suspend Snowflake warehouses** - Save 70% on idle time
3. **Set CloudWatch log retention** - Avoid excessive storage charges
4. **Monitor certificate lifecycle** - Prevent duplicate certificate creation
5. **Use Snowflake Time Travel wisely** - Balance data protection vs. storage costs
6. **Consolidate logs** - Aggregate tenant logs to reduce CloudWatch ingestion

---

## Appendix A: Command Reference

### AWS IoT Core Commands

```bash
# List things
aws iot list-things

# Describe thing
aws iot describe-thing --thing-name <thing-name>

# List certificates
aws iot list-certificates

# Describe certificate
aws iot describe-certificate --certificate-id <cert-id>

# Update certificate status
aws iot update-certificate --certificate-id <cert-id> --new-status INACTIVE

# List policies
aws iot list-policies

# Get policy
aws iot get-policy --policy-name <policy-name>

# List topic rules
aws iot list-topic-rules
```

### Snowflake Commands

```sql
-- List databases
SHOW DATABASES;

-- List tables in database
SHOW TABLES IN DATABASE <database_name>;

-- Monitor task execution
SELECT * FROM INFORMATION_SCHEMA.TASK_HISTORY LIMIT 100;

-- Monitor data ingestion
SELECT * FROM INFORMATION_SCHEMA.TABLE_STORAGE_METRICS;

-- Check warehouse status
SHOW WAREHOUSES;

-- Monitor query performance
SELECT * FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY LIMIT 100;
```

---

## Appendix B: Troubleshooting

### Snowflake Variable Reference Issues

**Symptoms:** "Variable is not defined" errors in SnowSQL

**Root Cause:** Confusion between SnowSQL and SQL session variables

**Solutions:**
1. **SnowSQL variables** (`&variable`): Pass via `-D` flag, e.g., `-D tenant_id=test_tenant`
2. **SQL session variables** (`$variable`): Create with `SET`, reference with `$`
3. Always use `-o variable_substitution=true` when using `&` variables
4. Example of correct usage:
   ```sql
   -- Create SQL session variable
   SET database_name = 'smdh_tenant_' || '&tenant_id';
   -- Use SQL session variable with $
   USE DATABASE IDENTIFIER($database_name);
   ```

### Snowflake CREATE DATABASE/ROLE Comment Syntax Errors

**Symptoms:** "Syntax error unexpected '('" when using CONCAT in COMMENT clause

**Root Cause:** COMMENT clauses don't support functions, only literals or simple concatenation

**Solutions:**
1. **Wrong:** `COMMENT = CONCAT('text', variable, 'text')`
2. **Correct:** `COMMENT = 'text ' || variable || ' text'`
3. **Also Correct:** `COMMENT = 'Static text with &snowsql_variable substitution'`

### Issue: Gateway Cannot Connect to IoT Core

**Symptoms:** Connection timeout, "certificate verify failed"

**Solutions:**
1. Verify certificate files are correct (check certificate dates)
2. Ensure TLS port 8883 is not blocked by firewall
3. Verify IoT endpoint address is correct
4. Check certificate permissions (600 for private key)
5. Validate certificate against root CA

### Issue: No Data Appearing in Snowflake

**Symptoms:** Records published to MQTT but not in sensor_readings table

**Solutions:**
1. Check IoT Rule is enabled
2. Verify Kinesis stream has data
3. Check Snowflake task is running
4. Look at task execution history for errors
5. Verify Openflow connector configuration

### Issue: High Latency in Data Pipeline

**Symptoms:** Data takes >5 minutes to appear in Snowflake

**Solutions:**
1. Check Kinesis iterator age in CloudWatch
2. Verify Snowflake warehouse is running
3. Look for slow task execution
4. Check for database locks
5. Monitor network latency to AWS

---

## Document History

| Date | Version | Changes | Author |
|------|---------|---------|--------|
| 2025-11-22 | 2.1 | Updated Snowflake configuration with validated scripts, added variable reference documentation, included troubleshooting for common SQL issues | Platform Team |
| 2025-11-21 | 2.0 | Added Terraform deployment section with actual deployment results | Platform Team |
| 2024-11-21 | 1.0 | Initial release with manual CLI procedures | Platform Team |
