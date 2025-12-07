# SMDH Core Infrastructure Deployment Guide

## Overview

This guide provides step-by-step instructions for deploying the Smart Manufacturing Data Hub (SMDH) core infrastructure. The platform enables multi-tenant IoT data ingestion from manufacturing sensors through AWS IoT Core and Kinesis into Snowflake for analytics.

**Target Audience:** Platform engineers and DevOps personnel responsible for the initial infrastructure deployment.

**Time Required:** Approximately 2-3 hours for complete setup.

---

## Architecture Summary

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         SMDH DATA FLOW ARCHITECTURE                          │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────────────────────┐  │
│  │ IoT Devices  │───▶│ AWS IoT Core │───▶│ Kinesis Data Stream          │  │
│  │ (MQTT)       │    │ (Rules)      │    │ (Per-tenant streams)         │  │
│  └──────────────┘    └──────────────┘    └──────────────┬───────────────┘  │
│                                                         │                   │
│                                                         ▼                   │
│                              ┌───────────────────────────────────────────┐  │
│                              │     SNOWFLAKE OPENFLOW                    │  │
│                              │  ┌─────────────────────────────────────┐  │  │
│                              │  │  Deployment: smdh-openflow-deployment│  │  │
│                              │  │  Runtime: smdh-kinesis-runtime       │  │  │
│                              │  └─────────────────────────────────────┘  │  │
│                              └───────────────┬───────────────────────────┘  │
│                                              │                              │
│                    ┌─────────────────────────┼─────────────────────────┐    │
│                    ▼                         ▼                         ▼    │
│   ┌────────────────────────┐ ┌────────────────────────┐ ┌────────────────┐ │
│   │ SMDH_TENANT_ACME       │ │ SMDH_TENANT_XYZ        │ │ Additional     │ │
│   │ .RAW.SENSOR_READINGS   │ │ .RAW.SENSOR_READINGS   │ │ Tenant DBs     │ │
│   └────────────────────────┘ └────────────────────────┘ └────────────────┘ │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Key Components

| Component | Purpose | Location |
|-----------|---------|----------|
| **AWS IoT Core** | MQTT broker for device connectivity | AWS eu-west-2 |
| **Kinesis Data Streams** | Real-time data buffering (per-tenant) | AWS eu-west-2 |
| **IAM User** | Access keys for Snowflake OpenFlow | AWS IAM |
| **DynamoDB Tables** | KCL checkpoint storage (auto-created) | AWS DynamoDB |
| **Snowflake Infrastructure DB** | Platform metadata and tenant registry | Snowflake |
| **Snowflake Openflow** | Native Kinesis ingestion | Snowflake |
| **External Access Integration** | Network egress for AWS connectivity | Snowflake |
| **Tenant Databases** | Isolated data storage per tenant | Snowflake |

---

## Deployment Sequence

The deployment follows this sequence:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  PHASE 1: PREREQUISITES                                                     │
│  • Install required tools (AWS CLI, Terraform, SnowSQL)                     │
│  • Configure credentials                                                    │
│  • Create Terraform state storage                                           │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  PHASE 2: AWS CORE INFRASTRUCTURE (Terraform)                               │
│  • IoT Core (thing types, logging)                                          │
│  • IAM roles for Snowflake access                                           │
│  • CloudWatch monitoring                                                    │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  PHASE 3: SNOWFLAKE CORE INFRASTRUCTURE (SQL Scripts)                       │
│  • Infrastructure database                                                  │
│  • Shared resources (warehouse, roles)                                      │
│  • Openflow connector configuration                                         │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  PHASE 4: OPENFLOW UI CONFIGURATION (Snowsight - One-Time)                  │
│  • Create Openflow Deployment                                               │
│  • Create Openflow Runtime                                                  │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  PHASE 5: TENANT ONBOARDING (Per Tenant)                                    │
│  • See: Tenant_Onboarding_Guide.md                                          │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Phase 1: Prerequisites

### 1.1 Required Tools

Install the following tools on your workstation:

