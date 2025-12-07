Smart Manufacturing Data Hub (SMDH) - Infrastructure Implementation Guide

Overview

This document provides detailed step-by-step implementation instructions for deploying and configuring the SMDH platform. It complements the [SMDH AWS Design Document](../docs/detailed-design/SMDH%AWS%design.md) which explains the architectural concepts.

Quick Start: For immediate deployment, use the Terraform infrastructure in [terraform/](terraform/). See [Terraform Deployment](terraform-deployment-recommended) below.

For high-level architecture and design decisions, refer to the AWS Design Document. This guide focuses on:

- Terraform-based Infrastructure as Code deployment (Recommended)
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

Table of Contents

. [Terraform Deployment (Recommended)](terraform-deployment-recommended)
. [Pre-requisites](-pre-requisites)
. [AWS Account Setup](-aws-account-setup)
. [Snowflake Configuration](-snowflake-configuration)
. [Tenant Onboarding Procedures](-tenant-onboarding-procedures)
. [Table Definitions](-table-definitions)
. [Gateway Device Setup](-gateway-device-setup)
. [Monitoring and Alerting](-monitoring-and-alerting)
. [Automation Scripts](-automation-scripts)
. [Validation and Testing](-validation-and-testing)
. [Rollback Procedures](-rollback-procedures)
. [Cost Estimates](-cost-estimates)

---

Terraform Deployment (Recommended)

Overview

The SMDH platform is deployed using Terraform Infrastructure as Code. This approach provides:

- Reproducible deployments across environments
- Version-controlled infrastructure with git history
- Automated resource provisioning ( resources in ~ minutes)
- Comprehensive tagging for cost allocation and compliance
- State management with S backend and DynamoDB locking

Deployment Summary

Successfully Deployed: December 2025
Environment: Development (eu-west-2)
Resources Created: AWS resources per tenant
Tenant: manufacturing_demo (5 sites)

Quick Start

The Terraform configuration uses **three separate variable files** for better organisation:

| File | Purpose | When to Modify |
|------|---------|----------------|
| `01_tags.tfvars` | Resource tags (owner, cost centre) | Rarely |
| `02_core.tfvars` | AWS region, retention, Snowflake integration | Rarely |
| `03_tenants.tfvars` | Tenant definitions | **Each tenant onboarding** |

```bash
# Navigate to Terraform directory
cd infrastructure/terraform

# Review the comprehensive README
cat README.md

# Initialize Terraform (one-time setup)
terraform init

# Review the deployment plan (all three tfvars files required)
terraform plan \
  -var-file=environments/dev/01_tags.tfvars \
  -var-file=environments/dev/02_core.tfvars \
  -var-file=environments/dev/03_tenants.tfvars

# Deploy infrastructure
terraform apply \
  -var-file=environments/dev/01_tags.tfvars \
  -var-file=environments/dev/02_core.tfvars \
  -var-file=environments/dev/03_tenants.tfvars
```

What Gets Deployed

The Terraform configuration automatically creates:

Core Infrastructure

- IoT Core: Thing Types (LoRaWAN, DevTank), logging, IAM roles
- Kinesis: On-demand data stream for sensor data
- IAM: Cross-account roles for Snowflake integration
- Secrets Manager: Secure credential storage for Snowflake
- CloudWatch: Log groups, dashboards, alarms, SNS topics

Per-Tenant Resources

- IoT Things: Gateways and sensors with proper attributes
- X. Certificates: Automatically generated with private keys
- IoT Policies: Tenant-isolated topic access control
- IoT Rules: Route sensor data to Kinesis with tenant partition keys
- SNS Topics: Tenant-specific alerting
- CloudWatch Alarms: Connection failures, message failures

Deployed Configuration

IoT Endpoint

```
IoT Endpoint: afbiixmeupm-ats.iot.eu-west-.amazonaws.com
MQTT Address: mqtt://afbiixmeupm-ats.iot.eu-west-.amazonaws.com:
```

Kinesis Streams (Per-Tenant Architecture)

```
Architecture: One dedicated stream per tenant
Stream Pattern: smdh-{tenant_id}-stream
Example: smdh-test_tenant-stream
Mode: ON_DEMAND (auto-scaling per tenant)

Note: Per-tenant streams are REQUIRED because Snowflake Openflow
cannot filter records from a shared stream.
```

Monitoring

```
Dashboard: https://console.aws.amazon.com/cloudwatch/home?region=eu-west-dashboards:name=smdh-platform-dev
Log Group: /aws/iot/smdh (-day retention)
SNS Topic: smdh-platform-alarms-dev
```

Demo Tenant Configuration

```
Tenant ID: manufacturing_demo
Tenant Name: Demo Manufacturing Corp
Sites: 5
Kinesis Stream: smdh-manufacturing_demo-stream
IoT Policy: smdh-policy-manufacturing_demo
IoT Rule: smdh_route_manufacturing_demo
Certificates: X.509 certificates per site with private keys
```

Terraform Outputs

View all deployment outputs:

```bash
 All outputs
terraform output

 Specific outputs
terraform output iot_endpoint
terraform output kinesis_stream_name
terraform output cloudwatch_dashboard_url

 Sensitive outputs (certificates, IAM roles)
terraform output -json tenant_certificate_arns
terraform output snowflake_iam_role_arn
```

Post-Deployment Steps

After Terraform deployment completes:

. Confirm SNS Subscriptions

- Check email for subscription confirmations
- Confirm both platform and tenant alert topics

. Download Device Certificates

```bash
terraform output -json tenant_configurations | jq .
```

- Note: Private keys are in Terraform state, extract carefully

. Configure Snowflake Integration

- Update `snowflake_account_id` in `02_core.tfvars`
- Update `snowflake_external_id` in `02_core.tfvars` (generate UUID)
- Re-run terraform apply with all three tfvars files to update IAM role trust policy

. Test MQTT Connectivity

- Use certificates to test gateway connections
- See [Gateway Device Setup](-gateway-device-setup) below

Known Issues

AWS Provider Default Tags Bug
During deployment, you may see errors about "Provider produced inconsistent final plan" related to tags on IoT Policy resources. This is a known AWS provider issue and does not affect functionality. All resources are created successfully.

Workaround: After the initial error, run `terraform refresh` and `terraform apply` again. The state will sync correctly.

IoT Thing Type Searchable Attributes
AWS IoT supports a maximum of searchable attributes per Thing Type. The current configuration uses:

- `tenant_id`
- `site_id`
- `device_type`

IoT Rule SQL Syntax
IoT Rules SQL does not support checking built-in functions in WHERE clauses. For example:

- Invalid: `WHERE timestamp() IS NOT NULL`
- Valid: `SELECT , timestamp() as iot_timestamp FROM 'topic'`

The `timestamp()` function generates a timestamp at message processing time and doesn't need validation. Remove WHERE clause checks on function results.

Terraform Module Structure

```
terraform/
 main.tf                     Root module orchestration
 providers.tf               AWS provider with default tags
 variables.tf               Input variables
 outputs.tf                Output values
 tags.tf                   Centralized tagging strategy
 modules/
    iot-core/            IoT Thing Types, logging
    kinesis/             Kinesis stream, alarms
    iam/                 Snowflake cross-account roles
    secrets-manager/     Credential storage
    cloudwatch/          Monitoring, dashboards, alarms
    tenant/              Per-tenant resources
 environments/
     dev/                Development environment
     prod/               Production environment
```

For comprehensive documentation, see [terraform/README.md](terraform/README.md) and [terraform/TAGGING_STRATEGY.md](terraform/TAGGING_STRATEGY.md).

Next Steps

- Manual Operations: Continue to [AWS Account Setup](-aws-account-setup) for manual CLI commands (reference only)
- Snowflake Setup: Proceed to [Snowflake Configuration](-snowflake-configuration)
- Device Setup: Configure gateways with generated certificates in [Gateway Device Setup](-gateway-device-setup)
- Testing: Validate deployment with [Validation and Testing](-validation-and-testing)

---

. Pre-requisites

Required Permissions

AWS:

- IoT Core administrator
- Kinesis administrator
- Secrets Manager administrator
- CloudWatch administrator
- IAM administrator

Snowflake:

- Account admin role
- Ability to create databases and roles

Required Tools

```bash
 AWS CLI (v.x minimum)
aws --version

 Snowflake CLI
snowsql --version

 jq (JSON processor)
jq --version

 openssl (certificate generation)
openssl version
```

Environment Setup

