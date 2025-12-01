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

### Step 1: Create Terraform State Backend

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

### Step 2: Deploy AWS Infrastructure

```bash
cd infrastructure/terraform

# Copy and configure environment variables
cp environments/dev/terraform.tfvars.example environments/dev/terraform.tfvars
# Edit terraform.tfvars with your settings

# Initialize Terraform (connects to S3 backend)
terraform init

# Review the plan
terraform plan -var-file=environments/dev/terraform.tfvars

# Apply configuration
terraform apply -var-file=environments/dev/terraform.tfvars

# Note the outputs - you'll need these for Snowflake setup
terraform output
```

### Step 3: Deploy Snowflake Infrastructure

First, configure SnowSQL with your Snowflake account details:

```bash
# Configure SnowSQL (creates ~/.snowsql/config)
snowsql -a <your-account> -u <your-user>
# Enter password when prompted, then exit with !quit

# Alternatively, edit ~/.snowsql/config directly:
# [connections.smdh]
# accountname = <your-account>
# username = <your-user>
# password = <your-password>
```

Then deploy the infrastructure:

```bash
cd infrastructure/snowflake/scripts

# Set credentials for scripts
export SNOWFLAKE_ACCOUNT="your-account"
export SNOWFLAKE_USER="your-user"
export SNOWSQL_PWD="your-password"

# Deploy core infrastructure
./snowflake.sh deploy

# Verify deployment
./snowflake.sh status
```

### Step 4: Configure Kinesis Integration

```bash
# Get AWS IAM role details from Terraform output
cd infrastructure/terraform
terraform output snowflake_kinesis_role_arn

# Configure Snowflake to read from Kinesis
cd infrastructure/snowflake/scripts
./setup_kinesis_integration.sh
```

### Step 5: Onboard Your First Tenant

```bash
cd infrastructure/snowflake/scripts

# Create tenant infrastructure
./onboard_tenant.sh \
  --tenant-id mycompany \
  --tenant-name "My Company Ltd" \
  --num-sites 2 \
  --contact-email alerts@mycompany.com
```

### Step 6: Configure Gateway

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

3. Check Kinesis stream:
   ```bash
   aws kinesis describe-stream --stream-name smdh-sensor-data-stream
   ```

4. Verify Snowflake pipe status:
   ```sql
   SELECT SYSTEM$PIPE_STATUS('pipe_name');
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