| Tool | Version | Installation |
|------|---------|--------------|
| AWS CLI | v2.x | `brew install awscli` or [AWS documentation](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html) |
| Terraform | v1.5+ | `brew install terraform` or [Terraform downloads](https://www.terraform.io/downloads) |
| SnowSQL | Latest | `brew install snowflake-snowsql` or [Snowflake documentation](https://docs.snowflake.com/en/user-guide/snowsql-install-config) |
| jq | Latest | `brew install jq` (for JSON processing) |

Verify installations:

```bash
aws --version
terraform --version
snowsql --version
jq --version
```

### 1.2 AWS Configuration

Configure AWS CLI with credentials that have sufficient permissions:

```bash
aws configure
# AWS Access Key ID: <your-access-key>
# AWS Secret Access Key: <your-secret-key>
# Default region name: eu-west-2
# Default output format: json
```

**Required AWS Permissions:**
- IoT Core: Full access
- Kinesis: Full access
- IAM: Role and policy management
- CloudWatch: Logs and metrics
- S3: Terraform state storage
- DynamoDB: Terraform state locking

Verify AWS access:

```bash
aws sts get-caller-identity
```

### 1.3 Snowflake Configuration

Set environment variables for Snowflake access:

```bash
export SNOWFLAKE_ACCOUNT="your-account-identifier"
export SNOWFLAKE_USER="your-username"
export SNOWSQL_PWD="your-password"
```

> **Note:** For production environments, consider using key-pair authentication instead of password authentication.

Verify Snowflake access:

```bash
snowsql -a $SNOWFLAKE_ACCOUNT -u $SNOWFLAKE_USER -q "SELECT CURRENT_USER(), CURRENT_ROLE();"
```

### 1.4 Create Terraform State Storage

Terraform requires remote state storage for team collaboration and state locking.

```bash
# Create S3 bucket for state storage
aws s3 mb s3://smdh-terraform-state --region eu-west-2

# Enable versioning (recommended)
aws s3api put-bucket-versioning \
  --bucket smdh-terraform-state \
  --versioning-configuration Status=Enabled \
  --region eu-west-2

# Create DynamoDB table for state locking
aws dynamodb create-table \
  --table-name smdh-terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region eu-west-2
```

Verify resources:

```bash
aws s3 ls s3://smdh-terraform-state
aws dynamodb describe-table --table-name smdh-terraform-locks --query 'Table.TableStatus'
```

---

## Phase 2: AWS Core Infrastructure (Terraform)

### 2.1 Navigate to Terraform Directory

```bash
cd infrastructure/terraform
```

### 2.2 Understanding the Configuration Files

The Terraform configuration is organised into **three separate variable files** for easier maintenance and separation of concerns:

```
infrastructure/terraform/
├── environments/
│   └── dev/
│       ├── 01_tags.tfvars       # Tagging and compliance values
│       ├── 02_core.tfvars       # Core infrastructure settings
│       ├── 03_tenants.tfvars    # Tenant definitions
│       └── terraform.tfvars.example  # Reference example
```

| File | Purpose | When to Modify |
|------|---------|----------------|
| `01_tags.tfvars` | Resource tags (owner, cost centre, compliance) | Rarely - only when ownership/billing changes |
| `02_core.tfvars` | AWS region, retention policies, Snowflake integration | Rarely - only for infrastructure-level changes |
| `03_tenants.tfvars` | Tenant definitions (add/remove tenants) | **Frequently** - each time a new tenant is onboarded |

### 2.3 Create Environment Configuration

Copy and configure each file from the examples:

```bash
# For development environment - copy example as reference
cp environments/dev/terraform.tfvars.example environments/dev/terraform.tfvars.example.bak
```

#### 2.3.1 Tags Configuration (`01_tags.tfvars`)

This file defines all resource tagging for compliance and cost tracking:

```hcl
# environments/dev/01_tags.tfvars

# ========================================
# MANDATORY TAGS (Required for deployment)
# ========================================

owner       = "Platform-Team"          # Team responsible for the resources
cost_center = "ENG-SMDH-001"           # Cost centre for billing
deployed_by = "your-email@company.com" # Deployer's email

# ========================================
# Compliance and Classification
# ========================================

data_classification    = "Internal"    # Internal, Confidential, Public
compliance_requirement = "None"        # GDPR, SOC2, None
backup_policy          = "Daily"       # Backup frequency

# ========================================
# Business and Operational
# ========================================

business_unit    = "Engineering"       # Business unit
application_name = "SMDH"              # Application name
service_tier     = "Medium"            # Low, Medium, High, Critical

# ========================================
# Additional Tags
# ========================================

tags = {
  Purpose     = "Development"
  Terraform   = "true"
  GitRepo     = "smdh"
  Provisioner = "Your Name"
}
```

#### 2.3.2 Core Configuration (`02_core.tfvars`)

This file defines core infrastructure settings:

```hcl
# environments/dev/02_core.tfvars

# ========================================
# AWS Configuration
# ========================================

aws_region   = "eu-west-2"
environment  = "dev"
project_name = "smdh"

# ========================================
# Retention Settings
# ========================================

log_retention_days      = 30           # CloudWatch log retention
kinesis_retention_hours = 24           # Kinesis data retention (1-365 hours)

# ========================================
# Snowflake Integration
# ========================================
# Note: These can be left empty for initial deployment
# Update after Snowflake infrastructure is configured

snowflake_account_id  = ""             # Leave empty initially
snowflake_external_id = ""             # Leave empty initially
snowflake_region      = "eu-west-2"

# ========================================
# Alerting
# ========================================

alert_email = "ops@company.com"        # Email for CloudWatch alerts

# ========================================
# Feature Flags
# ========================================

enable_monitoring          = true      # Enable CloudWatch dashboards
enable_deletion_protection = false     # Prevent accidental deletion (true for prod)
```

#### 2.3.3 Tenants Configuration (`03_tenants.tfvars`)

This file defines tenant-specific infrastructure. **This is the file you modify when adding new tenants:**

```hcl
# environments/dev/03_tenants.tfvars

# ============================================================================
# ADDING NEW TENANTS:
# 1. Add a new block to the tenants map below
# 2. Run: terraform plan -var-file=environments/dev/01_tags.tfvars \
#                        -var-file=environments/dev/02_core.tfvars \
#                        -var-file=environments/dev/03_tenants.tfvars
# 3. Review the plan, then apply
# 4. Complete Snowflake tenant setup (see Tenant_Onboarding_Guide.md)
# 5. Configure Kinesis connector in Snowsight UI
#
# REMOVING TENANTS:
# 1. Remove or comment out the tenant block below
# 2. Run terraform plan/apply
# 3. Note: This only removes AWS resources. Snowflake cleanup is separate.
# ============================================================================

tenants = {

  # ----------------------------------------
  # Demo Tenant (Example)
  # ----------------------------------------
  manufacturing_demo = {
    name             = "Demo Manufacturing Corp"
    num_sites        = 5
    retention_days   = 90
    warehouse_size   = "SMALL"
    contact_email    = "ops@demo-mfg.com"
    sensors_per_site = 30
  }

  # ----------------------------------------
  # Add more tenants below using this format:
  # ----------------------------------------
  # acme_corp = {
  #   name             = "ACME Corporation"
  #   num_sites        = 3
  #   retention_days   = 90
  #   warehouse_size   = "SMALL"
  #   contact_email    = "ops@acme.com"
  #   sensors_per_site = 20
  # }

}
```

**Tenant Configuration Fields:**

| Field | Description | Example Values |
|-------|-------------|----------------|
| `name` | Display name for the tenant | `"ACME Corporation"` |
| `num_sites` | Number of manufacturing sites | `1-100` |
| `retention_days` | Data retention period | `30-365` |
| `warehouse_size` | Snowflake warehouse size | `XSMALL, SMALL, MEDIUM, LARGE` |
| `contact_email` | Primary contact email | `"ops@tenant.com"` |
| `sensors_per_site` | Expected sensors per site | `1-1000` |

> **Important:** The tenant key (e.g., `manufacturing_demo`, `acme_corp`) becomes part of resource names. Use lowercase letters, numbers, and underscores only. No hyphens or spaces.

### 2.4 Initialise Terraform

```bash
terraform init
```

Expected output:
```
Initializing the backend...
Successfully configured the backend "s3"!

Initializing provider plugins...
- Finding hashicorp/aws versions matching "~> 5.0"...
- Installing hashicorp/aws v5.x.x...

Terraform has been successfully initialized!
```

### 2.5 Review the Execution Plan

**IMPORTANT:** All three tfvars files must be specified in order:

```bash
terraform plan \
  -var-file=environments/dev/01_tags.tfvars \
  -var-file=environments/dev/02_core.tfvars \
  -var-file=environments/dev/03_tenants.tfvars
```

Review the plan carefully. The core infrastructure creates:
- IoT Core thing types (LoRaWAN Gateway, DevTank OSM)
- IAM role for Snowflake Openflow access
- CloudWatch log groups and dashboards
- Kinesis streams for each tenant defined in `03_tenants.tfvars`

### 2.6 Apply the Configuration

```bash
terraform apply \
  -var-file=environments/dev/01_tags.tfvars \
  -var-file=environments/dev/02_core.tfvars \
  -var-file=environments/dev/03_tenants.tfvars
```

Type `yes` when prompted to confirm.

> **Tip:** Create a shell alias for frequently used commands:
> ```bash
> alias tf-dev='terraform -var-file=environments/dev/01_tags.tfvars \
>   -var-file=environments/dev/02_core.tfvars \
>   -var-file=environments/dev/03_tenants.tfvars'
> # Usage: tf-dev plan, tf-dev apply, tf-dev destroy
> ```

### 2.8 Capture Outputs

After successful deployment, capture the outputs for Snowflake configuration:

```bash
# Get the IAM role ARN for Snowflake
terraform output snowflake_iam_role_arn

# Get complete Openflow configuration
terraform output -json openflow_aws_credentials_config

# Get IoT endpoint
terraform output iot_endpoint
```

Save these values; they are required for Snowflake Openflow configuration.

### 2.9 Verify AWS Resources

```bash
# Check IoT endpoint
aws iot describe-endpoint --endpoint-type iot:Data-ATS --region eu-west-2

# Check IAM role
aws iam get-role --role-name smdh-snowflake-openflow-role

# Check CloudWatch log groups
aws logs describe-log-groups --log-group-name-prefix /aws/iot/smdh --region eu-west-2
```

---

## Phase 3: Snowflake Core Infrastructure (SQL Scripts)

### 3.1 Navigate to Snowflake Directory

```bash
cd infrastructure/snowflake/sql/core
```

### 3.2 Run Infrastructure Setup Script

This script creates the central infrastructure database, tenant registry, and monitoring tables.

```bash
snowsql -a $SNOWFLAKE_ACCOUNT -u $SNOWFLAKE_USER \
  -r ACCOUNTADMIN \
  -f 01_infrastructure_setup.sql
```

**Resources Created:**
- Database: `SMDH_INFRASTRUCTURE`
- Schemas: `tenant_configs`, `monitoring`, `audit`
- Tables: `tenants`, `sites`, `devices`, `tenant_users`
- Monitoring tables: `ingestion_metrics`, `task_execution_log`, `alerts`
- Audit tables: `user_access_log`, `data_modification_log`
- Roles: `smdh_infrastructure_admin`, `smdh_monitoring`
- Warehouse: `SMDH_WH`

Verify:

```bash
snowsql -a $SNOWFLAKE_ACCOUNT -u $SNOWFLAKE_USER -r ACCOUNTADMIN \
  -q "SHOW DATABASES LIKE 'smdh_%';"
```

### 3.3 Run Shared Resources Script

This script creates platform-wide roles, service accounts, and monitoring views.

```bash
snowsql -a $SNOWFLAKE_ACCOUNT -u $SNOWFLAKE_USER \
  -r ACCOUNTADMIN \
  -f 02_shared_resources.sql
```

**Resources Created:**
- Roles: `smdh_tenant_operator`, `smdh_data_engineer`, `smdh_analytics_user`
- Service account: `smdh_automation_svc`
- Views: `v_warehouse_utilization`, `v_warehouse_state`, `v_daily_costs`

Verify:

```bash
snowsql -a $SNOWFLAKE_ACCOUNT -u $SNOWFLAKE_USER -r ACCOUNTADMIN \
  -q "SHOW ROLES LIKE 'smdh_%';"
```

### 3.4 Run Openflow Connector Script

This script configures Snowflake Openflow for Kinesis integration.

```bash
snowsql -a $SNOWFLAKE_ACCOUNT -u $SNOWFLAKE_USER \
  -r ACCOUNTADMIN \
  -f 03_openflow_connector.sql
```

**Resources Created:**
- Database: `SMDH_OPENFLOW` (with image repository)
- Roles: `OPENFLOW_ADMIN`, `OPENFLOW_RUNTIME_ROLE_KINESIS`
- Network Rule: `OPENFLOW_AWS_EU_WEST_2_RULE`
- External Access Integration: `OPENFLOW_AWS_EAI`
- Table: `openflow_connectors` (connector tracking)
- Stored Procedure: `sp_grant_openflow_tenant_access`
- Views: `v_openflow_connector_status`, `v_openflow_health_summary`

Verify:

```bash
snowsql -a $SNOWFLAKE_ACCOUNT -u $SNOWFLAKE_USER -r ACCOUNTADMIN \
  -q "SHOW ROLES LIKE '%OPENFLOW%';"

snowsql -a $SNOWFLAKE_ACCOUNT -u $SNOWFLAKE_USER -r ACCOUNTADMIN \
  -q "SHOW EXTERNAL ACCESS INTEGRATIONS LIKE 'OPENFLOW%';"
```

---

## Phase 4: Openflow UI Configuration (Snowsight)

Openflow Deployments and Runtimes cannot be created via SQL; they must be configured through the Snowsight user interface. This is a one-time setup.

### 4.1 Create Openflow Deployment

1. Log in to **Snowsight** (https://app.snowflake.com)
2. Navigate to **Ingestion** → **Openflow**
3. Click **Create Deployment**
4. Configure:
   - **Name:** `smdh-openflow-deployment`
   - **Type:** Snowflake Deployment (managed)
5. Click **Create**
6. Wait 15-20 minutes for the deployment to reach **Active** status

### 4.2 Create Openflow Runtime

1. Within your deployment (`smdh-openflow-deployment`), click **Create Runtime**
2. Configure:
   - **Name:** `smdh-kinesis-runtime`
   - **Role:** `OPENFLOW_RUNTIME_ROLE_KINESIS`
   - **Warehouse:** `SMDH_WH`
   - **External Access Integration:** `OPENFLOW_AWS_EAI`
3. Click **Create**
4. Wait 5-10 minutes for the runtime to reach **Active** status

> **Important: Runtime Initialization Timing**
>
> After the runtime shows **Active** status, it still needs additional time (2-3 minutes) to fully initialize internally. During this time, the runtime container must:
> - Connect to Snowflake and establish session tokens
> - Initialize the KCL (Kinesis Consumer Library) lease coordination
> - Register with DynamoDB for checkpointing
> - Establish Kinesis shard iterators
>
> **If using `LATEST` stream position:** Any data sent to Kinesis before the runtime completes initialization will be skipped. Wait until you see logs like `"This node has been elected Primary Node"` and `"Node connected"` in the runtime before sending test data.
>
> **Recommendation:** After creating or restarting a runtime, wait 2-3 minutes after it shows Active before sending test data to ensure reliable data flow.

### 4.3 Critical OpenFlow Configuration Notes

Before configuring any Kinesis connector, be aware of these critical requirements discovered during implementation:

| Configuration | Correct Value | Wrong Value (will fail) | Error if Wrong |
|--------------|---------------|-------------------------|----------------|
| **AWS Authentication** | IAM Access Keys | Role Assumption | `Access Denied` |
| **Consumer Type** | `Shared Throughput` | `Enhanced Fan-Out` | `InterruptedException`, no data flows |
| **SF Auth Strategy** | `SNOWFLAKE_SESSION_TOKEN` | `KEY_PAIR` | `Private Key not configured` |
| **Metrics Publishing** | `DISABLED` | `None` | Validation error |
| **StandardPrivateKeyService** | Disabled/deleted | Enabled | `Private Key not configured` |
| **External Access Integration** | Attached to Runtime | Not attached | `UnknownHostException: dynamodb.*.amazonaws.com` |
| **Initial Stream Position** | `LATEST` or `TRIM_HORIZON` | N/A | `LATEST` = new data only; `TRIM_HORIZON` = all historical data |

#### External Access Integration (EAI) Requirement

The External Access Integration (`OPENFLOW_AWS_EAI`) **must be attached to the Runtime** for network connectivity. This is required for:
- Kinesis stream access
- DynamoDB checkpoint table operations
- CloudWatch metrics (if enabled)

Without EAI, you will see errors like:
```
UnknownHostException: dynamodb.eu-west-2.amazonaws.com
```

**Note:** EAI is for network egress (allowing Snowflake to reach AWS endpoints), NOT for authentication. Authentication uses IAM Access Keys.

#### Initial Stream Position Behaviour

The `Kinesis Initial Stream Position` setting determines where the connector starts reading:

| Setting | Behaviour | Use Case |
|---------|-----------|----------|
| `LATEST` | Read only new records arriving after connector starts | Normal operation, fresh deployments |
| `TRIM_HORIZON` | Read all available records from the beginning | Backfill, recovery scenarios |

**Important:** If you restart the connector and data was sent while it was stopped, that data will NOT be processed if using `LATEST`. The connector's checkpoint (stored in DynamoDB) will be at `LATEST`, skipping any backlog.

To process historical data:
1. Stop the connector
2. Delete the DynamoDB checkpoint table (e.g., `smdh-openflow-{tenant_id}`)
3. Change `Kinesis Initial Stream Position` to `TRIM_HORIZON`
4. Restart the connector

### 4.4 Create IAM User for OpenFlow (Access Keys Required)

**IMPORTANT:** Snowflake OpenFlow Kinesis connector **only supports IAM Access Key authentication**. IAM Role assumption is NOT supported.

Create a dedicated IAM user:

```bash
# Create IAM user for OpenFlow
aws iam create-user --user-name smdh-openflow-kinesis-user --region eu-west-2

# Get AWS Account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Create policy document
cat > /tmp/openflow-kinesis-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "KinesisReadAccess",
      "Effect": "Allow",
      "Action": [
        "kinesis:DescribeStream",
        "kinesis:DescribeStreamSummary",
        "kinesis:GetRecords",
        "kinesis:GetShardIterator",
        "kinesis:ListShards",
        "kinesis:ListStreams",
        "kinesis:SubscribeToShard",
        "kinesis:RegisterStreamConsumer",
        "kinesis:DeregisterStreamConsumer",
        "kinesis:DescribeStreamConsumer",
        "kinesis:ListStreamConsumers"
      ],
      "Resource": "arn:aws:kinesis:eu-west-2:${AWS_ACCOUNT_ID}:stream/smdh-*"
    },
    {
      "Sid": "KinesisListAccess",
      "Effect": "Allow",
      "Action": [
        "kinesis:ListStreams",
        "kinesis:ListTagsForStream"
      ],
      "Resource": "*"
    },
    {
      "Sid": "DynamoDBKCLAccess",
      "Effect": "Allow",
      "Action": [
        "dynamodb:CreateTable",
        "dynamodb:UpdateTable",
        "dynamodb:DeleteTable",
        "dynamodb:DescribeTable",
        "dynamodb:DescribeTimeToLive",
        "dynamodb:UpdateTimeToLive",
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:UpdateItem",
        "dynamodb:DeleteItem",
        "dynamodb:Scan",
        "dynamodb:Query",
        "dynamodb:BatchGetItem",
        "dynamodb:BatchWriteItem"
      ],
      "Resource": "arn:aws:dynamodb:eu-west-2:${AWS_ACCOUNT_ID}:table/smdh-openflow-*"
    },
    {
      "Sid": "DynamoDBKCLListAccess",
      "Effect": "Allow",
      "Action": ["dynamodb:ListTables"],
      "Resource": "*"
    },
    {
      "Sid": "CloudWatchMetricsAccess",
      "Effect": "Allow",
      "Action": ["cloudwatch:PutMetricData"],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "cloudwatch:namespace": "SMDH/Openflow"
        }
      }
    }
  ]
}
EOF

# Attach policy to user
aws iam put-user-policy \
  --user-name smdh-openflow-kinesis-user \
  --policy-name smdh-openflow-kinesis-policy \
  --policy-document file:///tmp/openflow-kinesis-policy.json

# Create access keys - SAVE THESE SECURELY
aws iam create-access-key --user-name smdh-openflow-kinesis-user
```

**Store the Access Key ID and Secret Access Key securely** (e.g., AWS Secrets Manager, 1Password). You will need these when configuring the Kinesis connector.

> **Note:** If using Terraform, the IAM user is created automatically by the IAM module (`terraform/modules/iam/main.tf`). Retrieve credentials from Terraform outputs or AWS Secrets Manager.

#### Required IAM Permissions Explained

| Permission | Purpose |
|------------|---------|
| `kinesis:GetRecords`, `GetShardIterator` | Read data from the stream |
| `kinesis:DescribeStream*`, `ListShards` | Discover stream structure |
| `kinesis:*StreamConsumer` | For enhanced fan-out (if used) |
| `dynamodb:CreateTable`, `UpdateTable` | Create/modify KCL checkpoint tables |
| `dynamodb:*Item`, `Scan`, `Query` | Read/write checkpoint data |
| `dynamodb:*TimeToLive` | Manage checkpoint TTL settings |
| `cloudwatch:PutMetricData` | Optional: publish connector metrics |

> **Critical:** The `dynamodb:UpdateTable` and `dynamodb:UpdateTimeToLive` permissions are required for KCL lease management. Missing these causes connector failures with errors like `not authorized to perform: dynamodb:UpdateTable`.

---

## Phase 5: Verification

### 5.1 Verify AWS Infrastructure

```bash
# Check IoT thing types
aws iot list-thing-types --region eu-west-2

# Check IAM role trust policy
aws iam get-role --role-name smdh-snowflake-openflow-role \
  --query 'Role.AssumeRolePolicyDocument'

# Check CloudWatch dashboard
aws cloudwatch list-dashboards --region eu-west-2
```

### 5.2 Verify Snowflake Infrastructure

```bash
# Check databases
snowsql -a $SNOWFLAKE_ACCOUNT -u $SNOWFLAKE_USER -r ACCOUNTADMIN \
  -q "SHOW DATABASES LIKE 'smdh_%' OR LIKE 'SMDH_%';"

# Check warehouse
snowsql -a $SNOWFLAKE_ACCOUNT -u $SNOWFLAKE_USER -r ACCOUNTADMIN \
  -q "SHOW WAREHOUSES LIKE 'SMDH%';"

# Check Openflow integration
snowsql -a $SNOWFLAKE_ACCOUNT -u $SNOWFLAKE_USER -r ACCOUNTADMIN \
  -q "SHOW EXTERNAL ACCESS INTEGRATIONS;"

# Check monitoring views
snowsql -a $SNOWFLAKE_ACCOUNT -u $SNOWFLAKE_USER -r ACCOUNTADMIN \
  -q "SELECT * FROM smdh_infrastructure.monitoring.v_warehouse_state;"
```

### 5.3 Verify Openflow Status (Snowsight)

1. Navigate to **Ingestion** → **Openflow**
2. Confirm `smdh-openflow-deployment` shows **Active** status
3. Confirm `smdh-kinesis-runtime` shows **Active** status

---

## Post-Deployment Checklist

Before proceeding to tenant onboarding, verify all items:

| Check | Command/Action | Expected Result |
|-------|----------------|-----------------|
| AWS CLI configured | `aws sts get-caller-identity` | Account ID displayed |
| Terraform state | `terraform state list` | Resources listed |
| IoT endpoint available | `aws iot describe-endpoint --endpoint-type iot:Data-ATS` | Endpoint URL returned |
| IAM role created | `aws iam get-role --role-name smdh-snowflake-openflow-role` | Role details returned |
| SMDH_INFRASTRUCTURE database | `SHOW DATABASES LIKE 'smdh_infrastructure';` | Database exists |
| SMDH_WH warehouse | `SHOW WAREHOUSES LIKE 'SMDH_WH';` | Warehouse running |
| OPENFLOW_AWS_EAI integration | `SHOW EXTERNAL ACCESS INTEGRATIONS;` | Integration enabled |
| Openflow deployment | Snowsight UI | Status: Active |
| Openflow runtime | Snowsight UI | Status: Active |

---

## Next Steps: Tenant Onboarding

With the core infrastructure deployed, you can now onboard tenants. Each tenant receives:

- **AWS Resources:**
  - Dedicated Kinesis Data Stream
  - IoT Rule routing data to the stream
  - IoT Thing Groups for device management
  - Billing Group for cost tracking

- **Snowflake Resources:**
  - Dedicated tenant database
  - Schemas: RAW, NORMALIZED, AGGREGATED, ANALYTICS
  - Tables for sensor data storage
  - Streams and tasks for data processing
  - Dynamic tables for real-time analytics
  - Tenant-specific roles

**See:** [Tenant_Onboarding_Guide.md](Tenant_Onboarding_Guide.md) for detailed tenant onboarding instructions.

**Quick Start:**

```bash
cd infrastructure/scripts

./onboard_tenant_full.sh \
  --tenant-id acme_corp \
  --tenant-name "ACME Corporation" \
  --num-sites 5 \
  --contact-email ops@acme.com
```

---

## Troubleshooting

### Terraform Issues

**Issue: Backend initialisation fails**

```bash
# Verify S3 bucket exists
aws s3 ls s3://smdh-terraform-state

# Verify DynamoDB table exists
aws dynamodb describe-table --table-name smdh-terraform-locks
```

**Issue: IAM permissions insufficient**

Ensure your AWS credentials have the required permissions. Consider using an admin role for initial deployment.

### Snowflake Issues

**Issue: ACCOUNTADMIN role not available**

```bash
# Check available roles
snowsql -q "SHOW ROLES;"

# Request ACCOUNTADMIN access from your Snowflake administrator
```

**Issue: Warehouse not starting**

```bash
# Check warehouse state
snowsql -q "SHOW WAREHOUSES LIKE 'SMDH_WH';"

# Resume warehouse
snowsql -q "ALTER WAREHOUSE SMDH_WH RESUME;"
```

### Openflow Issues

**Issue: External Access Integration not working**

1. Verify network rule exists:
   ```sql
   USE DATABASE SMDH_OPENFLOW;
   SHOW NETWORK RULES;
   ```

2. Verify integration is enabled:
   ```sql
   SHOW EXTERNAL ACCESS INTEGRATIONS LIKE 'OPENFLOW%';
   ```

**Issue: Runtime not starting**

1. Check runtime logs in Snowsight
2. Verify role has correct grants
3. Ensure warehouse is available

**Issue: Connector running but no data flowing (0 bytes In/Out)**

This is typically caused by runtime initialization timing. Symptoms:
- Processors show green "running" state with task counts incrementing
- In/Out counters remain at 0 bytes
- No errors visible in bulletins
- AWS CloudWatch shows no `GetRecords` activity

**Root Cause:** The runtime needs time to fully initialize after creation or restart. With `LATEST` stream position, data sent before initialization completes is missed.

**Solution:**

1. Check runtime logs for initialization messages:
   - Look for: `"This node has been elected Primary Node"`
   - Look for: `"Received first heartbeat from connecting node. Node connected."`

2. If no such messages appear, restart the runtime:
   - Stop all connectors in the runtime
   - Stop the runtime
   - Wait 30 seconds
   - Start the runtime
   - Wait 2-3 minutes for full initialization
   - Start the connectors
   - Send test data AFTER initialization completes

3. To verify AWS connectivity, check if GetRecords calls are being made:
   ```bash
   aws cloudwatch get-metric-statistics \
     --namespace AWS/Kinesis \
     --metric-name GetRecords.Records \
     --dimensions Name=StreamName,Value=smdh-{tenant_id}-stream \
     --start-time $(date -u -v-10M +%Y-%m-%dT%H:%M:%SZ) \
     --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
     --period 60 --statistics Sum --region eu-west-2
   ```

4. If `GetRecords` shows no datapoints, the connector is not connecting to Kinesis at all - check IAM credentials and EAI configuration.

**Issue: Data was sent but not appearing in Snowflake**

If using `LATEST` stream position, data sent before the connector was fully initialized is skipped. Options:

1. **Send new data** while the connector is running - it will be processed immediately
2. **Backfill historical data:**
   - Stop the connector
   - Delete DynamoDB checkpoint tables:
     ```bash
     aws dynamodb delete-table --table-name smdh-openflow-{tenant_id} --region eu-west-2
     aws dynamodb delete-table --table-name smdh-openflow-{tenant_id}-CoordinatorState --region eu-west-2
     aws dynamodb delete-table --table-name smdh-openflow-{tenant_id}-WorkerMetricStats --region eu-west-2
     ```
   - Change `Kinesis Initial Stream Position` to `TRIM_HORIZON` in the connector config
   - Restart the connector - it will process all available data from the beginning of the stream

---

## Platform Teardown

If you need to completely remove the SMDH platform, follow these steps in order.

> **Warning:** This permanently destroys all infrastructure and data. Ensure you have backups if required.

### Step 1: Remove All Tenants First

Before removing core infrastructure, offboard all tenants using the Tenant_Onboarding_Guide.md offboarding procedure.

### Step 2: Stop and Remove OpenFlow

1. Navigate to **Snowsight** → **Ingestion** → **Openflow**
2. Stop all connectors in the runtime
3. Delete all connectors
4. Delete the runtime (`smdh-kinesis-runtime`)
5. Delete the deployment (`smdh-openflow-deployment`)

### Step 3: Delete IAM User for OpenFlow

The IAM user created for OpenFlow Kinesis access must be deleted manually:

```bash
# List and delete access keys
aws iam list-access-keys --user-name smdh-openflow-kinesis-user
aws iam delete-access-key \
  --user-name smdh-openflow-kinesis-user \
  --access-key-id <ACCESS_KEY_ID>

# Delete inline policy
aws iam delete-user-policy \
  --user-name smdh-openflow-kinesis-user \
  --policy-name smdh-openflow-kinesis-policy

# Delete user
aws iam delete-user --user-name smdh-openflow-kinesis-user
```

### Step 4: Clean Up DynamoDB Checkpoint Tables

OpenFlow creates DynamoDB tables for KCL checkpointing. Delete these:

```bash
# List SMDH-related tables
aws dynamodb list-tables --region eu-west-2 --query 'TableNames[?contains(@, `smdh`)]'

# Delete each checkpoint table
aws dynamodb delete-table --table-name <table-name> --region eu-west-2
```

### Step 5: Destroy Terraform Infrastructure

```bash
cd infrastructure/terraform

terraform destroy \
  -var-file=environments/dev/01_tags.tfvars \
  -var-file=environments/dev/02_core.tfvars \
  -var-file=environments/dev/03_tenants.tfvars
```

Type `yes` when prompted.

### Step 6: Snowflake Cleanup

```sql
-- Drop infrastructure database
DROP DATABASE IF EXISTS SMDH_INFRASTRUCTURE;

-- Drop OpenFlow database
DROP DATABASE IF EXISTS SMDH_OPENFLOW;

-- Drop warehouse
DROP WAREHOUSE IF EXISTS SMDH_WH;

-- Drop roles (in dependency order)
DROP ROLE IF EXISTS OPENFLOW_RUNTIME_ROLE_KINESIS;
DROP ROLE IF EXISTS OPENFLOW_ADMIN;
DROP ROLE IF EXISTS smdh_monitoring;
DROP ROLE IF EXISTS smdh_analytics_user;
DROP ROLE IF EXISTS smdh_data_engineer;
DROP ROLE IF EXISTS smdh_tenant_operator;
DROP ROLE IF EXISTS smdh_infrastructure_admin;
```

### Step 7: Remove Terraform State Storage (Optional)

If you want to completely remove all traces:

```bash
# Empty and delete S3 bucket
aws s3 rm s3://smdh-terraform-state --recursive
aws s3 rb s3://smdh-terraform-state

# Delete DynamoDB lock table
aws dynamodb delete-table --table-name smdh-terraform-locks --region eu-west-2
```

---

## Support and Resources

### Documentation

| Document | Purpose | Location |
|----------|---------|----------|
| Tenant Onboarding Guide | Per-tenant setup | `infrastructure/deployment/Tenant_Onboarding_Guide.md` |
| Terraform README | AWS infrastructure details | `infrastructure/terraform/README.md` |
| Snowflake README | Snowflake setup details | `infrastructure/snowflake/README.md` |
| Architecture Design | System architecture | `docs/detailed-design/SMDH AWS design.md` |

### Useful Commands

```bash
# Check Snowflake infrastructure status
cd infrastructure/snowflake/scripts
./snowflake.sh status

# Validate tenant setup
cd infrastructure/scripts
./validate_tenant.sh --tenant-id <tenant_id>

# Check system health
./check_system_health.sh --tenant-id <tenant_id>
```

---

## Appendix: Configuration Reference

### Terraform Configuration Files

The configuration is split across three files for maintainability:

#### A.1 `01_tags.tfvars` - Resource Tagging

| Variable | Description | Required |
|----------|-------------|----------|
| `owner` | Team responsible for resources | Yes |
| `cost_center` | Cost centre code for billing | Yes |
| `deployed_by` | Email of the deployer | Yes |
| `data_classification` | Data sensitivity level | Yes |
| `compliance_requirement` | Regulatory requirements (GDPR, SOC2, None) | Yes |
| `backup_policy` | Backup frequency | Yes |
| `business_unit` | Business unit name | Yes |
| `application_name` | Application identifier | Yes |
| `service_tier` | Service criticality (Low, Medium, High, Critical) | Yes |
| `tags` | Additional custom tags (map) | No |

#### A.2 `02_core.tfvars` - Core Infrastructure

| Variable | Description | Default |
|----------|-------------|---------|
| `aws_region` | AWS region for deployment | `eu-west-2` |
| `environment` | Environment name (dev/staging/prod) | Required |
| `project_name` | Project name for resource naming | `smdh` |
| `log_retention_days` | CloudWatch log retention period | `30` |
| `kinesis_retention_hours` | Kinesis stream data retention | `24` |
| `snowflake_account_id` | Snowflake's AWS account ID | `""` (optional) |
| `snowflake_external_id` | External ID for role assumption | `""` (optional) |
| `snowflake_region` | Snowflake deployment region | `eu-west-2` |
| `alert_email` | Email for CloudWatch alerts | Required |
| `enable_monitoring` | Enable CloudWatch dashboards | `true` |
| `enable_deletion_protection` | Prevent accidental deletion | `false` |

#### A.3 `03_tenants.tfvars` - Tenant Definitions

| Variable | Description | Required |
|----------|-------------|----------|
| `tenants` | Map of tenant configurations | Yes |

**Tenant Map Structure:**

```hcl
tenants = {
  tenant_key = {
    name             = "Tenant Display Name"
    num_sites        = 5
    retention_days   = 90
    warehouse_size   = "SMALL"
    contact_email    = "ops@tenant.com"
    sensors_per_site = 30
  }
}
```

### Terraform Command Reference

| Action | Command |
|--------|---------|
| Initialise | `terraform init` |
| Plan | `terraform plan -var-file=environments/dev/01_tags.tfvars -var-file=environments/dev/02_core.tfvars -var-file=environments/dev/03_tenants.tfvars` |
| Apply | `terraform apply -var-file=environments/dev/01_tags.tfvars -var-file=environments/dev/02_core.tfvars -var-file=environments/dev/03_tenants.tfvars` |
| Destroy | `terraform destroy -var-file=environments/dev/01_tags.tfvars -var-file=environments/dev/02_core.tfvars -var-file=environments/dev/03_tenants.tfvars` |
| Show state | `terraform state list` |
| Get outputs | `terraform output` |

### Snowflake Objects Created

| Object Type | Name | Purpose |
|-------------|------|---------|
| Database | `SMDH_INFRASTRUCTURE` | Platform metadata |
| Database | `SMDH_OPENFLOW` | Openflow configuration |
| Warehouse | `SMDH_WH` | All SMDH workloads |
| Role | `OPENFLOW_ADMIN` | Openflow administration |
| Role | `OPENFLOW_RUNTIME_ROLE_KINESIS` | Kinesis connector runtime |
| Role | `smdh_infrastructure_admin` | Infrastructure management |
| Role | `smdh_tenant_operator` | Tenant onboarding |
| Role | `smdh_data_engineer` | ETL development |
| Role | `smdh_monitoring` | Read-only monitoring |
| Integration | `OPENFLOW_AWS_EAI` | AWS external access |

### Quick Reference: Adding a New Tenant

1. **Edit `03_tenants.tfvars`** and add tenant block:
   ```hcl
   new_tenant = {
     name             = "New Tenant Inc"
     num_sites        = 3
     retention_days   = 90
     warehouse_size   = "SMALL"
     contact_email    = "ops@newtenant.com"
     sensors_per_site = 20
   }
   ```

2. **Run Terraform:**
   ```bash
   cd infrastructure/terraform
   terraform plan -var-file=environments/dev/01_tags.tfvars \
     -var-file=environments/dev/02_core.tfvars \
     -var-file=environments/dev/03_tenants.tfvars
   terraform apply -var-file=environments/dev/01_tags.tfvars \
     -var-file=environments/dev/02_core.tfvars \
     -var-file=environments/dev/03_tenants.tfvars
   ```

3. **Complete Snowflake setup** using Tenant_Onboarding_Guide.md

4. **Configure Kinesis connector** in Snowsight UI

---

*Document Version: 1.6*
*Last Updated: 7 December 2025*
*Author: SMDH Platform Team*
