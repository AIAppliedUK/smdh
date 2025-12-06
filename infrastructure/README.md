# SMDH Infrastructure Setup Guide

This directory contains the complete infrastructure configuration for the **Smart Manufacturing Data Hub (SMDH)** platform. Use these scripts and configurations to set up your own AWS and Snowflake environment for receiving IoT sensor data via MQTT from LoRaWAN gateways.

## Overview

The SMDH platform collects sensor data from manufacturing facilities using:

- **LoRaWAN sensors** (e.g., DevTank OpenSmartMonitor) connected to gateways
- **LoRaWAN gateways** (e.g., Milesight UG65) that publish to AWS IoT Core via MQTT
- **AWS IoT Core** as the managed MQTT broker with X.509 certificate authentication
- **Amazon Kinesis** for data buffering and ordering
- **Snowflake** for data storage, processing, and analytics

```
┌─────────────────┐     LoRaWAN      ┌─────────────────┐     MQTT/TLS     ┌─────────────────┐
│  LoRaWAN        │ ───────────────► │  LoRaWAN        │ ───────────────► │  AWS IoT Core   │
│  Sensors        │                  │  Gateway        │   (X.509 cert)   │  MQTT Broker    │
│  (DevTank OSM)  │                  │  (Milesight)    │                  │                 │
└─────────────────┘                  └─────────────────┘                  └────────┬────────┘
                                                                                   │
                                                                         IoT Rules Engine
                                                                                   │
                                                                                   ▼
┌─────────────────┐                  ┌─────────────────┐                  ┌─────────────────┐
│  Snowflake      │ ◄──────────────  │  Snowflake      │ ◄──────────────  │  Kinesis        │
│  Analytics      │   Dynamic Tables │  Openflow       │   Stream Read    │  Data Streams   │
│  & Dashboards   │                  │  Connector      │                  │                 │
└─────────────────┘                  └─────────────────┘                  └─────────────────┘
```

## Directory Structure

```
infrastructure/
├── README.md                              # This file
├── terraform/                             # AWS Infrastructure as Code
│   ├── main.tf                            # Root Terraform configuration
│   ├── modules/
│   │   ├── iot-core/                      # AWS IoT Core resources
│   │   ├── kinesis/                       # Kinesis Data Streams
│   │   ├── iam/                           # IAM roles for Snowflake integration
│   │   ├── secrets-manager/               # Credential management
│   │   ├── cloudwatch/                    # Monitoring and alerting
│   │   └── tenant/                        # Per-tenant resources
│   └── environments/                      # Environment-specific configs
│       ├── dev/
│       └── prod/
│
├── snowflake/                             # Snowflake setup and configuration
│   ├── sql/
│   │   ├── core/                          # Platform infrastructure scripts
│   │   ├── tenant/                        # Per-tenant setup scripts
│   │   └── utility/                       # Validation and utility scripts
│   └── scripts/                           # Automation scripts
│
├── scripts/                               # Operational scripts
│   ├── check_system_health.sh             # Health monitoring
│   └── check_iot_costs.sh                 # Cost tracking
│
└── docs/                                  # Additional documentation
    ├── DEPLOYMENT_NOTES.md
    ├── SMDH_Implementation_Plan.md
    └── SMDH_Infrastructure_Implementation.md
```

## Infrastructure Architecture

The infrastructure is divided into **Core** (one-time setup) and **Tenant** (per-tenant) components:

### Core Infrastructure (Deploy Once)

| Layer | Component | Description |
|-------|-----------|-------------|
| AWS | IoT Core | Thing types, logging configuration |
| AWS | IAM | Roles for Snowflake integration |
| AWS | CloudWatch | Platform-wide dashboard and base alarms |
| AWS | Secrets Manager | Credential storage |
| AWS | IAM User | Dedicated user for Openflow Kinesis access |
| Snowflake | Infrastructure DB | `SMDH_INFRASTRUCTURE` with tenant configs |
| Snowflake | Warehouse | `SMDH_WH` shared compute |
| Snowflake | Roles | Base roles and Openflow runtime role |
| Snowflake | External Access | `OPENFLOW_AWS_EAI` for AWS connectivity |
| Snowflake | Openflow | Deployment and runtime (manual via Snowsight) |

### Tenant Infrastructure (Deploy Per Tenant)