```bash
 Set these environment variables
export AWS_REGION="eu-west-"
export AWS_ACCOUNT_ID="YOUR_ACCOUNT_ID"
export SNOWFLAKE_ACCOUNT="YOUR_ACCOUNT"
export SNOWFLAKE_USER="admin_user"
```

---

. AWS Account Setup

> Note: This section documents manual AWS CLI commands for reference. For production deployments, use the [Terraform infrastructure](terraform-deployment-recommended) which automates all these steps.

The manual commands below are useful for:

- Understanding the underlying AWS resources
- Troubleshooting and debugging
- One-off operations outside Terraform management
- Learning the SMDH architecture

. Enable AWS IoT Core

```bash
 Verify IoT Core is available in region
aws iot describe-endpoint \
  --endpoint-type iot:Data-ATS \
  --region $AWS_REGION

 Save endpoint for later
IOT_ENDPOINT=$(aws iot describe-endpoint \
  --endpoint-type iot:Data-ATS \
  --region $AWS_REGION \
  --query 'endpointAddress' \
  --output text)

echo "IoT Endpoint: $IOT_ENDPOINT"
```

. Kinesis Streams (Per-Tenant - Created by Terraform)

```bash
 NOTE: Kinesis streams are now created per-tenant by Terraform
 Each tenant gets their own stream: smdh-{tenant_id}-stream
 This is REQUIRED because Snowflake Openflow cannot filter from a shared stream

 Manual creation example (for reference only):
aws kinesis create-stream \
  --stream-name smdh-${TENANT_ID}-stream \
  --stream-mode-details StreamMode=ON_DEMAND \
  --region $AWS_REGION

 Wait for stream to be active
aws kinesis wait stream-exists \
  --stream-name smdh-${TENANT_ID}-stream \
  --region $AWS_REGION

echo " Kinesis stream created for tenant: smdh-${TENANT_ID}-stream"
```

. Create Secrets Manager Secret for Snowflake

```bash
 Create secret for Snowflake private key (placeholder)
 This will be populated during tenant onboarding

aws secretsmanager create-secret \
  --name smdh/snowflake/private-key \
  --description "Snowflake private key for Openflow connector" \
  --secret-string '{"private_key": "placeholder"}' \
  --region $AWS_REGION

echo " Secrets Manager secret created"
```

. Create CloudWatch Log Group

```bash
 Create log group for IoT logs
aws logs create-log-group \
  --log-group-name /aws/iot/smdh \
  --region $AWS_REGION

 Set retention policy ( days)
aws logs put-retention-policy \
  --log-group-name /aws/iot/smdh \
  --retention-in-days  \
  --region $AWS_REGION

echo " CloudWatch log group created"
```

. Create IAM Role for Snowflake Integration

```bash
 Create trust policy for Snowflake
cat > /tmp/snowflake-trust-policy.json << 'EOF'
{
  "Version": "--",
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

 Create role
aws iam create-role \
  --role-name smdh-snowflake-kinesis-role \
  --assume-role-policy-document file:///tmp/snowflake-trust-policy.json \
  --region $AWS_REGION

 Create policy for Kinesis access
cat > /tmp/snowflake-kinesis-policy.json << 'EOF'
{
  "Version": "--",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "kinesis:GetRecords",
        "kinesis:GetShardIterator",
        "kinesis:DescribeStream",
        "kinesis:ListStreams"
      ],
      "Resource": "arn:aws:kinesis:eu-west-::stream/smdh-"
    }
  ]
}
EOF

 Attach policy to role
aws iam put-role-policy \
  --role-name smdh-snowflake-kinesis-role \
  --policy-name smdh-snowflake-kinesis-policy \
  --policy-document file:///tmp/snowflake-kinesis-policy.json

echo " IAM role for Snowflake created"
```

---

. Snowflake Configuration

. Initialize Snowflake Account

> Note: All Snowflake scripts have been validated and are available in `infrastructure/snowflake/`

Quick Start - Complete Snowflake Setup

```bash
 Navigate to Snowflake scripts directory
cd infrastructure/snowflake

 Set your Snowflake password
export SNOWSQL_PWD="your_password"

 Run the complete setup with validation
./validate_setup.sh test_tenant "Test Tenant" eu-west-2

 Check the logs if needed
ls -la /tmp/smdh_.log
```

What Gets Created

Running the validation script creates:

. Infrastructure Database (`SMDH_INFRASTRUCTURE`)

- Tenant registry and configuration
- Monitoring and audit schemas
- Platform-wide roles and permissions

. Tenant Database (`SMDH_TENANT_<tenant_id>`)

- Four data schemas: raw, normalized, aggregated, analytics
- File formats for JSON, CSV, and Parquet
- Internal stages for file uploads and error handling
- Tenant-specific roles with proper permissions

. Shared Resources

- Multiple warehouses with auto-suspend
- Base roles for inheritance
- Monitoring views and procedures

Core Infrastructure Setup (\_infrastructure_setup.sql)

```sql
-- Connect to Snowflake as account admin
-- snowsql -a <account> -u <user> -r ACCOUNTADMIN

USE ROLE ACCOUNTADMIN;

-- Create organizational database
CREATE DATABASE IF NOT EXISTS smdh_infrastructure
    DATA_RETENTION_TIME_IN_DAYS =
    COMMENT = 'SMDH platform infrastructure and shared resources. Contains tenant metadata, monitoring data, and audit logs.';

USE DATABASE smdh_infrastructure;

-- Create shared schemas
CREATE SCHEMA IF NOT EXISTS tenant_configs
    DATA_RETENTION_TIME_IN_DAYS =
    COMMENT = 'Tenant metadata, configuration, and registry. Central source of truth for all SMDH tenants.';

CREATE SCHEMA IF NOT EXISTS monitoring
    DATA_RETENTION_TIME_IN_DAYS =
    COMMENT = 'Platform-wide monitoring, metrics, and health checks. Used for operational dashboards.';

CREATE SCHEMA IF NOT EXISTS audit
    DATA_RETENTION_TIME_IN_DAYS =
    COMMENT = 'Audit logs, access tracking, and compliance records. Retained for  days for security compliance.';

-- Create tenant registry table
USE SCHEMA tenant_configs;

CREATE TABLE IF NOT EXISTS tenants (
    tenant_id VARCHAR() PRIMARY KEY,
    tenant_name VARCHAR() NOT NULL,
    status VARCHAR() DEFAULT 'provisioning',
    created_date TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    updated_date TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    aws_region VARCHAR(),
    num_sites NUMBER(),
    warehouse_size VARCHAR() DEFAULT 'XSMALL',
    data_retention_days NUMBER() DEFAULT ,
    billing_contact VARCHAR(),
    technical_contact VARCHAR(),
    metadata VARIANT,
    CONSTRAINT valid_status CHECK (status IN ('provisioning', 'active', 'suspended', 'offboarded'))
);

-- Create site registry
CREATE TABLE IF NOT EXISTS sites (
    site_id VARCHAR() PRIMARY KEY,
    tenant_id VARCHAR() NOT NULL,
    site_name VARCHAR(),
    location VARCHAR(),
    gateway_count NUMBER() DEFAULT ,
    sensor_count NUMBER() DEFAULT ,
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

. Create Shared Warehouse

```sql
-- Create shared warehouse for infrastructure operations
CREATE WAREHOUSE IF NOT EXISTS smdh_infrastructure_wh
  WAREHOUSE_SIZE = 'xsmall'
  AUTO_SUSPEND =
  AUTO_RESUME = true
  INITIALLY_SUSPENDED = false;

-- Create warehouses for tenant ETL
CREATE WAREHOUSE IF NOT EXISTS smdh_etl_wh
  WAREHOUSE_SIZE = 'small'
  AUTO_SUSPEND =
  AUTO_RESUME = true
  INITIALLY_SUSPENDED = false;

CREATE WAREHOUSE IF NOT EXISTS smdh_analytics_wh
  WAREHOUSE_SIZE = 'medium'
  AUTO_SUSPEND =
  AUTO_RESUME = true
  INITIALLY_SUSPENDED = false;
