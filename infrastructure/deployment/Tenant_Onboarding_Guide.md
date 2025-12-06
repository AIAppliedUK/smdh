# SMDH Tenant Onboarding Guide

## Overview

This guide provides step-by-step instructions for onboarding new tenants to the Smart Manufacturing Data Hub (SMDH) platform. Each tenant receives isolated AWS and Snowflake resources for secure, multi-tenant data processing.

**Prerequisites:** The core infrastructure must be deployed before onboarding tenants. See [Core_Infrastructure_Deployment_Guide.md](Core_Infrastructure_Deployment_Guide.md).

**Target Audience:** Platform operators responsible for tenant lifecycle management.

**Time Required:** Approximately 15-30 minutes per tenant.

---

## Architecture Pattern

Each tenant receives dedicated resources to ensure complete data isolation:

```
Tenant A Devices                          Tenant B Devices
      │                                         │
      ▼                                         ▼
┌─────────────────┐                   ┌─────────────────┐
│ AWS IoT Core    │                   │ AWS IoT Core    │
│ Topic: smdh/    │                   │ Topic: smdh/    │
│ tenant_a/...    │                   │ tenant_b/...    │
└────────┬────────┘                   └────────┬────────┘
         │                                     │
         ▼                                     ▼
┌─────────────────┐                   ┌─────────────────┐
│ Kinesis Stream  │                   │ Kinesis Stream  │
│ smdh-tenant_a   │                   │ smdh-tenant_b   │
└────────┬────────┘                   └────────┬────────┘
         │                                     │
         └──────────────┬──────────────────────┘
                        │
                        ▼
              ┌─────────────────────┐
              │  Snowflake Openflow │
              │  Kinesis Connector  │
              │                     │
              │  Stream Routing:    │
              │  tenant_a → DB_A    │
              │  tenant_b → DB_B    │
              └─────────┬───────────┘
                        │
           ┌────────────┴────────────┐
           ▼                         ▼
   ┌───────────────┐         ┌───────────────┐
   │ SMDH_TENANT_  │         │ SMDH_TENANT_  │
   │ TENANT_A      │         │ TENANT_B      │
   │ .RAW.SENSOR_  │         │ .RAW.SENSOR_  │
   │ READINGS      │         │ READINGS      │
   └───────────────┘         └───────────────┘
```

### Benefits of Per-Tenant Streams

- **Complete data isolation**: Each tenant's data flows through dedicated infrastructure
- **Independent scaling**: High-volume tenants do not affect others
- **Simplified security**: IAM policies per tenant stream
- **Easy offboarding**: Delete tenant stream without affecting others
- **Compliance**: Data never co-mingles in transit

---

## What Gets Created

When you onboard a tenant, the following resources are created:

### AWS Resources

| Resource | Naming Convention | Purpose |
|----------|-------------------|---------|
| Kinesis Data Stream | `smdh-{tenant_id}-stream` | Real-time data buffering |
| IAM Role | `smdh-openflow-{tenant_id}-role` | Snowflake Openflow access |
| IoT Rule | `smdh_{tenant_id}_to_kinesis` | Route MQTT data to Kinesis |
| Thing Group | `smdh-tenant-{tenant_id}` | Hierarchical device management |
| Billing Group | `smdh-billing-{tenant_id}` | Cost tracking per tenant |

### Snowflake Resources

| Resource | Naming Convention | Purpose |
|----------|-------------------|---------|
| Database | `SMDH_TENANT_{TENANT_ID}` | Isolated tenant data storage |
| Schemas | RAW, NORMALISED, AGGREGATED, ANALYTICS | Data processing stages |
| Tables | `sensor_readings`, `sensor_metrics`, etc. | Data storage |
| Streams | CDC streams for real-time processing | Change data capture |
| Tasks | Automated ETL processing | Data transformation |
| Dynamic Tables | Real-time aggregations | Live analytics |
| Roles | Tenant-specific RBAC | Access control |

---

## Onboarding Methods

### Method 1: Automated Full Onboarding (Recommended)

The `onboard_tenant_full.sh` script automates both AWS and Snowflake resource creation.

#### Prerequisites Check

Ensure you have:
- AWS CLI configured with appropriate permissions
- SnowSQL installed with credentials set
- ACCOUNTADMIN role access in Snowflake