| Layer | Component | Description |
|-------|-----------|-------------|
| AWS | Kinesis Stream | `smdh-{tenant_id}-stream` per tenant |
| AWS | IoT Policy | Tenant-scoped MQTT topic access |
| AWS | IoT Rule | Routes messages to tenant's Kinesis stream |
| AWS | Certificates | Per-site X.509 certificates |
| AWS | Thing Groups | Tenant and site hierarchy |
| AWS | CloudWatch Alarms | Per-stream iterator age and error alarms |
| Snowflake | Tenant Database | `SMDH_TENANT_{TENANT_ID}` |
| Snowflake | Schemas | RAW, NORMALIZED, AGGREGATED, ANALYTICS |
| Snowflake | Tables | Typed sensor tables and metadata |
| Snowflake | Streams | CDC streams for data routing |
| Snowflake | Tasks | Automated data routing task |
| Snowflake | Roles | Tenant-specific access roles |
| Snowflake | Kinesis Connector | Openflow connector (manual via Snowsight) |

### Deployment Order

The deployment must follow this order due to dependencies:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         CORE INFRASTRUCTURE                              │
├─────────────────────────────────────────────────────────────────────────┤
│  Phase 1: AWS Core                                                       │
│  └── terraform apply -var-file=environments/dev/core.tfvars             │
│                                                                          │
│  Phase 2: IAM User for Openflow                                          │
│  └── aws iam create-user + create-access-key                            │
│                                                                          │
│  Phase 3: Snowflake Core                                                 │
│  └── snowsql -f 01, 02, 03 scripts                                      │
│                                                                          │
│  Phase 4: Openflow Runtime (Manual - Snowsight UI)                       │
│  └── Create deployment → Create runtime                                  │
├─────────────────────────────────────────────────────────────────────────┤
│                        TENANT INFRASTRUCTURE                             │
├─────────────────────────────────────────────────────────────────────────┤
│  Phase 5: AWS Tenant                                                     │
│  └── terraform apply -var-file=environments/dev/terraform.tfvars        │
│                                                                          │
│  Phase 6: Snowflake Tenant                                               │
│  └── snowsql -f 10, 11, 12, 13, 14, 16 scripts                          │
│                                                                          │
│  Phase 7: Kinesis Connector (Manual - Snowsight UI)                      │
│  └── Add connector to runtime for tenant's stream                        │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Prerequisites

### 1. AWS Account

- AWS account with administrator access
- Region: `eu-west-2` (London) recommended
- AWS CLI installed and configured

```bash
# Install AWS CLI
brew install awscli  # macOS
# or download from https://aws.amazon.com/cli/

# Configure credentials
aws configure
# Enter: Access Key ID, Secret Access Key, Region (eu-west-2)

# Verify
aws sts get-caller-identity
```

### 2. Snowflake Account

- Snowflake account (Enterprise edition or higher for Dynamic Tables)
- Region: `eu-west-2` (London) recommended for optimal Kinesis integration
- SnowSQL CLI installed

```bash
# Install SnowSQL
brew install snowflake-snowsql  # macOS
# or download from https://docs.snowflake.com/en/user-guide/snowsql-install-config

# Verify
snowsql --version
```

### 3. Terraform

```bash
# Install Terraform
brew install terraform  # macOS
# or download from https://www.terraform.io/downloads

# Verify (v1.0+ required)
terraform version
```

### 4. Gateway Hardware

- Milesight UG65 LoRaWAN gateway (or compatible)
- DevTank OpenSmartMonitor sensors (or compatible LoRaWAN Class A sensors)

---

## Quick Start

### Prerequisites Setup

#### Create Terraform State Backend

Before deploying infrastructure, create an S3 bucket and DynamoDB table for Terraform state management:

```bash
# Create S3 bucket for state storage
aws s3 mb s3://smdh-terraform-state --region eu-west-2

# Enable versioning for state history
aws s3api put-bucket-versioning \
  --bucket smdh-terraform-state \
  --versioning-configuration Status=Enabled

# Create DynamoDB table for state locking
aws dynamodb create-table \
  --table-name smdh-terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region eu-west-2
```

#### Configure SnowSQL