```

. Snowflake Directory Structure

The Snowflake implementation is organised as follows:

```
infrastructure/snowflake/
├── scripts/
│   ├── validate_setup.sh              # Master validation script
│   ├── onboard_tenant.sh              # Tenant onboarding automation
│   ├── setup_openflow.sh              # Openflow setup automation
│   └── snowflake.sh                   # General Snowflake utilities
├── sql/
│   ├── core/
│   │   ├── 00_drop_all.sql            # Clean slate (use with caution)
│   │   ├── 01_infrastructure_setup.sql # Infrastructure database
│   │   ├── 02_shared_resources.sql    # Warehouses, roles
│   │   └── 03_openflow_connector.sql  # Kinesis connector config
│   ├── tenant/
│   │   ├── 10_create_tenant_database.sql
│   │   ├── 11_create_schemas.sql
│   │   ├── 12_create_tables.sql
│   │   ├── 13_create_streams.sql
│   │   ├── 14_create_routing_task.sql # Routes data from landing table
│   │   ├── 14_create_tasks.sql        # Processing tasks
│   │   ├── 15_create_dynamic_tables.sql
│   │   ├── 16_create_roles.sql
│   │   └── 17_create_monitoring.sql
│   └── utility/
│       ├── check_current_state.sql
│       ├── check_role.sql
│       └── validate_tenant.sql
└── README.md
```

. Snowflake Validation Script

The `validate_setup.sh` script automates the entire Snowflake setup and verification:

```bash
!/bin/bash
 Usage: ./validate_setup.sh [tenant_id] [tenant_name] [aws_region] [num_sites]
 Example: ./validate_setup.sh test_tenant "Test Tenant" eu-west-

 Key features:
 - Validates all required parameters
 - Sets up SnowSQL with proper variable substitution (-o variable_substitution=true)
 - Runs all scripts in the correct order
 - Handles both infrastructure and tenant setup
 - Provides detailed logging to /tmp/smdh_.log
 - Verifies successful creation of all resources

 The script correctly handles Snowflake's dual variable system:
 - Passes SnowSQL variables via -D flags
 - Uses proper SQL session variables with SET statements
 - References variables correctly (& for SnowSQL, $ for SQL session)
```

Successfully Deployed Configuration

As of November , , the following Snowflake resources have been successfully created and validated:

Infrastructure Database:

- Database: `SMDH_INFRASTRUCTURE`
- Schemas: `TENANT_CONFIGS`, `MONITORING`, `AUDIT`
- Tables: `tenants`, `sites`, `devices`, `gateway_registry`

Test Tenant Configuration:

- Database: `SMDH_TENANT_TEST_TENANT`
- Schemas: `RAW`, `NORMALIZED`, `AGGREGATED`, `ANALYTICS`
- Roles: `smdh_tenant_test_tenant_admin`, `smdh_tenant_test_tenant_user`, `smdh_tenant_test_tenant_readonly`
- File Formats: `ff_json`, `ff_csv`, `ff_parquet`
- Stages: `stage_uploads`, `stage_errors`

. Implementation Status Summary

Fully Implemented and Working:

- Infrastructure database setup (`SMDH_INFRASTRUCTURE`)
- Tenant database creation (`SMDH_TENANT_<tenant_id>`)
- All schemas (raw, normalized, aggregated, analytics)
- Role-based access control (admin, user, readonly roles)
- File formats and internal stages
- Tenant metadata tables
- Validation and verification scripts
- Proper variable handling in all SQL scripts

Partially Implemented:

- Dynamic tables (DDL created, not yet populated with real data)
- Tasks and streams (created but not processing real sensor data yet)
- Monitoring views (structure in place, awaiting real data)

✅ Recently Implemented (December 2024):

- Openflow Connector infrastructure for native Kinesis integration
- Per-tenant Kinesis stream architecture
- Network rules and External Access Integration for AWS connectivity
- Openflow connector tracking and monitoring views
- Comprehensive tenant onboarding documentation

⏳ Pending UI Configuration (Manual Steps Required):

- Create Openflow Deployment in Snowsight UI
- Create Openflow Runtime with `OPENFLOW_RUNTIME_ROLE_KINESIS`
- Configure Kinesis Connector with stream-to-table mappings
- End-to-end testing with real sensor data

⏳ Future Enhancements:

- Streamlit portal for tenant analytics
- Production monitoring and alerting dashboards

. Openflow Connector for Kinesis Integration

**Architecture Decision**: Use Snowflake Openflow Connector for native Kinesis Data Stream ingestion.

**Per-Tenant Stream Architecture**: Each tenant gets a dedicated Kinesis stream that routes directly to their Snowflake database:
```
AWS IoT Core → IoT Rule (per tenant) → Kinesis Stream (per tenant) → Openflow → Tenant Database
```

Benefits of per-tenant streams:
- Complete data isolation between tenants
- Independent scaling per tenant workload
- Simplified stream-to-table routing
- Easier debugging and monitoring

**Openflow SQL Setup** (`infrastructure/snowflake/sql/core/03_openflow_connector.sql`):

```sql
-- Creates the following resources:
-- 1. OPENFLOW_ADMIN role with deployment/runtime privileges
-- 2. OPENFLOW_RUNTIME_ROLE_KINESIS for connector execution
-- 3. OPENFLOW database with image repository
-- 4. Network rules for AWS Kinesis/DynamoDB/STS access
-- 5. External Access Integration (OPENFLOW_AWS_EAI)
-- 6. Connector tracking table and monitoring views
-- 7. Stored procedure: sp_grant_openflow_tenant_access()

-- Run the setup script:
USE ROLE ACCOUNTADMIN;
USE WAREHOUSE SMDH_WH;

-- Or use the automated script:
-- ./infrastructure/snowflake/scripts/setup_openflow.sh
```

**Post-SQL UI Configuration** (required in Snowsight):

1. Navigate to **Ingestion** > **Openflow**
2. Create Deployment: `smdh-openflow-deployment`
3. Create Runtime: `smdh-kinesis-runtime`
   - Role: `OPENFLOW_RUNTIME_ROLE_KINESIS`
   - Warehouse: `SMDH_WH`
   - External Access: `OPENFLOW_AWS_EAI`
4. Add Kinesis Connector with stream-to-table mapping

**CRITICAL Configuration Requirements:**

| Setting | Correct Value | Wrong Value (will fail) |
|---------|---------------|-------------------------|
| AWS Authentication | IAM Access Keys | Role Assumption |
| Consumer Type | `Shared Throughput` | Enhanced Fan-Out |
| Snowflake Auth | `SNOWFLAKE_SESSION_TOKEN` | KEY_PAIR |

**Stream-to-Table Mapping Example**:

OpenFlow automatically creates a landing table named after the Kinesis stream (uppercase, hyphens preserved):
```
smdh-manufacturing_demo-stream → "SMDH-MANUFACTURING_DEMO-STREAM" table
```

**Detailed Instructions**: See `infrastructure/deployment/Tenant_Onboarding_Guide.md`

---

. Tenant Onboarding Procedures

. Tenant Onboarding Checklist and Timeline

| Phase           | Component       | Steps                                         | Est. Time |
| --------------- | --------------- | --------------------------------------------- | --------- |
| Planning        | Business Setup  | Gather requirements, SLA definition           | min       |
| Identity        | AWS & Snowflake | Create accounts, assign roles                 | min       |
| AWS Setup       | IoT Core        | Thing registry, certificates, policies, rules | min       |
| Snowflake Setup | Database        | Database, schemas, tables, streams, tasks     | min       |
| Application     | Portal          | Streamlit config, UI customization            | min       |
| Validation      | Testing         | EE test, monitoring verification              | min       |
| Total           |                 |                                               | ~. hours  |

. Phase : Gathering Requirements

```bash
!/bin/bash
 Tenant Requirements Gathering Script

read -p "Tenant ID (lowercase, alphanumeric): " TENANT_ID
read -p "Tenant Name: " TENANT_NAME
read -p "Number of sites: " NUM_SITES
read -p "Number of sensors per site: " SENSORS_PER_SITE
read -p "Data retention (days): " RETENTION_DAYS
read -p "Primary contact email: " CONTACT_EMAIL

 Validation
if ! [[ $TENANT_ID =~ ^[a-z-_]+$ ]]; then
  echo "Error: Tenant ID must be lowercase alphanumeric"
  exit
fi

 Save to configuration file
cat > tenant_config_${TENANT_ID}.env << EOF
TENANT_ID=$TENANT_ID
TENANT_NAME=$TENANT_NAME
NUM_SITES=$NUM_SITES
SENSORS_PER_SITE=$SENSORS_PER_SITE
RETENTION_DAYS=$RETENTION_DAYS
CONTACT_EMAIL=$CONTACT_EMAIL
AWS_REGION=eu-west-
CREATED_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF

echo " Configuration saved to tenant_config_${TENANT_ID}.env"
```

. Phase : AWS IoT Setup

Step .: Create IoT Thing Type

```bash
!/bin/bash
source tenant_config_${TENANT_ID}.env

aws iot create-thing-type \
  --thing-type-name "LoRaWANGateway" \
  --thing-type-properties searchableAttributes=tenant_id,site_id,location \
  --region $AWS_REGION \
  --output json > thing-type-response.json