```bash
# Verify AWS access
aws sts get-caller-identity

# Verify Snowflake access
snowsql -a $SNOWFLAKE_ACCOUNT -u $SNOWFLAKE_USER -q "SELECT CURRENT_ROLE();"
```

#### Run the Onboarding Script

```bash
cd infrastructure/scripts

./onboard_tenant_full.sh \
  --tenant-id acme_corp \
  --tenant-name "ACME Corporation" \
  --num-sites 5 \
  --contact-email ops@acme.com
```

**Parameters:**

| Parameter | Required | Description |
|-----------|----------|-------------|
| `--tenant-id` | Yes | Unique identifier (lowercase, alphanumeric, underscores) |
| `--tenant-name` | Yes | Display name for the tenant |
| `--num-sites` | Yes | Number of manufacturing sites |
| `--contact-email` | No | Tenant contact email address |
| `--aws-region` | No | AWS region (default: eu-west-2) |
| `--shard-count` | No | Kinesis shard count (default: 2) |
| `--skip-aws` | No | Skip AWS resource creation |
| `--skip-snowflake` | No | Skip Snowflake resource creation |
| `--dry-run` | No | Show what would be done without executing |

**Example Output:**

```
╔════════════════════════════════════════════════════════════════╗
║   SMDH Full Tenant Onboarding Automation                       ║
╚════════════════════════════════════════════════════════════════╝

Configuration:
  Tenant ID:    acme_corp
  Tenant Name:  ACME Corporation
  Num Sites:    5
  AWS Region:   eu-west-2

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
▶ Checking Prerequisites
[INFO] ✓ AWS CLI installed
[INFO] ✓ AWS Account: 123456789012
[INFO] ✓ SnowSQL installed
[INFO] ✓ SNOWSQL_PWD set

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
▶ Creating Kinesis Data Stream
[INFO] Creating Kinesis stream: smdh-acme_corp-stream (2 shards)
[INFO] Waiting for stream to become active...
[INFO] ✓ Kinesis stream created and active
  ARN: arn:aws:kinesis:eu-west-2:123456789012:stream/smdh-acme_corp-stream

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
▶ Creating IAM Role for Openflow
[INFO] Creating IAM role: smdh-openflow-acme_corp-role
[INFO] ✓ IAM role created
  ARN: arn:aws:iam::123456789012:role/smdh-openflow-acme_corp-role

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
▶ Creating IoT Core Rule
[INFO] Creating IoT rule: smdh_acme_corp_to_kinesis
[INFO] ✓ IoT rule created
  Topic pattern: smdh/acme_corp/+/+

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
▶ Creating Snowflake Tenant Database
[INFO] Running Snowflake tenant onboarding script...
[INFO] ✓ Snowflake tenant database created

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
▶ Granting Openflow Access to Tenant Database
[INFO] Calling sp_grant_openflow_tenant_access...
[INFO] ✓ Granted Openflow access to database: SMDH_TENANT_ACME_CORP

╔════════════════════════════════════════════════════════════════╗
║   Tenant Onboarding Complete!                                  ║
╚════════════════════════════════════════════════════════════════╝
```

#### Complete Manual Step: Add Kinesis Connector in Snowsight

After the automated script completes, you must add the Kinesis connector in the Snowsight UI. This is the **only manual step** required per tenant.

> **IMPORTANT - Critical Configuration Requirements:**
> - **AWS Authentication:** Use IAM Access Keys only (role assumption is NOT supported per Snowflake docs)
> - **Consumer Type:** Must be `Shared Throughput` (Enhanced Fan-Out causes initialisation failures)
> - **Snowflake Auth:** Use `SNOWFLAKE_SESSION_TOKEN` for Snowflake-managed deployments

**Step-by-step:**