```bash
# Configure SnowSQL (creates ~/.snowsql/config)
snowsql -a <your-account> -u <your-user>
# Enter password when prompted, then exit with !quit

# Alternatively, edit ~/.snowsql/config directly:
# [connections.smdh]
# accountname = <your-account>
# username = <your-user>
# password = <your-password>

# Set credentials for command-line use
export SNOWFLAKE_ACCOUNT="your-account"
export SNOWFLAKE_USER="your-user"
export SNOWSQL_PWD="your-password"
```

---

## Core Infrastructure Deployment

### Phase 1: Deploy AWS Core

Deploy AWS core infrastructure (IoT Core, IAM roles, CloudWatch dashboard) **without** any tenants:

```bash
cd infrastructure/terraform

# Initialise Terraform (connects to S3 backend)
terraform init

# Review the core-only plan (no tenants)
terraform plan -var-file=environments/dev/core.tfvars

# Apply core configuration
terraform apply -var-file=environments/dev/core.tfvars
```

### Phase 2: Create IAM User for Openflow

**IMPORTANT:** Openflow Kinesis connector only supports IAM Access Key authentication. Role assumption is NOT supported.

```bash
# Create dedicated IAM user
aws iam create-user --user-name smdh-openflow-kinesis-user --region eu-west-2

# Get your AWS account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Create policy document
cat > /tmp/openflow-kinesis-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "KinesisAccess",
      "Effect": "Allow",
      "Action": [
        "kinesis:DescribeStream",
        "kinesis:DescribeStreamSummary",
        "kinesis:GetShardIterator",
        "kinesis:GetRecords",
        "kinesis:ListShards"
      ],
      "Resource": "arn:aws:kinesis:eu-west-2:${AWS_ACCOUNT_ID}:stream/smdh-*"
    },
    {
      "Sid": "DynamoDBAccess",
      "Effect": "Allow",
      "Action": [
        "dynamodb:CreateTable",
        "dynamodb:UpdateTable",
        "dynamodb:DescribeTable",
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:UpdateItem",
        "dynamodb:DeleteItem",
        "dynamodb:Scan",
        "dynamodb:Query"
      ],
      "Resource": "arn:aws:dynamodb:eu-west-2:${AWS_ACCOUNT_ID}:table/smdh-*"
    },
    {
      "Sid": "DynamoDBListTables",
      "Effect": "Allow",
      "Action": ["dynamodb:ListTables"],
      "Resource": "*"
    },
    {
      "Sid": "CloudWatchMetrics",
      "Effect": "Allow",
      "Action": ["cloudwatch:PutMetricData"],
      "Resource": "*"
    }
  ]
}
EOF

# Attach policy to user
aws iam put-user-policy \
  --user-name smdh-openflow-kinesis-user \
  --policy-name smdh-openflow-kinesis-policy \
  --policy-document file:///tmp/openflow-kinesis-policy.json \
  --region eu-west-2

# Create access keys - SAVE THESE SECURELY
aws iam create-access-key --user-name smdh-openflow-kinesis-user --region eu-west-2
```

**Store the Access Key ID and Secret Access Key securely** - you will need them when configuring the Kinesis connector in Snowsight.

> **Note:** The Kinesis Client Library (KCL) uses DynamoDB for checkpointing. The `dynamodb:UpdateTable` permission is required for lease management.

### Phase 3: Deploy Snowflake Core

```bash
cd infrastructure/snowflake/sql/core

# Deploy infrastructure database, warehouse, and roles
snowsql -a $SNOWFLAKE_ACCOUNT -u $SNOWFLAKE_USER -r ACCOUNTADMIN \
  -f 01_infrastructure_setup.sql

# Deploy shared resources (warehouse, monitoring)
snowsql -a $SNOWFLAKE_ACCOUNT -u $SNOWFLAKE_USER -r ACCOUNTADMIN \
  -f 02_shared_resources.sql

# Deploy Openflow configuration (external access, roles)
snowsql -a $SNOWFLAKE_ACCOUNT -u $SNOWFLAKE_USER -r ACCOUNTADMIN \
  -f 03_openflow_connector.sql
```

### Phase 4: Configure Openflow Runtime (Snowsight UI)

**Note:** Openflow Deployments and Runtimes cannot be created via SQL - this requires the Snowsight UI.

**Create Deployment:**
1. Open **Snowsight** → **Ingestion** → **Openflow**
2. Click **+ Create deployment**
3. Configure:
   - **Name**: `smdh-openflow-deployment`
   - **Type**: Snowflake Deployment (managed)