echo " IoT Thing Type created"
```

Step .: Create IoT Thing Registry Entries

```bash
!/bin/bash
source tenant_config_${TENANT_ID}.env

 Create a thing for each site/gateway combination
for ((site=; site<=$NUM_SITES; site++)); do
  SITE_ID="site_$(printf '%d' $site)"
  THING_NAME="smdh-gateway-${TENANT_ID}-${SITE_ID}-gw_"

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

  echo " Created Thing: $THING_NAME"
done
```

Step .: Generate X. Certificates

```bash
!/bin/bash
source tenant_config_${TENANT_ID}.env

 Create certificates directory
mkdir -p certificates/${TENANT_ID}
cd certificates/${TENANT_ID}

for ((site=; site<=$NUM_SITES; site++)); do
  SITE_ID=$(printf '%d' $site)
  CERT_NAME="${TENANT_ID}-site-${SITE_ID}"

   Generate certificate
  CERT_ARN=$(aws iot create-keys-and-certificate \
    --set-as-active \
    --certificate-pem-outfile "${CERT_NAME}-cert.pem" \
    --private-key-outfile "${CERT_NAME}-private.key" \
    --region $AWS_REGION \
    --query 'certificateArn' \
    --output text)

   Download CA certificate
  curl -o AmazonRootCA.pem https://www.amazontrust.com/repository/AmazonRootCA.pem

  echo " Certificate generated: $CERT_NAME"
  echo "ARN: $CERT_ARN"
done

cd ../..
```

Step .: Create IoT Policy

```bash
!/bin/bash
source tenant_config_${TENANT_ID}.env

 Create policy document
cat > iot-policy-${TENANT_ID}.json << EOF
{
  "Version": "--",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "iot:Connect",
      "Resource": "arn:aws:iot:${AWS_REGION}:${AWS_ACCOUNT_ID}:client/smdh--${TENANT_ID}-"
    },
    {
      "Effect": "Allow",
      "Action": "iot:Publish",
      "Resource": [
        "arn:aws:iot:${AWS_REGION}:${AWS_ACCOUNT_ID}:topic/smdh/${TENANT_ID}//sensor-data",
        "arn:aws:iot:${AWS_REGION}:${AWS_ACCOUNT_ID}:topic/smdh/${TENANT_ID}//device-status"
      ]
    },
    {
      "Effect": "Allow",
      "Action": "iot:Subscribe",
      "Resource": "arn:aws:iot:${AWS_REGION}:${AWS_ACCOUNT_ID}:topicfilter/smdh/${TENANT_ID}/commands/"
    },
    {
      "Effect": "Allow",
      "Action": "iot:Receive",
      "Resource": "arn:aws:iot:${AWS_REGION}:${AWS_ACCOUNT_ID}:topic/smdh/${TENANT_ID}/commands/"
    }
  ]
}
EOF

 Create policy
aws iot create-policy \
  --policy-name "smdh-policy-${TENANT_ID}" \
  --policy-document file://iot-policy-${TENANT_ID}.json \
  --region $AWS_REGION

echo " IoT Policy created: smdh-policy-${TENANT_ID}"
```

Step .: Attach Certificates to Policy

```bash
!/bin/bash
source tenant_config_${TENANT_ID}.env

 Get all certificates
CERTS=$(aws iot list-certificates \
  --region $AWS_REGION \
  --query "certificates[?certificateStatus=='ACTIVE'].certificateArn" \
  --output text)

 Attach policy to certificates for this tenant
for CERT_ARN in $CERTS; do
   Only attach to this tenant's certificates
  if [[ $CERT_ARN == "${TENANT_ID}" ]]; then
    CERT_ID=$(echo $CERT_ARN | awk -F'/' '{print $NF}')

    aws iot attach-policy \
      --policy-name "smdh-policy-${TENANT_ID}" \
      --target $CERT_ARN \
      --region $AWS_REGION

    echo " Policy attached to certificate: $CERT_ID"
  fi
done
```

Step .: Create IoT Rules Engine Rule

```bash
!/bin/bash
source tenant_config_${TENANT_ID}.env

 Create IoT rule for tenant - routes to tenant's dedicated Kinesis stream
cat > iot-rule-${TENANT_ID}.json << 'EOF'
{
  "sql": "SELECT *, topic(2) as tenant_id, topic(3) as site_id, timestamp() as iot_timestamp, clientId() as device_id FROM 'smdh/${TENANT_ID}/+/sensor-data'",
  "actions": [
    {
      "kinesis": {
        "roleArn": "arn:aws:iam::${AWS_ACCOUNT_ID}:role/smdh-iot-kinesis-role",
        "streamName": "smdh-${TENANT_ID}-stream",
        "partitionKey": "${topic(3)}"
      }
    }
  ],
  "errorAction": {
    "republish": {
      "roleArn": "arn:aws:iam::${AWS_ACCOUNT_ID}:role/smdh-iot-kinesis-role",
      "topic": "smdh/errors/${TENANT_ID}"
    }
  }
}
EOF

 NOTE: Each tenant gets a dedicated stream (smdh-{tenant_id}-stream)
 Partition key is site_id for ordering within the tenant

aws iot create-topic-rule \
  --rule-name "smdh_route_${TENANT_ID}" \
  --topic-rule-payload file://iot-rule-${TENANT_ID}.json \
  --region $AWS_REGION

echo " IoT Rule created: smdh_route_${TENANT_ID}"
```

. Phase : Snowflake Setup

Step .: Create Tenant Database

> Important: Snowflake has two variable systems:
>
> - SnowSQL variables (`&variable`): Client-side substitution via `-D` flag
> - SQL session variables (`$variable`): Server-side variables created with `SET`

```bash
 Using the automated script
cd infrastructure/snowflake
export SNOWSQL_PWD="your_password"

 Run tenant creation for a specific tenant
snowsql -r ACCOUNTADMIN -o variable_substitution=true \
  -D tenant_id=company_a \
  -D tenant_name="Company A Ltd" \
  -D aws_region=eu-west- \
  -D num_sites= \
  -f tenant/_create_tenant_database.sql
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
    DATA_RETENTION_TIME_IN_DAYS =
    COMMENT = 'SMDH Tenant Database for &tenant_name. Isolated database per tenant for complete data separation.';

-- Use the database
USE DATABASE IDENTIFIER($database_name);

-- Create schemas
CREATE SCHEMA IF NOT EXISTS raw
    DATA_RETENTION_TIME_IN_DAYS =
    COMMENT = 'Raw ingested sensor data from IoT devices. Minimal transformation, preserves original payload structure.';

CREATE SCHEMA IF NOT EXISTS normalized
    DATA_RETENTION_TIME_IN_DAYS =
    COMMENT = 'Cleaned, normalized, and validated data. Ready for analytics and aggregation.';

CREATE SCHEMA IF NOT EXISTS aggregated
    DATA_RETENTION_TIME_IN_DAYS =
    COMMENT = 'Pre-aggregated metrics and KPIs. Used for dashboards and reporting. Longer retention for historical analysis.';

CREATE SCHEMA IF NOT EXISTS analytics
    DATA_RETENTION_TIME_IN_DAYS =
    COMMENT = 'Analytics views, ML model results, and business intelligence objects.';
```

Step .: Create Tables

```sql
-- Set tenant ID variable
SET TENANT_ID = 'company_a';

-- Raw sensor readings table
CREATE TABLE IF NOT EXISTS smdh_tenant_&{TENANT_ID}.raw.sensor_readings (
  sensor_id VARCHAR() NOT NULL,
  tenant_id VARCHAR() NOT NULL,
  timestamp TIMESTAMP_NTZ NOT NULL,
  payload VARIANT NOT NULL,
  ingestion_timestamp TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
  source_system VARCHAR(),
  mqtt_topic VARCHAR(),
  PRIMARY KEY (tenant_id, sensor_id, timestamp),
  CONSTRAINT valid_tenant CHECK (tenant_id = '&{TENANT_ID}')
)
CLUSTER BY (DATE_TRUNC('day', timestamp), sensor_id);

-- Gateway connection log table
CREATE TABLE IF NOT EXISTS smdh_tenant_&{TENANT_ID}.raw.gateway_connections (
  gateway_id VARCHAR() NOT NULL,
  tenant_id VARCHAR() NOT NULL,
  connection_time TIMESTAMP_NTZ NOT NULL,
  disconnection_time TIMESTAMP_NTZ,
  status VARCHAR(),
  error_message VARCHAR(),
  ingestion_timestamp TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
  PRIMARY KEY (tenant_id, gateway_id, connection_time)
);