1. Log in to **Snowsight** (https://app.snowflake.com)
2. Navigate to **Ingestion** → **Openflow**
3. Open your runtime: `smdh-kinesis-runtime`
4. Click **Add Connector** → **Amazon Kinesis** → **Kinesis Data Streams: JSON modularized**
5. Configure **Parameter Contexts**:

**Kinesis Source Parameters:**

| Parameter | Value | Notes |
|-----------|-------|-------|
| AWS Access Key ID | `<your-access-key>` | From IAM user (NOT role assumption) |
| AWS Secret Access Key | `<your-secret-key>` | From IAM user |
| AWS Region Code | `eu-west-2` | Region where Kinesis stream is located |
| **Consumer Type** | `Shared Throughput` | **CRITICAL: NOT Enhanced Fan-Out** |
| Kinesis Application Name | `smdh-openflow-acme_corp` | Used for DynamoDB checkpoint table name |
| Kinesis Stream Name | `smdh-acme_corp-stream` | Must match exactly |
| Kinesis Initial Stream Position | `LATEST` | Or `TRIM_HORIZON` for all historical data |
| Metrics Publishing | `DISABLED` | Options: DISABLED, LOGS, CLOUDWATCH |

**Streaming Destination Parameters:**

| Parameter | Value | Notes |
|-----------|-------|-------|
| Destination Database | `SMDH_TENANT_ACME_CORP` | Must exist, case-sensitive (uppercase) |
| Destination Schema | `RAW` | Must exist, case-sensitive (uppercase) |
| **Snowflake Authentication Strategy** | `SNOWFLAKE_SESSION_TOKEN` | For Snowflake-managed deployment |
| Snowflake Account Identifier | *(leave blank)* | Only for KEY_PAIR auth |
| Snowflake Username | *(leave blank)* | Only for KEY_PAIR auth |
| Snowflake Role | `OPENFLOW_RUNTIME_ROLE_KINESIS` | Use Runtime Role |
| Snowflake Warehouse | `SMDH_WH` | |
| Iceberg Enabled | `false` | Set true only for Iceberg tables |
| Schema Evolution Enabled | `true` | Recommended for flexibility |

6. Configure **Controller Services**:
   - **Disable** `StandardPrivateKeyService` (not needed for session token auth)
   - Enable all other services in dependency order

7. Click **Create** → **Start**

8. Verify data flows through processors (check bulletins in top-right for errors)

#### Verify Landing Table Creation

OpenFlow automatically creates a destination table named after the Kinesis stream (uppercase, with hyphens preserved). Wait ~60 seconds after starting the connector, then verify:

```sql
USE DATABASE SMDH_TENANT_ACME_CORP;
SHOW TABLES LIKE 'SMDH-%' IN SCHEMA RAW;
-- Should show: "SMDH-ACME_CORP-STREAM"
```

> **Note:** The table name includes quotes because it contains hyphens. Reference it as `"SMDH-ACME_CORP-STREAM"` in SQL.

#### Deploy Data Routing Task

After the landing table exists, deploy the routing task:

```bash
cd infrastructure/snowflake/sql/tenant
snowsql -a $SNOWFLAKE_ACCOUNT -u $SNOWFLAKE_USER \
  -r ACCOUNTADMIN \
  -f 14_create_routing_task.sql \
  --variable tenant_id="acme_corp"
```

Resume the routing task:

```sql
USE DATABASE SMDH_TENANT_ACME_CORP;
ALTER TASK RAW.TASK_ROUTE_SENSOR_DATA RESUME;
```

---

### Method 2: Terraform + Snowflake Scripts (Production Recommended)

For production environments, use Terraform to manage AWS resources with proper state tracking, then use Snowflake scripts for database setup.

#### Step 1: Add Tenant to Terraform Configuration

Edit `infrastructure/terraform/environments/dev/03_tenants.tfvars`:

```hcl
tenants = {
  # ... existing tenants ...

  # Add new tenant
  acme_corp = {
    name             = "ACME Corporation"
    num_sites        = 5
    retention_days   = 90
    warehouse_size   = "SMALL"
    contact_email    = "ops@acme.com"
    sensors_per_site = 25
  }
}
```

#### Step 2: Apply Terraform Changes

```bash
cd infrastructure/terraform

# Review what will be created
terraform plan \
  -var-file=environments/dev/01_tags.tfvars \
  -var-file=environments/dev/02_core.tfvars \
  -var-file=environments/dev/03_tenants.tfvars

# Apply changes
terraform apply \
  -var-file=environments/dev/01_tags.tfvars \
  -var-file=environments/dev/02_core.tfvars \
  -var-file=environments/dev/03_tenants.tfvars
```

**AWS Resources Created by Terraform:**
- Kinesis Data Stream: `smdh-acme_corp-stream`
- IoT Topic Rule: `smdh_acme_corp_to_kinesis`
- IoT Policy: `smdh-policy-acme_corp`

#### Step 3: Run Snowflake Tenant Scripts

```bash
cd infrastructure/snowflake/scripts

./onboard_tenant.sh \
  --tenant-id acme_corp \
  --tenant-name "ACME Corporation" \
  --num-sites 5 \
  --snowflake-account $SNOWFLAKE_ACCOUNT \
  --snowflake-user $SNOWFLAKE_USER
```

#### Step 4: Configure Kinesis Connector in Snowsight

Follow the connector configuration steps in Method 1, section "Complete Manual Step: Add Kinesis Connector in Snowsight".

#### Step 5: Deploy Data Routing Task

```bash
cd infrastructure/snowflake/sql/tenant
snowsql -a $SNOWFLAKE_ACCOUNT -u $SNOWFLAKE_USER \
  -r ACCOUNTADMIN \
  -f 14_create_routing_task.sql \
  --variable tenant_id="acme_corp"
```

---

### Method 3: Manual SQL Onboarding

For custom setups or troubleshooting, run SQL scripts individually:

```bash
cd infrastructure/snowflake/sql/tenant

TENANT_ID="acme_corp"
TENANT_NAME="ACME Corporation"
AWS_REGION="eu-west-2"
NUM_SITES=5

# Step 1: Create database
snowsql -a $SNOWFLAKE_ACCOUNT -u $SNOWFLAKE_USER \
  -r ACCOUNTADMIN \
  -f 10_create_tenant_database.sql \
  --variable tenant_id="$TENANT_ID" \
  --variable tenant_name="$TENANT_NAME" \
  --variable aws_region="$AWS_REGION" \
  --variable num_sites=$NUM_SITES

# Step 2: Create schemas
snowsql -a $SNOWFLAKE_ACCOUNT -u $SNOWFLAKE_USER \
  -r ACCOUNTADMIN \
  -f 11_create_schemas.sql \
  --variable tenant_id="$TENANT_ID"

# Step 3: Create tables
snowsql -a $SNOWFLAKE_ACCOUNT -u $SNOWFLAKE_USER \
  -r ACCOUNTADMIN \
  -f 12_create_tables.sql \
  --variable tenant_id="$TENANT_ID"

# Step 4: Create streams
snowsql -a $SNOWFLAKE_ACCOUNT -u $SNOWFLAKE_USER \
  -r ACCOUNTADMIN \
  -f 13_create_streams.sql \
  --variable tenant_id="$TENANT_ID"

# Step 5: Create tasks (optional - for automated processing)
snowsql -a $SNOWFLAKE_ACCOUNT -u $SNOWFLAKE_USER \
  -r ACCOUNTADMIN \
  -f 14_create_tasks.sql \
  --variable tenant_id="$TENANT_ID"

# Step 6: Create dynamic tables (optional - for real-time analytics)
snowsql -a $SNOWFLAKE_ACCOUNT -u $SNOWFLAKE_USER \
  -r ACCOUNTADMIN \
  -f 15_create_dynamic_tables.sql \
  --variable tenant_id="$TENANT_ID"

# Step 7: Create roles
snowsql -a $SNOWFLAKE_ACCOUNT -u $SNOWFLAKE_USER \
  -r ACCOUNTADMIN \
  -f 16_create_roles.sql \
  --variable tenant_id="$TENANT_ID"

# Step 8: Create monitoring views
snowsql -a $SNOWFLAKE_ACCOUNT -u $SNOWFLAKE_USER \
  -r ACCOUNTADMIN \
  -f 17_create_monitoring.sql \
  --variable tenant_id="$TENANT_ID"
```

> **Important:** Use `--variable` syntax (not `-D` flag) for Snowflake session variables. See CLAUDE.md for details on variable naming conventions.

---

## Validation

### Automated Validation

Use the validation script to verify tenant setup:

```bash
cd infrastructure/scripts

./validate_tenant.sh --tenant-id acme_corp
```

**Validation Checks:**

| Check | Description |
|-------|-------------|
| Kinesis stream | Stream exists and is ACTIVE |
| IAM role | Role exists with correct policies |
| IoT rule | Rule exists and is enabled |
| Snowflake database | Database and schemas exist |
| Tenant registry | Tenant registered in infrastructure DB |
| Openflow access | Runtime role has correct grants |
| Connector status | Connector registered in tracking table |

### Manual Verification

#### AWS Verification

```bash
# Check Kinesis stream
aws kinesis describe-stream-summary \
  --stream-name smdh-acme_corp-stream \
  --region eu-west-2

# Check IAM role
aws iam get-role --role-name smdh-openflow-acme_corp-role

# Check IoT rule
aws iot get-topic-rule \
  --rule-name smdh_acme_corp_to_kinesis \
  --region eu-west-2
```

#### Snowflake Verification

```sql
-- Check database exists
SHOW DATABASES LIKE 'SMDH_TENANT_ACME_CORP';

-- Check schemas
USE DATABASE SMDH_TENANT_ACME_CORP;
SHOW SCHEMAS;

-- Check tables
USE SCHEMA RAW;
SHOW TABLES;

-- Check Openflow access
SHOW GRANTS TO ROLE OPENFLOW_RUNTIME_ROLE_KINESIS;
```

---

## Testing the Data Pipeline

### Send Test Message

After onboarding, test the data pipeline by sending a test message:

```bash
# Using AWS IoT test client
aws iot-data publish \
  --topic "smdh/acme_corp/site_001/sensor" \
  --payload '{"sensor_id":"TEMP_001","value":25.5,"unit":"celsius","timestamp":"'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'"}' \
  --region eu-west-2
```

Alternatively, use the test script:

```bash
cd infrastructure/scripts

./test_iot_pipeline.sh acme_corp site_001 5
```

This sends 5 test messages in UG65 gateway format.

### Verify Data in Snowflake

After sending test messages (wait 30-60 seconds for Openflow processing):

```sql
USE DATABASE SMDH_TENANT_ACME_CORP;

-- Check recent data
SELECT *
FROM raw.sensor_readings
WHERE ingestion_timestamp >= DATEADD(MINUTE, -10, CURRENT_TIMESTAMP())
ORDER BY ingestion_timestamp DESC
LIMIT 10;

-- Check record count
SELECT COUNT(*) AS total_readings
FROM raw.sensor_readings;
```

---

## MQTT Topic Structure

Devices publish to topics following this pattern:

```
smdh/{tenant_id}/{site_id}/{data_type}
```

**Examples:**
- `smdh/acme_corp/site_001/sensor-data` - Sensor readings
- `smdh/acme_corp/site_001/status` - Device status updates
- `smdh/acme_corp/site_002/alerts` - Alert notifications

The IoT rule enriches messages with metadata:
- `tenant_id` - Extracted from topic(2)
- `site_id` - Extracted from topic(3)
- `iot_timestamp` - Server-side timestamp
- `device_id` - Client ID from connection

---

## Managing Multiple Tenants

### Adding More Tenants

For each additional tenant, run the onboarding script:

```bash
./onboard_tenant_full.sh \
  --tenant-id new_tenant \
  --tenant-name "New Tenant Inc" \
  --num-sites 3
```

Then add the connector in Snowsight (repeat the manual step above).

### Multi-Tenant Connector Mapping

You can configure multiple tenants in a single Openflow connector by updating the stream-to-table mapping:

```
smdh-acme_corp-stream:SMDH_TENANT_ACME_CORP.RAW.SENSOR_READINGS,
smdh-new_tenant-stream:SMDH_TENANT_NEW_TENANT.RAW.SENSOR_READINGS
```

---

## Tenant Lifecycle Management

### Suspend a Tenant

To temporarily suspend data processing for a tenant:

```sql
-- Suspend tasks
USE DATABASE SMDH_TENANT_ACME_CORP;
CALL analytics.sp_suspend_all_tasks();

-- Update tenant status
UPDATE smdh_infrastructure.tenant_configs.tenants
SET status = 'suspended', suspended_date = CURRENT_TIMESTAMP()
WHERE tenant_id = 'acme_corp';
```

### Reactivate a Tenant

```sql
-- Resume tasks
USE DATABASE SMDH_TENANT_ACME_CORP;
CALL analytics.sp_resume_all_tasks();

-- Update tenant status
UPDATE smdh_infrastructure.tenant_configs.tenants
SET status = 'active', suspended_date = NULL
WHERE tenant_id = 'acme_corp';
```

### Offboard a Tenant

> **Warning:** This permanently deletes all tenant data. Ensure you have backups if required.

#### Step 1: Stop OpenFlow Connector

1. Navigate to **Snowsight** → **Ingestion** → **Openflow** → Runtime
2. Stop the connector for this tenant
3. Delete the connector

#### Step 2: AWS Cleanup

```bash
# Delete Kinesis stream
aws kinesis delete-stream --stream-name smdh-acme_corp-stream --region eu-west-2

# Delete IoT rule
aws iot delete-topic-rule --rule-name smdh_acme_corp_to_kinesis --region eu-west-2

# Delete IAM role and policy
aws iam delete-role-policy --role-name smdh-openflow-acme_corp-role --policy-name KinesisOpenflowAccess
aws iam delete-role --role-name smdh-openflow-acme_corp-role
```

#### Step 3: DynamoDB Cleanup (KCL Checkpoint Tables)

OpenFlow creates DynamoDB tables for Kinesis Consumer Library (KCL) checkpointing. These must be deleted manually:

```bash
# List checkpoint tables
aws dynamodb list-tables --region eu-west-2 --query 'TableNames[?contains(@, `smdh`)]'

# Delete checkpoint table for this tenant
aws dynamodb delete-table --table-name smdh-openflow-acme_corp --region eu-west-2
```

#### Step 4: Snowflake Cleanup

```sql
-- Drop tenant database
DROP DATABASE IF EXISTS SMDH_TENANT_ACME_CORP;

-- Update tenant status in registry
UPDATE smdh_infrastructure.tenant_configs.tenants
SET status = 'offboarded', offboarded_date = CURRENT_TIMESTAMP()
WHERE tenant_id = 'acme_corp';
```

---

## Monitoring and Troubleshooting

### Connector Status

```sql
-- Check connector status
SELECT *
FROM smdh_infrastructure.monitoring.v_openflow_connector_status
WHERE tenant_id = 'acme_corp';

-- Check health summary
SELECT *
FROM smdh_infrastructure.monitoring.v_openflow_health_summary;
```

### Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| No data appearing | Connector not started | Start connector in Snowsight UI |
| Permission denied | Missing grants | Run `sp_grant_openflow_tenant_access` |
| High latency | Insufficient Kinesis shards | Increase shard count |
| Stream errors | Network connectivity | Check `OPENFLOW_AWS_EAI` integration |
| Empty readings | Incorrect topic pattern | Verify IoT rule SQL matches topic structure |

### OpenFlow Connector Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| `InterruptedException` on init | Consumer Type = Enhanced Fan-Out | Change to `Shared Throughput` |
| `Access Denied` from AWS | IAM role assumption attempted | Use IAM Access Keys instead |
| `Insufficient privileges` | Missing Snowflake grants | Run `sp_grant_openflow_tenant_access()` |
| `Private Key not configured` | Wrong auth strategy | Set to `SNOWFLAKE_SESSION_TOKEN` |
| No landing table created | Connector not started | Start connector, wait 60 seconds |
| Routing task shows 0 rows | Stream consumed multiple times | Check procedure uses temp table pattern |
| DynamoDB errors | Missing `UpdateTable` permission | Add to IAM policy |

### Check Kinesis Stream Activity

```bash
# Get shard iterator
SHARD_ID=$(aws kinesis describe-stream --stream-name smdh-acme_corp-stream \
  --query 'StreamDescription.Shards[0].ShardId' --output text --region eu-west-2)

SHARD_ITERATOR=$(aws kinesis get-shard-iterator \
  --stream-name smdh-acme_corp-stream \
  --shard-id $SHARD_ID \
  --shard-iterator-type LATEST \
  --query 'ShardIterator' --output text --region eu-west-2)

# Get records (will show any messages in the last 5 minutes)
aws kinesis get-records --shard-iterator $SHARD_ITERATOR --region eu-west-2
```

### Check IoT Rule Metrics

```bash
# Check rule action failures
aws cloudwatch get-metric-statistics \
  --namespace AWS/IoT \
  --metric-name RuleActionFailure \
  --dimensions Name=RuleName,Value=smdh_acme_corp_to_kinesis \
  --start-time $(date -u -v-1H +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 300 \
  --statistics Sum \
  --region eu-west-2
```

---

## Device Certificate Management

Each device requires an X.509 certificate for MQTT authentication.

### Create Device Certificate

```bash
# Create certificate
aws iot create-keys-and-certificate \
  --set-as-active \
  --certificate-pem-outfile cert.pem \
  --private-key-outfile private.key \
  --region eu-west-2

# Note the certificate ARN from the output
CERT_ARN="arn:aws:iot:eu-west-2:123456789012:cert/abc123..."

# Attach policy to certificate
aws iot attach-policy \
  --policy-name "smdh-policy-acme_corp" \
  --target "$CERT_ARN" \
  --region eu-west-2
```

### Store Certificates

Store certificates securely in the deployment directory:

```
infrastructure/deployment/certificates/
├── acme_corp_site_001_certificate.pem
├── acme_corp_site_001_private_key.pem
└── ca/
    └── AmazonRootCA1.pem
```

Download the Amazon Root CA:

```bash
curl -o infrastructure/deployment/certificates/ca/AmazonRootCA1.pem \
  https://www.amazontrust.com/repository/AmazonRootCA1.pem
```

---

## Quick Reference: Onboarding Checklist

### Per-Tenant Setup

| Step | Task | Verified |
|------|------|----------|
| 1 | Collect tenant information (ID, name, sites, contact) | ☐ |
| 2 | Run `onboard_tenant_full.sh` script | ☐ |
| 3 | Verify AWS resources created (Kinesis, IoT rule) | ☐ |
| 4 | Verify Snowflake database created | ☐ |
| 5 | Add Kinesis connector in Snowsight UI | ☐ |
| 6 | Set Consumer Type = `Shared Throughput` (NOT Enhanced Fan-Out) | ☐ |
| 7 | Set Auth Strategy = `SNOWFLAKE_SESSION_TOKEN` | ☐ |
| 8 | Disable `StandardPrivateKeyService` controller service | ☐ |
| 9 | Start the connector | ☐ |
| 10 | Verify landing table created (wait 60s) | ☐ |
| 11 | Deploy routing task (`14_create_routing_task.sql`) | ☐ |
| 12 | Resume routing task | ☐ |
| 13 | Send test message | ☐ |
| 14 | Verify data appears in typed tables | ☐ |

### Critical Configuration Parameters

| Parameter | Correct Value | Wrong Value (will fail) |
|-----------|---------------|-------------------------|
| AWS Auth | IAM Access Keys | Role Assumption |
| Consumer Type | `Shared Throughput` | Enhanced Fan-Out |
| SF Auth Strategy | `SNOWFLAKE_SESSION_TOKEN` | `KEY_PAIR` |
| Schema Permissions | `USAGE` + `CREATE TABLE` | `USAGE` only |

---

## Quick Reference Commands

### Environment Variables

```bash
export AWS_REGION="eu-west-2"
export SNOWFLAKE_ACCOUNT="your-account"
export SNOWFLAKE_USER="your-user"
export SNOWSQL_PWD="your-password"
```

### Key Commands

```bash
# Onboard tenant (full)
./onboard_tenant_full.sh --tenant-id xxx --tenant-name "XXX" --num-sites N

# Validate tenant
./validate_tenant.sh --tenant-id xxx

# Test pipeline
./test_iot_pipeline.sh xxx site_001 5

# Check pipeline health
./check_iot_pipeline.sh xxx
```

### Key SQL Queries

```sql
-- List all tenants
SELECT * FROM smdh_infrastructure.tenant_configs.tenants;

-- Check connector status
SELECT * FROM smdh_infrastructure.monitoring.v_openflow_connector_status;

-- Grant Openflow access
CALL smdh_infrastructure.tenant_configs.sp_grant_openflow_tenant_access('tenant_id');

-- Check recent data
SELECT COUNT(*), MAX(ingestion_timestamp)
FROM SMDH_TENANT_XXX.RAW.SENSOR_READINGS
WHERE ingestion_timestamp >= DATEADD(HOUR, -1, CURRENT_TIMESTAMP());
```

---

## Related Documentation

| Document | Purpose | Location |
|----------|---------|----------|
| Core Infrastructure Deployment | Initial platform setup | [Core_Infrastructure_Deployment_Guide.md](Core_Infrastructure_Deployment_Guide.md) |
| Terraform README | AWS infrastructure details | [../terraform/README.md](../terraform/README.md) |
| Snowflake README | Snowflake setup details | [../snowflake/README.md](../snowflake/README.md) |
| CLAUDE.md | Development guidelines | [../../CLAUDE.md](../../CLAUDE.md) |

---

*Document Version: 2.2*
*Last Updated: 6 December 2025*
*Author: SMDH Platform Team*