4. Click **Create deployment**
5. **Wait 15-20 minutes** for deployment to become Active

**Create Runtime:**
1. In Snowsight → **Ingestion** → **Openflow** → your deployment
2. Click **+ Create runtime**
3. Configure:
   - **Name**: `smdh-kinesis-runtime`
   - **Role**: `OPENFLOW_RUNTIME_ROLE_KINESIS`
   - **Warehouse**: `SMDH_WH`
   - **External Access Integration**: `OPENFLOW_AWS_EAI`
4. Click **Create**
5. **Wait 5-10 minutes** for runtime to become Active

---

## Tenant Infrastructure Deployment

### Phase 5: Deploy AWS Tenant Infrastructure

Add your tenant configuration to `terraform.tfvars` and apply:

```bash
cd infrastructure/terraform

# Edit terraform.tfvars to add tenants
# Example configuration:
cat >> environments/dev/terraform.tfvars << 'EOF'

tenants = {
  mycompany = {
    name             = "My Company Ltd"
    num_sites        = 3
    retention_days   = 90
    warehouse_size   = "SMALL"
    contact_email    = "alerts@mycompany.com"
    sensors_per_site = 30
  }
}
EOF

# Review tenant resources to be created
terraform plan -var-file=environments/dev/terraform.tfvars

# Apply tenant configuration
terraform apply -var-file=environments/dev/terraform.tfvars
```

This creates for each tenant:
- Kinesis Data Stream (`smdh-{tenant_id}-stream`)
- IoT Policy with tenant-scoped topic access
- IoT Rule routing to the tenant's Kinesis stream
- X.509 certificates for each site
- Thing Groups for tenant and site hierarchy
- CloudWatch alarms for stream health

### Phase 6: Deploy Snowflake Tenant Infrastructure

```bash
cd infrastructure/snowflake/sql/tenant

# Set tenant ID for all scripts
TENANT_ID="mycompany"

# Create tenant database
snowsql -a $SNOWFLAKE_ACCOUNT -u $SNOWFLAKE_USER -r ACCOUNTADMIN -w SMDH_WH \
  -f 10_create_tenant_database.sql \
  --variable tenant_id=$TENANT_ID

# Create schemas (RAW, NORMALIZED, AGGREGATED, ANALYTICS)
snowsql -a $SNOWFLAKE_ACCOUNT -u $SNOWFLAKE_USER -r ACCOUNTADMIN -w SMDH_WH \
  -f 11_create_schemas.sql \
  --variable tenant_id=$TENANT_ID

# Create typed sensor tables
snowsql -a $SNOWFLAKE_ACCOUNT -u $SNOWFLAKE_USER -r ACCOUNTADMIN -w SMDH_WH \
  -f 12_create_tables.sql \
  --variable tenant_id=$TENANT_ID

# Create CDC streams
snowsql -a $SNOWFLAKE_ACCOUNT -u $SNOWFLAKE_USER -r ACCOUNTADMIN -w SMDH_WH \
  -f 13_create_streams.sql \
  --variable tenant_id=$TENANT_ID

# Create tenant roles
snowsql -a $SNOWFLAKE_ACCOUNT -u $SNOWFLAKE_USER -r ACCOUNTADMIN -w SMDH_WH \
  -f 16_create_roles.sql \
  --variable tenant_id=$TENANT_ID

# Grant Openflow access to tenant database
snowsql -a $SNOWFLAKE_ACCOUNT -u $SNOWFLAKE_USER -r ACCOUNTADMIN -w SMDH_WH \
  -q "CALL SMDH_INFRASTRUCTURE.TENANT_CONFIGS.SP_GRANT_OPENFLOW_TENANT_ACCESS('$TENANT_ID');"
```

### Phase 7: Add Kinesis Connector (Snowsight UI)

After deploying tenant infrastructure, add the Kinesis connector in Snowsight:

1. In Snowsight → **Ingestion** → **Openflow** → **Runtimes**
2. Click on `smdh-kinesis-runtime`
3. Click **Add Connector** → **Kinesis Data Streams: JSON modularized**
4. **Enter the process group** by double-clicking it