-- File upload tracking table
CREATE TABLE IF NOT EXISTS smdh_tenant_&{TENANT_ID}.raw.uploaded_files (
  file_id VARCHAR() PRIMARY KEY,
  tenant_id VARCHAR() NOT NULL,
  file_name VARCHAR(),
  file_size NUMBER(),
  upload_timestamp TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
  uploaded_by VARCHAR(),
  file_path VARCHAR(),
  status VARCHAR(),
  CONSTRAINT valid_tenant CHECK (tenant_id = '&{TENANT_ID}')
);

-- API events table
CREATE TABLE IF NOT EXISTS smdh_tenant_&{TENANT_ID}.raw.api_events (
  event_id VARCHAR() PRIMARY KEY,
  tenant_id VARCHAR() NOT NULL,
  event_type VARCHAR(),
  timestamp TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
  user_id VARCHAR(),
  details VARIANT,
  CONSTRAINT valid_tenant CHECK (tenant_id = '&{TENANT_ID}')
);

-- Normalized sensor metrics table
CREATE TABLE IF NOT EXISTS smdh_tenant_&{TENANT_ID}.normalized.sensor_metrics (
  sensor_id VARCHAR() NOT NULL,
  tenant_id VARCHAR() NOT NULL,
  timestamp TIMESTAMP_NTZ NOT NULL,
  metric_name VARCHAR(),
  metric_value FLOAT,
  metric_unit VARCHAR(),
  quality_flag VARCHAR(),
  normalized_timestamp TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
  PRIMARY KEY (tenant_id, sensor_id, timestamp, metric_name),
  CONSTRAINT valid_tenant CHECK (tenant_id = '&{TENANT_ID}')
)
CLUSTER BY (DATE_TRUNC('day', timestamp), sensor_id);
```

Step .: Create Streams for CDC

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

Step .: Create Processing Tasks

```sql
SET TENANT_ID = 'company_a';
USE WAREHOUSE smdh_etl_wh;

-- Task : Process sensor readings
CREATE TASK IF NOT EXISTS smdh_tenant_&{TENANT_ID}.raw.process_sensor_data
  WAREHOUSE = smdh_etl_wh
  SCHEDULE = ' minute'
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

Step .: Create Dynamic Tables for Aggregation

```sql
SET TENANT_ID = 'company_a';

-- Hourly aggregation of sensor metrics
CREATE DYNAMIC TABLE IF NOT EXISTS smdh_tenant_&{TENANT_ID}.aggregated.sensor_hourly
  TARGET_LAG = ' minutes'
  WAREHOUSE = smdh_etl_wh
AS
SELECT
  sensor_id,
  tenant_id,
  DATE_TRUNC('hour', timestamp) as hour,
  metric_name,
  COUNT() as reading_count,
  AVG(CASE WHEN TRY_CAST(metric_value as FLOAT) IS NOT NULL THEN TRY_CAST(metric_value as FLOAT) END) as avg_value,
  MIN(CASE WHEN TRY_CAST(metric_value as FLOAT) IS NOT NULL THEN TRY_CAST(metric_value as FLOAT) END) as min_value,
  MAX(CASE WHEN TRY_CAST(metric_value as FLOAT) IS NOT NULL THEN TRY_CAST(metric_value as FLOAT) END) as max_value,
  STDDEV_POP(CASE WHEN TRY_CAST(metric_value as FLOAT) IS NOT NULL THEN TRY_CAST(metric_value as FLOAT) END) as stddev_value
FROM smdh_tenant_&{TENANT_ID}.normalized.sensor_metrics
GROUP BY sensor_id, tenant_id, DATE_TRUNC('hour', timestamp), metric_name;

-- Daily aggregation
CREATE DYNAMIC TABLE IF NOT EXISTS smdh_tenant_&{TENANT_ID}.aggregated.sensor_daily
  TARGET_LAG = ' hour'
  WAREHOUSE = smdh_etl_wh
AS
SELECT
  sensor_id,
  tenant_id,
  DATE_TRUNC('day', timestamp) as day,
  metric_name,
  COUNT() as reading_count,
  AVG(CASE WHEN TRY_CAST(metric_value as FLOAT) IS NOT NULL THEN TRY_CAST(metric_value as FLOAT) END) as avg_value,
  MIN(CASE WHEN TRY_CAST(metric_value as FLOAT) IS NOT NULL THEN TRY_CAST(metric_value as FLOAT) END) as min_value,
  MAX(CASE WHEN TRY_CAST(metric_value as FLOAT) IS NOT NULL THEN TRY_CAST(metric_value as FLOAT) END) as max_value
FROM smdh_tenant_&{TENANT_ID}.normalized.sensor_metrics
GROUP BY sensor_id, tenant_id, DATE_TRUNC('day', timestamp), metric_name;
```

Step .: Create Roles and User Access

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

Step .: Configure Data Retention

```sql
SET TENANT_ID = 'company_a';
SET RETENTION_DAYS = ;  --  years

-- Set time travel retention (for failsafe storage)
ALTER TABLE smdh_tenant_&{TENANT_ID}.raw.sensor_readings
  SET DATA_RETENTION_TIME_IN_DAYS = &{RETENTION_DAYS};

ALTER TABLE smdh_tenant_&{TENANT_ID}.normalized.sensor_metrics
  SET DATA_RETENTION_TIME_IN_DAYS = &{RETENTION_DAYS};
```

---

. Table Definitions

. Data Model Overview

```
smdh_tenant_{tenant_id}
 raw (incoming data)
    sensor_readings
    gateway_connections
    uploaded_files
    api_events
    [streams for CDC]
 normalized (cleaned data)
    sensor_metrics
    [enriched data]
 aggregated (materialized views)
    sensor_hourly
    sensor_daily
 analytics (derived tables)
     [custom metrics]
```

. Complete Table Schema Reference

See section . above for full CREATE TABLE statements.

. Indexing Strategy

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

. Gateway Device Setup

. Milesight UG LoRaWAN Gateway Setup

Physical Configuration:

. Power on gateway
. Connect to local Wi-Fi network
. Access web interface at `http://<gateway-ip>`
. Login with default credentials (check device documentation)

MQTT Configuration in Web UI:

```
MQTT Server Address: <IOT_ENDPOINT>
MQTT Server Port:
Enable TLS: YES
Protocol Version: MQTT v..

Client ID: smdh-gateway-{tenant_id}-{site_id}
Username: [Leave blank]
Password: [Leave blank]

Certificate Method: Certificate File
CA Certificate: AmazonRootCA.pem
Device Certificate: {tenant_id}-site-{site_id}-cert.pem
Device Key: {tenant_id}-site-{site_id}-private.key

MQTT Publish Topic: smdh/{tenant_id}/sensor-data
MQTT Subscribe Topic: smdh/{tenant_id}/commands/
QoS:  (At least once)
Keep Alive:  seconds
Offline Message Buffer:

Reconnect Interval:  seconds
Max Reconnect Interval:  seconds
```

Steps:
. Upload AmazonRootCA.pem
. Upload device certificate ({tenant_id}-site-{site_id}-cert.pem)
. Upload device private key ({tenant_id}-site-{site_id}-private.key)
. Set MQTT server address to {IOT_ENDPOINT}
. Verify connection shows "Connected"

. DevTank OpenSmartMonitor (OSM) Wi-Fi Setup

Network Configuration:

. Power on DevTank device
. Scan for Wi-Fi network: "DevTank-Setup-{XXXX}"
. Connect to DevTank Wi-Fi with default password
. Access configuration portal at `http://...`
. Select production Wi-Fi network and enter credentials

MQTT Configuration:

```
MQTT Broker: {IOT_ENDPOINT}
Port:
Protocol: MQTT over TLS

Client ID: smdh-osm-{tenant_id}-{site_id}
TLS Enabled: TRUE

Certificate Setup:
- CA Certificate: AmazonRootCA.pem
- Client Certificate: {tenant_id}-site-{site_id}-cert.pem
- Client Key: {tenant_id}-site-{site_id}-private.key

Publish Topics:
- Air Quality: smdh/{tenant_id}/devtank-data/air-quality
- Energy: smdh/{tenant_id}/devtank-data/energy
- Environment: smdh/{tenant_id}/devtank-data/environment

QoS:
Frequency:  minutes (configurable)
```

. Certificate Deployment to Devices