5. Configure **AWSCredentialsProviderControllerService** (Access Keys Required):

   | Parameter | Value |
   |-----------|-------|
   | AWS Access Key ID | Create IAM user access key (see below) |
   | AWS Secret Access Key | Create IAM user access key (see below) |

   > **IMPORTANT**: Openflow Kinesis connector does NOT support IAM Role Assumption. You must create a dedicated IAM user with access keys:
   > ```bash
   > aws iam create-user --user-name smdh-openflow-kinesis-user
   > aws iam create-access-key --user-name smdh-openflow-kinesis-user
   > ```
   > Attach the policy from `docs/deployment/Openflow_Kinesis_Configuration_Guide.md`

6. Configure **Kinesis Source Parameters**:

   | Parameter | Value |
   |-----------|-------|
   | AWS Region | `eu-west-2` |
   | Stream Name | `smdh-mycompany-stream` |
   | Application Name | `smdh-openflow-mycompany` |
   | Initial Position | `TRIM_HORIZON` (all data) or `LATEST` (new only) |
   | **Consumer Type** | **`POLLING` (Shared Throughput)** |
   | Metrics Publishing | `Disabled` |

   > **CRITICAL**: Consumer Type MUST be set to `POLLING` (Shared Throughput). Enhanced Fan-Out causes `InterruptedException` errors.

7. Configure **Streaming Destination Parameters**:

   | Parameter | Value |
   |-----------|-------|
   | Snowflake Account | `<org>-<account>` (e.g., `qqoylnv-zy42691`) |
   | Database | `SMDH_TENANT_MYCOMPANY` |
   | Schema | `RAW` |
   | **Authentication Strategy** | **`SNOWFLAKE_SESSION_TOKEN`** |
   | Role | `OPENFLOW_RUNTIME_ROLE_KINESIS` |
   | Warehouse | `SMDH_WH` |

   > **IMPORTANT**: Use `SNOWFLAKE_SESSION_TOKEN` authentication. Do NOT configure private key authentication.

8. Configure **Controller Services**:
   - **Disable** the `StandardPrivateKeyService` (not needed for session token auth)
   - **Enable** all other Controller Services in dependency order

9. **Start** the flow from the parent process group

See full configuration guide: [Openflow_Kinesis_Configuration_Guide.md](docs/deployment/Openflow_Kinesis_Configuration_Guide.md)

### Phase 8: Deploy Data Routing Task

After Openflow is configured and data is flowing, deploy the data routing task to distribute data to typed sensor tables:

```bash
cd infrastructure/snowflake/sql/tenant

# Deploy routing task for tenant
snowsql -a <account> -u <user> -r ACCOUNTADMIN -w SMDH_WH \
  -f 14_create_routing_task.sql \
  --variable tenant_id='mycompany'
```

**What this creates:**
- `OPENFLOW_LANDING_STREAM` - CDC stream on Openflow landing table
- `TASK_ROUTE_SENSOR_DATA` - Runs every minute to route data
- `sp_route_sensor_data()` - Routing procedure
- `sp_backfill_typed_tables()` - Backfill historical data

**Data Routing Flow:**
```
Openflow Landing Table ("SMDH-{TENANT}-STREAM")
          ↓ (Stream + Task every 1 minute)
    ┌─────┴─────┬──────────────┬──────────────┬──────────────┐
    ↓           ↓              ↓              ↓              ↓
SENSOR_     ENVIRONMENTAL_  VIBRATION_     CLAMP_       DEVICE_
READINGS    SENSOR_READINGS SENSOR_READINGS SENSOR_...  STATUS
(all data)  (AM308/EM300)   (vibration)    (CT-Clamp)  (status)
```

**Routing Rules:**
| Sensor Type | Destination Table | Match Criteria |
|-------------|------------------|----------------|
| All | `sensor_readings` | All records (master table) |
| Environmental | `environmental_sensor_readings` | AM308, EM300, temp/humidity data |
| Vibration | `vibration_sensor_readings` | `sensorType='vibration'` or device name |
| Clamp/Power | `clamp_sensor_readings` | `sensorType='clamp_current'` or CT-Clamp |
| Device Status | `device_status` | `sensorType='device_status'` or Status- |

**Verify routing is working:**
```sql
USE DATABASE SMDH_TENANT_MYCOMPANY;

-- Check record counts
SELECT 'Landing' AS tbl, COUNT(*) FROM RAW."SMDH-MYCOMPANY-STREAM"
UNION ALL SELECT 'sensor_readings', COUNT(*) FROM RAW.sensor_readings
UNION ALL SELECT 'environmental', COUNT(*) FROM RAW.environmental_sensor_readings
UNION ALL SELECT 'vibration', COUNT(*) FROM RAW.vibration_sensor_readings
UNION ALL SELECT 'clamp', COUNT(*) FROM RAW.clamp_sensor_readings
UNION ALL SELECT 'device_status', COUNT(*) FROM RAW.device_status;

-- Check task status
SELECT name, state FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY())
WHERE name = 'TASK_ROUTE_SENSOR_DATA'
ORDER BY scheduled_time DESC LIMIT 5;
```

### Phase 9: Configure Gateway

1. Access your Milesight UG65 gateway web interface
2. Configure the built-in Network Server or connect to ChirpStack
3. Register your DevTank OSM sensors (DevEUI, AppKey)
4. Configure MQTT output:
   - Server: `{iot-endpoint}.iot.eu-west-2.amazonaws.com` (from Terraform output)
   - Port: `8883` (MQTT with TLS)
   - Client ID: `smdh-gateway-{tenant_id}-site-001`
   - Upload X.509 certificate and private key (from Terraform output)
   - Topic: `smdh/{tenant_id}/sensor-data`

---

## Detailed Component Guides

### AWS (Terraform)

Full documentation: [terraform/README.md](terraform/README.md)

**State Management:**

Terraform state is stored remotely in S3 with DynamoDB locking to enable team collaboration:

| Resource | Purpose |
|----------|---------|
| S3 bucket: `smdh-terraform-state` | Stores state files with versioning |
| DynamoDB table: `smdh-terraform-locks` | Prevents concurrent modifications |

State commands:
```bash
# Show current state
terraform show

# List managed resources
terraform state list

# View specific resource
terraform state show module.iot_core.aws_iot_thing_type.lorawan_gateway
```

**Key features:**
- AWS IoT Core with Thing Types, Thing Groups, and IoT policies
- Kinesis Data Streams with on-demand scaling
- IAM roles for Snowflake cross-account access
- CloudWatch dashboards and alarms
- Per-tenant resource isolation

**Adding a new tenant:**
```hcl
# In terraform.tfvars
tenants = {
  new_tenant = {
    name             = "New Tenant Company Ltd"
    num_sites        = 3
    retention_days   = 365
    contact_email    = "alerts@newtenant.com"
  }
}
```

### Snowflake

Full documentation: [snowflake/README.md](snowflake/README.md)

Key features:
- Database-per-tenant isolation
- Real-time streaming with Snowflake Openflow
- Automated ETL with Streams and Tasks
- Dynamic Tables for sub-minute analytics
- Comprehensive RBAC and monitoring

**Database structure per tenant:**
```
smdh_tenant_{tenant_id}/
├── raw/           # Ingested data from Kinesis
├── normalized/    # Validated and flattened data
├── aggregated/    # Pre-computed metrics (hourly, daily)
└── analytics/     # Views, dashboards, stored procedures
```

### Operational Scripts

Full documentation: [scripts/README.md](scripts/README.md)

**Health monitoring:**
```bash
# Check all sites for a tenant
./scripts/check_system_health.sh --tenant-id mycompany

# Check specific site
./scripts/check_system_health.sh --tenant-id mycompany --site-id site_001 --verbose
```

**Cost tracking:**
```bash
# View IoT costs for a tenant
./scripts/check_iot_costs.sh --tenant-id mycompany --period 30

# Export to CSV
./scripts/check_iot_costs.sh --tenant-id mycompany --export-csv costs.csv
```

---

## Network Server Options

DevTank OSM sensors cannot store X.509 certificates, so they connect via LoRaWAN to a gateway that handles AWS IoT Core authentication.

### Option A: Milesight UG65 Built-in Network Server (Recommended for simplicity)

- Gateway receives LoRaWAN packets and decodes payloads
- MQTT output directly to AWS IoT Core
- Best for: Single-site deployments, <30 sensors

### Option B: ChirpStack (Recommended for scale)

- Centralised Network Server for multi-site deployments
- Native AWS IoT Core integration
- Best for: Multi-site deployments, central device management

See the full architecture design: [docs/detailed-design/SMDH AWS design.md](../docs/detailed-design/SMDH%20AWS%20design.md)

---

## Security

### Device Authentication