```bash
!/bin/bash
 Script to copy certificates to gateway via SCP

GATEWAY_IP=$
TENANT_ID=$
SITE_ID=$(printf '%d' $)

 Connect to gateway
ssh -i gateway_key.pem ubuntu@${GATEWAY_IP} << EOF
   Create certificate directory
  mkdir -p /etc/ssl/certs/mqtt

   Copy certificates (via SCP or manual upload)
   They should be placed in /etc/ssl/certs/mqtt/

   Verify permissions
  chmod  /etc/ssl/certs/mqtt/-private.key
  chmod  /etc/ssl/certs/mqtt/-cert.pem
  chmod  /etc/ssl/certs/mqtt/AmazonRootCA.pem

   Restart MQTT client service
  systemctl restart mqtt-client

   Verify connection
  journalctl -u mqtt-client -n
EOF

echo " Certificates deployed to ${GATEWAY_IP}"
```

---

. Monitoring and Alerting

. CloudWatch Dashboard Setup

```bash
!/bin/bash
source tenant_config_${TENANT_ID}.env

 Create CloudWatch dashboard for tenant
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
        "period": ,
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
        "period": ,
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

echo " CloudWatch dashboard created"
```

. CloudWatch Alarms

```bash
!/bin/bash
source tenant_config_${TENANT_ID}.env

 Alarm : Connection failures
aws cloudwatch put-metric-alarm \
  --alarm-name "smdh-${TENANT_ID}-connection-failures" \
  --alarm-description "Alert on connection failures" \
  --metric-name Connect.Failure \
  --namespace AWS/IoT \
  --statistic Sum \
  --period  \
  --evaluation-periods  \
  --threshold  \
  --comparison-operator GreaterThanOrEqualToThreshold \
  --alarm-actions "arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:smdh-alerts-${TENANT_ID}" \
  --region $AWS_REGION

 Alarm : Kinesis iterator age
aws cloudwatch put-metric-alarm \
  --alarm-name "smdh-${TENANT_ID}-kinesis-iterator-age" \
  --alarm-description "Alert on high iterator age" \
  --metric-name GetRecords.IteratorAgeMilliseconds \
  --namespace AWS/Kinesis \
  --statistic Maximum \
  --period  \
  --evaluation-periods  \
  --threshold  \
  --comparison-operator GreaterThanThreshold \
  --alarm-actions "arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:smdh-alerts-${TENANT_ID}" \
  --region $AWS_REGION

 Alarm : Certificate expiry
aws cloudwatch put-metric-alarm \
  --alarm-name "smdh-${TENANT_ID}-cert-expiry-warning" \
  --alarm-description "Alert when certificate expires in  days" \
  --metric-name CertificateDaysToExpiry \
  --namespace AWS/IoT \
  --statistic Minimum \
  --period  \
  --evaluation-periods  \
  --threshold  \
  --comparison-operator LessThanOrEqualToThreshold \
  --alarm-actions "arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:smdh-alerts-${TENANT_ID}" \
  --region $AWS_REGION

echo " CloudWatch alarms created"
```

. SNS Topics for Alerts

```bash
!/bin/bash
source tenant_config_${TENANT_ID}.env

 Create SNS topic for tenant alerts
aws sns create-topic \
  --name "smdh-alerts-${TENANT_ID}" \
  --region $AWS_REGION

 Subscribe email
aws sns subscribe \
  --topic-arn "arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:smdh-alerts-${TENANT_ID}" \
  --protocol email \
  --notification-endpoint "${CONTACT_EMAIL}" \
  --region $AWS_REGION

echo " SNS topic and subscription created"
echo "Note: Confirm subscription via email"
```

. Snowflake Monitoring

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
LIMIT ;
```

---

. Automation Scripts

. Complete Tenant Onboarding Script

```bash
!/bin/bash
 SMDH Tenant Onboarding Automation Script
 Usage: ./onboard-tenant.sh company_a "Company A Ltd"

set -e

 Configuration
TENANT_ID=${:-test_tenant}
TENANT_NAME=${:-Test Tenant}
NUM_SITES=${:-}
SENSORS_PER_SITE=${:-}
RETENTION_DAYS=${:-}
AWS_REGION=${AWS_REGION:-eu-west-}

 Validation
if ! [[ $TENANT_ID =~ ^[a-z-_]+$ ]]; then
  echo " Error: Tenant ID must be lowercase alphanumeric"
  exit
fi

echo " Starting SMDH Tenant Onboarding"
echo "   Tenant ID: $TENANT_ID"
echo "   Tenant Name: $TENANT_NAME"
echo "   Sites: $NUM_SITES"
echo "   Sensors/Site: $SENSORS_PER_SITE"
echo ""

 Step : AWS IoT Setup
echo " Step : Creating AWS IoT Resources..."

 Create thing type
aws iot create-thing-type \
  --thing-type-name "LoRaWANGateway" \
  --region $AWS_REGION >/dev/null || true

 Create things and certificates
mkdir -p certificates/${TENANT_ID}
cd certificates/${TENANT_ID}

for ((site=; site<=$NUM_SITES; site++)); do
  SITE_ID=$(printf '%d' $site)
  THING_NAME="smdh-gateway-${TENANT_ID}-site-${SITE_ID}"
  CERT_NAME="${TENANT_ID}-site-${SITE_ID}"

   Create thing
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

   Generate certificate
  aws iot create-keys-and-certificate \
    --set-as-active \
    --certificate-pem-outfile "${CERT_NAME}-cert.pem" \
    --private-key-outfile "${CERT_NAME}-private.key" \
    --region $AWS_REGION

   Download CA certificate
  curl -s -o AmazonRootCA.pem \
    https://www.amazontrust.com/repository/AmazonRootCA.pem

  echo "   Created: $THING_NAME"
done

cd ../..

 Create policy
cat > iot-policy.json << EOF
{
  "Version": "--",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "iot:Connect",
      "Resource": "arn:aws:iot:${AWS_REGION}::client/smdh-gateway-${TENANT_ID}-"
    },
    {
      "Effect": "Allow",
      "Action": "iot:Publish",
      "Resource": "arn:aws:iot:${AWS_REGION}::topic/smdh/${TENANT_ID}/"
    }
  ]
}
EOF

aws iot create-policy \
  --policy-name "smdh-policy-${TENANT_ID}" \
  --policy-document file://iot-policy.json \
  --region $AWS_REGION

 Attach policy to certificates
for CERT in certificates/${TENANT_ID}/-cert.pem; do
  CERT_ID=$(aws iot describe-certificate --certificate-id $(basename $CERT .pem) --region $AWS_REGION --query 'certificateDescription.certificateId' --output text >/dev/null)
  if [ ! -z "$CERT_ID" ]; then
    CERT_ARN=$(aws iot describe-certificate --certificate-id $CERT_ID --region $AWS_REGION --query 'certificateDescription.certificateArn' --output text)
    aws iot attach-policy --policy-name "smdh-policy-${TENANT_ID}" --target $CERT_ARN --region $AWS_REGION
  fi
done

echo " AWS IoT setup complete"
echo ""

 Step : Snowflake Setup
echo " Step : Creating Snowflake Database..."

 Option : Use the validated scripts
cd infrastructure/snowflake
export SNOWSQL_PWD="$SNOWFLAKE_PASSWORD"
snowsql -r ACCOUNTADMIN -o variable_substitution=true \
  -D tenant_id="${TENANT_ID}" \
  -D tenant_name="${TENANT_NAME}" \
  -D aws_region="${AWS_REGION}" \
  -D num_sites="${NUM_SITES}" \
  -f tenant/_create_tenant_database.sql

 Option : Inline SQL with proper variable handling
snowsql -a $SNOWFLAKE_ACCOUNT -u $SNOWFLAKE_USER -r ACCOUNTADMIN \
  -o variable_substitution=true \
  -D tenant_id="${TENANT_ID}" \
  -f - << EOSQL
-- Set database name variable
SET database_name = 'smdh_tenant_' || '&tenant_id';

-- Create database with proper variable reference
CREATE DATABASE IF NOT EXISTS IDENTIFIER(\$database_name)
    DATA_RETENTION_TIME_IN_DAYS =
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
  sensor_id VARCHAR() NOT NULL,
  tenant_id VARCHAR() NOT NULL,
  timestamp TIMESTAMP_NTZ NOT NULL,
  payload VARIANT NOT NULL,
  ingestion_timestamp TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
  source_system VARCHAR(),
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

echo " Snowflake setup complete"
echo ""

 Step : Create Per-Tenant Kinesis Stream
echo " Step : Creating dedicated Kinesis stream for tenant..."

aws kinesis create-stream \
  --stream-name "smdh-${TENANT_ID}-stream" \
  --stream-mode-details StreamMode=ON_DEMAND \
  --region $AWS_REGION