- Gateways authenticate to AWS IoT Core using X.509 certificates
- Each tenant has isolated certificates and IoT policies
- Topic ACLs prevent cross-tenant access: `smdh/{tenant_id}/*`

### Data Encryption

- TLS 1.3 for all MQTT connections (port 8883)
- Kinesis encryption at rest
- Snowflake encryption at rest and in transit

### Access Control

- AWS IAM roles with least-privilege access
- Snowflake RBAC with tenant isolation
- Audit logging via CloudTrail and Snowflake audit tables

---

## Multi-Tenancy

The platform provides complete data isolation:

| Layer | Isolation Method |
|-------|------------------|
| Device | Separate X.509 certificates per gateway |
| Topic | Topic ACLs enforce `smdh/{tenant_id}/*` |
| Stream | Kinesis partitioned by `{tenant_id}` |
| Database | Separate Snowflake database per tenant |
| Application | Role-based access control |

---

## Monitoring

### CloudWatch Dashboard

After Terraform deployment:
```bash
terraform output cloudwatch_dashboard_url
```

Metrics include:
- MQTT message rate
- Connection status
- IoT Rule execution
- Kinesis iterator age
- Certificate expiry countdown

### Snowflake Monitoring

```sql
-- Real-time summary
SELECT * FROM analytics.v_system_summary;

-- Ingestion metrics
SELECT * FROM analytics.v_ingestion_monitoring;

-- Pipeline health
SELECT * FROM analytics.v_pipeline_health;

-- Active alerts
SELECT * FROM analytics.v_active_alerts;
```

---

## Estimated Costs

For a deployment with 30 tenants and ~26M messages/day:

| Service | Monthly Cost | Notes |
|---------|-------------|-------|
| AWS IoT Core | ~$130 | $0.12 per million messages |
| Kinesis | ~$15-20 | On-demand, auto-scales |
| Secrets Manager | ~$0.40 | Per secret + API calls |
| CloudWatch | ~$100 | Logs, metrics, alarms |
| **AWS Total** | **~$250/mo** | ~$8-10 per tenant/month |
| Snowflake | ~$5-10K/mo | Storage and compute |

---

## Troubleshooting

### No data in Snowflake

1. Check gateway MQTT connection:
   ```bash
   aws iot describe-thing --thing-name smdh-gateway-{tenant_id}-site-001
   ```

2. Verify IoT Rules are active:
   ```bash
   aws iot get-topic-rule --rule-name smdh_route_{tenant_id}
   ```

3. Check per-tenant Kinesis stream:
   ```bash
   # Each tenant has a dedicated stream: smdh-{tenant_id}-stream
   aws kinesis describe-stream-summary --stream-name smdh-{tenant_id}-stream
   ```

4. Verify Openflow connector status in Snowflake:
   ```sql
   -- Check Openflow connector ingestion history
   SELECT * FROM TABLE(INFORMATION_SCHEMA.OPENFLOW_INGESTION_HISTORY())
   WHERE connector_name = 'smdh-openflow-{tenant_id}'
   ORDER BY start_time DESC LIMIT 5;
   ```

### Gateway connection failures

1. Verify certificate is active:
   ```bash
   aws iot describe-certificate --certificate-id {cert_id}
   ```

2. Check IoT policy allows connection:
   ```bash
   aws iot get-policy --policy-name smdh-policy-{tenant_id}
   ```

3. Test with AWS IoT MQTT test client in AWS Console

### Health check failures

```bash
# Run verbose health check
./scripts/check_system_health.sh --tenant-id {tenant_id} --verbose

# Check disconnected devices
aws iot list-things-in-thing-group \
  --thing-group-name smdh-{tenant_id}-disconnected \
  --region eu-west-2
```

---

## Support

- Design documentation: [docs/detailed-design/SMDH AWS design.md](../docs/detailed-design/SMDH%20AWS%20design.md)
- Implementation guide: [SMDH_Infrastructure_Implementation.md](SMDH_Infrastructure_Implementation.md)

For additional help:
- AWS IoT Core: [AWS IoT Developer Guide](https://docs.aws.amazon.com/iot/latest/developerguide/)
- Snowflake: [Snowflake Documentation](https://docs.snowflake.com/)
- Milesight UG65: [Milesight Documentation](https://www.milesight.com/iot/resources/download-center)
- DevTank OSM: Contact DevTank for device documentation