aws kinesis wait stream-exists \
  --stream-name "smdh-${TENANT_ID}-stream" \
  --region $AWS_REGION

echo " Kinesis stream created: smdh-${TENANT_ID}-stream"
echo ""

 Step : Create IoT Rules (routes to tenant's dedicated stream)
echo " Step : Creating IoT Rules..."

cat > iot-rule.json << 'EOF'
{
  "sql": "SELECT *, topic(2) as tenant_id, topic(3) as site_id, timestamp() as iot_timestamp FROM 'smdh/${TENANT_ID}/+/sensor-data'",
  "actions": [
    {
      "kinesis": {
        "roleArn": "arn:aws:iam::${AWS_ACCOUNT_ID}:role/smdh-iot-kinesis-role",
        "streamName": "smdh-${TENANT_ID}-stream",
        "partitionKey": "${topic(3)}"
      }
    }
  ],
  "errorAction": {
    "republish": {
      "roleArn": "arn:aws:iam::${AWS_ACCOUNT_ID}:role/smdh-iot-kinesis-role",
      "topic": "smdh/errors/${TENANT_ID}"
    }
  }
}
EOF

aws iot create-topic-rule \
  --rule-name "smdh_route_${TENANT_ID}" \
  --topic-rule-payload file://iot-rule.json \
  --region $AWS_REGION

echo " IoT Rules created (routing to smdh-${TENANT_ID}-stream)"
echo ""

 Step : Create Alerts
echo " Step : Creating Monitoring Alerts..."

aws sns create-topic --name "smdh-alerts-${TENANT_ID}" --region $AWS_REGION || true

aws cloudwatch put-metric-alarm \
  --alarm-name "smdh-${TENANT_ID}-connection-failures" \
  --alarm-description "Connection failures for ${TENANT_ID}" \
  --metric-name Connect.Failure \
  --namespace AWS/IoT \
  --statistic Sum \
  --period  \
  --threshold  \
  --comparison-operator GreaterThanOrEqualToThreshold \
  --region $AWS_REGION

echo " Monitoring alerts created"
echo ""

 Cleanup
rm -f iot-policy.json iot-rule.json

echo " Tenant onboarding complete!"
echo ""
echo " Deliverables:"
echo "    Kinesis Stream: smdh-${TENANT_ID}-stream (dedicated per-tenant)"
echo "    Certificates: certificates/${TENANT_ID}/"
echo "    Snowflake Database: smdh_tenant_${TENANT_ID}"
echo "    IoT Core configured with tenant policies and rules"
echo "    Monitoring and alerts enabled"
echo ""
echo " Next steps:"
echo "   . Distribute certificates to gateways"
echo "   . Create Openflow connector in Snowsight for smdh-${TENANT_ID}-stream"
echo "   . Configure gateway MQTT settings with endpoint"
echo "   . Test data flow with sample messages"
echo "   . Verify data appears in Snowflake"
```

. Certificate Rotation Script

```bash
!/bin/bash
 Certificate Rotation Script

TENANT_ID=$
SITE_ID=$
AWS_REGION=${AWS_REGION:-eu-west-}

echo " Rotating certificate for ${TENANT_ID} - Site ${SITE_ID}..."

 Generate new certificate
CERT_ARN=$(aws iot create-keys-and-certificate \
  --set-as-active \
  --certificate-pem-outfile "${TENANT_ID}-site-${SITE_ID}-cert-new.pem" \
  --private-key-outfile "${TENANT_ID}-site-${SITE_ID}-private-new.key" \
  --region $AWS_REGION \
  --query 'certificateArn' \
  --output text)

 Attach policy to new certificate
aws iot attach-policy \
  --policy-name "smdh-policy-${TENANT_ID}" \
  --target $CERT_ARN \
  --region $AWS_REGION

 Update gateway with new certificate
echo "Upload new certificates to gateway and restart MQTT client"
echo "Old certificate will be automatically revoked after grace period"

 Schedule old certificate deactivation ( days later)
echo "Certificate rotation scheduled. Old cert will be deactivated on $(date -u -d "+ days" +%Y-%m-%d)"
```

---

. Validation and Testing

. End-to-End Test Procedure

```bash
!/bin/bash
 EE Validation Test

TENANT_ID=$
GATEWAY_THING_NAME="smdh-gateway-${TENANT_ID}-site-"
AWS_REGION=${AWS_REGION:-eu-west-}

echo " Running EE validation for ${TENANT_ID}..."

 Test : MQTT Connection
echo ""
echo "Test : MQTT Connection"
echo "  - Gateway should appear as 'Connected' in AWS IoT Core"
aws iot describe-thing \
  --thing-name $GATEWAY_THING_NAME \
  --region $AWS_REGION

 Test : Message Ingestion
echo ""
echo "Test : Publishing test message..."
 This requires publishing from gateway or via test client

 Test : Snowflake Data Verification
echo ""
echo "Test : Verifying data in Snowflake..."
snowsql -a $SNOWFLAKE_ACCOUNT -u $SNOWFLAKE_USER \
  -q "SELECT COUNT() FROM smdh_tenant_${TENANT_ID}.raw.sensor_readings;"

 Test : Topic ACLs
echo ""
echo "Test : Verifying topic ACLs (should fail for cross-tenant)..."
 Cross-tenant publish should fail

echo ""
echo " Validation complete!"
```

. Data Quality Checks

```sql
-- Monitor data ingestion quality
SET TENANT_ID = 'company_a';

-- Check ingestion rate
SELECT
  DATE_TRUNC('hour', ingestion_timestamp) as hour,
  COUNT() as record_count,
  COUNT(DISTINCT sensor_id) as unique_sensors
FROM smdh_tenant_&{TENANT_ID}.raw.sensor_readings
GROUP BY DATE_TRUNC('hour', ingestion_timestamp)
ORDER BY hour DESC
LIMIT ;

-- Check data quality
SELECT
  sensor_id,
  COUNT() as total_readings,
  COUNT(CASE WHEN payload IS NULL THEN  END) as null_payloads,
  COUNT(CASE WHEN DATEDIFF('minute', timestamp, ingestion_timestamp) >  THEN  END) as late_readings
FROM smdh_tenant_&{TENANT_ID}.raw.sensor_readings
GROUP BY sensor_id;
```

---

. Rollback Procedures

. Complete Tenant Offboarding

```bash
!/bin/bash
 Tenant Offboarding Script

TENANT_ID=$
read -p "Are you sure you want to offboard $TENANT_ID? (yes/no): " confirmation

if [ "$confirmation" != "yes" ]; then
  echo "Offboarding cancelled"
  exit
fi

AWS_REGION=${AWS_REGION:-eu-west-}

echo "  Starting tenant offboarding for ${TENANT_ID}..."

 Step : Backup Snowflake database
echo "Step : Creating backup..."
snowsql -a $SNOWFLAKE_ACCOUNT -u $SNOWFLAKE_USER \
  -q "CREATE DATABASE smdh_tenant_${TENANT_ID}_backup CLONE smdh_tenant_${TENANT_ID};"

 Step : Export data (optional)
echo "Step : Exporting data..."
snowsql -a $SNOWFLAKE_ACCOUNT -u $SNOWFLAKE_USER \
  -q "COPY (SELECT  FROM smdh_tenant_${TENANT_ID}.raw.sensor_readings LIMIT )
      TO '@~/offboard_${TENANT_ID}/'
      FILE_FORMAT = (TYPE = PARQUET) PARALLEL = ;"

 Step : Suspend Snowflake tasks
echo "Step : Suspending tasks..."
snowsql -a $SNOWFLAKE_ACCOUNT -u $SNOWFLAKE_USER \
  -q "ALTER TASK smdh_tenant_${TENANT_ID}.raw.process_sensor_data SUSPEND;"

 Step : Disable IoT certificates
echo "Step : Disabling IoT certificates..."
for CERT_ID in $(aws iot list-certificates --region $AWS_REGION --query 'certificates[].certificateId' --output text); do
  aws iot update-certificate \
    --certificate-id $CERT_ID \
    --new-status INACTIVE \
    --region $AWS_REGION >/dev/null || true
done

 Step : Delete IoT rules
echo "Step : Deleting IoT rules..."
aws iot delete-topic-rule \
  --rule-name "smdh_route_${TENANT_ID}" \
  --region $AWS_REGION

 Step : Delete IoT policy
echo "Step : Deleting IoT policy..."
aws iot delete-policy \
  --policy-name "smdh-policy-${TENANT_ID}" \
  --region $AWS_REGION

 Step : Delete Snowflake database (after backup confirmation)
echo "Step : Cleaning up Snowflake..."
snowsql -a $SNOWFLAKE_ACCOUNT -u $SNOWFLAKE_USER \
  -q "DROP DATABASE smdh_tenant_${TENANT_ID};"

 Step : Update infrastructure metadata
snowsql -a $SNOWFLAKE_ACCOUNT -u $SNOWFLAKE_USER \
  -q "UPDATE smdh_infrastructure.tenant_configs.tenants SET status='offboarded', offboard_date=CURRENT_TIMESTAMP() WHERE tenant_id='${TENANT_ID}';"

echo " Tenant offboarding complete"
echo "   Backup available: smdh_tenant_${TENANT_ID}_backup"
echo "   Exported data: ~/offboard_${TENANT_ID}/"
```

. Disaster Recovery

```sql
-- Restore from backup
CREATE DATABASE smdh_tenant_company_a CLONE smdh_tenant_company_a_backup;

-- Restore specific table from Time Travel
CREATE TABLE smdh_tenant_company_a.raw.sensor_readings CLONE smdh_tenant_company_a.raw.sensor_readings AT (TIMESTAMP => '--'::timestamp_ntz);

-- Recreate streams and tasks
CREATE STREAM smdh_tenant_company_a.raw.sensor_readings_stream
  ON TABLE smdh_tenant_company_a.raw.sensor_readings
  APPEND_ONLY = TRUE;
```

---

. Cost Estimates

. AWS Pricing Breakdown ( Tenants, M messages/day)

| Service         | Usage            | Monthly Cost | Annual Cost | Per-Tenant/Month |
| --------------- | ---------------- | ------------ | ----------- | ---------------- |
| IoT Core        | M messages/day   | ~$           | ~$,         | ~$.              |
| Kinesis         | On-demand, shard | ~$           | ~$          | ~$.              |
| Secrets Manager | secret           | ~$.          | ~$.         | ~$.              |
| CloudWatch      | GB logs/month    | ~$           | ~$,         | ~$.              |
| IAM Roles       | Minimal          | ~$           | ~$          | ~$.              |
| AWS Total       |                  | ~$/mo        | ~$,/year    | ~$.              |

. Snowflake Cost Estimation

```
Snowflake pricing varies by edition and region.
Example for  tenants (estimate):

- Standard Edition: $/credit
- Compute credits (ETL): , credits/month = $,
- Storage: TB average = $
- Openflow connector: ~$./million messages = ~$

Estimated Snowflake: $,/month or $,/year
Estimated per-tenant: $/month or $,/year
```

. Cost Optimization Tips

. Use Kinesis on-demand - Scales to zero when no data
. Auto-suspend Snowflake warehouses - Save % on idle time
. Set CloudWatch log retention - Avoid excessive storage charges
. Monitor certificate lifecycle - Prevent duplicate certificate creation
. Use Snowflake Time Travel wisely - Balance data protection vs. storage costs
. Consolidate logs - Aggregate tenant logs to reduce CloudWatch ingestion

---

Appendix A: Command Reference

AWS IoT Core Commands

```bash
 List things
aws iot list-things

 Describe thing
aws iot describe-thing --thing-name <thing-name>

 List certificates
aws iot list-certificates

 Describe certificate
aws iot describe-certificate --certificate-id <cert-id>

 Update certificate status
aws iot update-certificate --certificate-id <cert-id> --new-status INACTIVE

 List policies
aws iot list-policies

 Get policy
aws iot get-policy --policy-name <policy-name>

 List topic rules
aws iot list-topic-rules
```

Snowflake Commands

```sql
-- List databases
SHOW DATABASES;

-- List tables in database
SHOW TABLES IN DATABASE <database_name>;

-- Monitor task execution
SELECT  FROM INFORMATION_SCHEMA.TASK_HISTORY LIMIT ;

-- Monitor data ingestion
SELECT  FROM INFORMATION_SCHEMA.TABLE_STORAGE_METRICS;

-- Check warehouse status
SHOW WAREHOUSES;

-- Monitor query performance
SELECT  FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY LIMIT ;
```

---

Appendix B: Troubleshooting

Snowflake Variable Reference Issues

Symptoms: "Variable is not defined" errors in SnowSQL

Root Cause: Confusion between SnowSQL and SQL session variables

Solutions:
. SnowSQL variables (`&variable`): Pass via `-D` flag, e.g., `-D tenant_id=test_tenant`
. SQL session variables (`$variable`): Create with `SET`, reference with `$`
. Always use `-o variable_substitution=true` when using `&` variables
. Example of correct usage:

```sql
-- Create SQL session variable
SET database_name = 'smdh_tenant_' || '&tenant_id';
-- Use SQL session variable with $
USE DATABASE IDENTIFIER($database_name);
```

Snowflake CREATE DATABASE/ROLE Comment Syntax Errors

Symptoms: "Syntax error unexpected '('" when using CONCAT in COMMENT clause

Root Cause: COMMENT clauses don't support functions, only literals or simple concatenation

Solutions:
. Wrong: `COMMENT = CONCAT('text', variable, 'text')`
. Correct: `COMMENT = 'text ' || variable || ' text'`
. Also Correct: `COMMENT = 'Static text with &snowsql_variable substitution'`

Issue: Gateway Cannot Connect to IoT Core

Symptoms: Connection timeout, "certificate verify failed"

Solutions:
. Verify certificate files are correct (check certificate dates)
. Ensure TLS port is not blocked by firewall
. Verify IoT endpoint address is correct
. Check certificate permissions ( for private key)
. Validate certificate against root CA

Issue: No Data Appearing in Snowflake

Symptoms: Records published to MQTT but not in sensor_readings table

Solutions:
. Check IoT Rule is enabled
. Verify Kinesis stream has data
. Check Snowflake task is running
. Look at task execution history for errors
. Verify Openflow connector configuration

Issue: High Latency in Data Pipeline

Symptoms: Data takes > minutes to appear in Snowflake

Solutions:
. Check Kinesis iterator age in CloudWatch
. Verify Snowflake warehouse is running
. Look for slow task execution
. Check for database locks
. Monitor network latency to AWS

Issue: Deprecated Kinesis Integration Script

Symptoms: Running `setup_kinesis_integration.sh` shows deprecation warning or SQL errors

Root Cause: The original script attempted to use Snowpipe syntax to connect directly to Kinesis, which is not supported. Snowflake requires the Openflow Connector for native Kinesis integration.

Solution:
. **DO NOT USE** `infrastructure/snowflake/scripts/setup_kinesis_integration.sh` - it is deprecated
. **USE INSTEAD**: Snowflake Openflow Connector approach:
   - Run `infrastructure/snowflake/sql/core/03_openflow_connector.sql` in Snowsight
   - Complete UI configuration in Snowsight (Ingestion > Openflow)
   - Follow `infrastructure/deployment/Tenant_Onboarding_Guide.md`

The correct architecture uses:
- Per-tenant Kinesis streams (not a shared stream)
- Snowflake Openflow Connector (not Snowpipe)
- Stream-to-table routing via Openflow configuration

Issue: Openflow External Access Integration Fails

Symptoms: "External access is not supported for trial accounts" error

Root Cause: External Access Integrations require a paid Snowflake account

Solution:
. Upgrade from trial to paid Snowflake account
. After upgrading, enroll in MFA (required for paid accounts)
. Re-run the Openflow setup SQL script

---

Document History

| Date | Version | Changes | Author |
| ---- | ------- | ------- | ------ |
| 2025-12-06 | 2.1 | Updated Terraform to use three-file tfvars structure, corrected Openflow navigation path, added critical configuration requirements table, updated directory structure | Platform Team |
| 2024-12-02 | 2.0 | Added Snowflake Openflow Connector for native Kinesis integration, documented per-tenant stream architecture decision, updated tenant onboarding with Openflow configuration | Platform Team |
| 2024-11-20 | 1.3 | Updated Snowflake configuration with validated scripts, added variable reference documentation, included troubleshooting for common SQL issues | Platform Team |
| 2024-11-15 | 1.2 | Added Terraform deployment section with actual deployment results | Platform Team |
| 2024-11-01 | 1.1 | Initial release with manual CLI procedures | Platform Team |

---

**Related Documentation:**

| Document | Purpose | Location |
|----------|---------|----------|
| Core Infrastructure Deployment Guide | Step-by-step deployment | `infrastructure/deployment/Core_Infrastructure_Deployment_Guide.md` |
| Tenant Onboarding Guide | Per-tenant setup | `infrastructure/deployment/Tenant_Onboarding_Guide.md` |
| CLAUDE.md | Development guidelines | `CLAUDE.md` |
