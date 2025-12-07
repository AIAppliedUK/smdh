# SMDH Clean Rebuild - Next Session Context

**Last Updated:** December 4, 2025
**Session Focus:** Rebuild IoT Pipeline with Proper Openflow Assume Role Configuration

---

## Executive Summary

The Openflow Kinesis connector was failing because the `AWSCredentialsProviderControllerService` was enabled but not configured with credentials. We discovered that:

1. **Openflow DOES support IAM Role Assumption** (not just Access Keys)
2. The existing IAM role (`smdh-snowflake-kinesis-role-dev`) has the correct permissions
3. We just need to configure the Controller Service with the Assume Role ARN

**User has cleared all Openflow UI elements.** Ready to rebuild from scratch.

---

## What Was Cleared (User completed)

- [x] Openflow Kinesis connector deleted
- [x] Openflow runtime deleted
- [x] Openflow deployment deleted
- [x] All Controller Services cleared

---

## Execution Plan

### Phase 1: Cleanup Snowflake & Local Files (Claude)

```sql
-- Run in Snowflake
DROP DATABASE IF EXISTS SMDH_TENANT_TEST_TENANT;
DROP DATABASE IF EXISTS SMDH_OPENFLOW;
DROP DATABASE IF EXISTS SMDH_INFRASTRUCTURE;
DROP ROLE IF EXISTS OPENFLOW_ADMIN;
DROP ROLE IF EXISTS OPENFLOW_RUNTIME_ROLE_KINESIS;
DROP INTEGRATION IF EXISTS OPENFLOW_AWS_EAI;
```

```bash
# Delete local certificates
rm -f infrastructure/deployment/certificates/test_tenant_*
```

### Phase 2: Rebuild Snowflake (Claude)

```bash
cd /Users/david/projects/smdh/infrastructure/snowflake/sql/core

# Run in order
snowsql -f 00_drop_all.sql
snowsql -f 01_infrastructure_setup.sql
snowsql -f 02_shared_resources.sql
snowsql -f 03_openflow_connector.sql

cd ../tenant

# Create test tenant
snowsql -f 10_create_tenant_database.sql --variable tenant_id=test_tenant --variable tenant_name="Test Tenant" --variable aws_region=eu-west-2 --variable num_sites=2
snowsql -f 11_create_schemas.sql --variable tenant_id=test_tenant
snowsql -f 12_create_tables.sql --variable tenant_id=test_tenant
snowsql -f 13_create_streams.sql --variable tenant_id=test_tenant
snowsql -f 16_create_roles.sql --variable tenant_id=test_tenant
```

### Phase 3: Verify/Rebuild AWS (Claude)

```bash
cd /Users/david/projects/smdh/infrastructure/terraform

# Check current state
terraform state list | grep tenant

# Apply if needed (tenant resources)
terraform apply -var-file=environments/dev/terraform.tfvars -auto-approve
```

**Expected AWS Resources:**
- Kinesis stream: `smdh-test_tenant-stream`
- IoT Things: `smdh-gateway-test_tenant-site_001-gw_001`, `smdh-gateway-test_tenant-site_002-gw_001`
- IoT Policy: `smdh-policy-test_tenant`
- IoT Rule: `smdh_route_test_tenant`
- IAM Role: `smdh-snowflake-kinesis-role-dev` (already exists)

### Phase 4: Openflow Configuration (User in Snowsight UI)

#### Step 1: Create Deployment
1. Navigate to: **Data > Openflow**
2. Click **Create Deployment**
3. Configure:
   - Name: `smdh-openflow-deployment`
   - Type: **Snowflake Deployment** (managed)

#### Step 2: Create Runtime
1. In deployment, click **Create Runtime**
2. Configure:
   - Name: `smdh-kinesis-runtime`
   - Role: `OPENFLOW_RUNTIME_ROLE_KINESIS`
   - Warehouse: `SMDH_WH`
   - External Access Integration: `OPENFLOW_AWS_EAI`

#### Step 3: Add Kinesis Connector
1. Click **Add Connector** > **Amazon Kinesis**
2. Enter the process group and configure:

**AWSCredentialsProviderControllerService Configuration:**

| Property | Value |
|----------|-------|
| Use Default Credentials | `false` |
| Access Key ID | *(leave blank)* |
| Secret Access Key | *(leave blank)* |
| **Assume Role ARN** | `arn:aws:iam::471112943820:role/smdh-snowflake-kinesis-role-dev` |
| **Assume Role Session Name** | `openflow-kinesis-session` |
| Assume Role External ID | *(leave blank initially)* |

**Kinesis Source Configuration:**

| Property | Value |
|----------|-------|
| AWS Region | `eu-west-2` |
| Kinesis Stream Name | `smdh-test_tenant-stream` |
| Kinesis Application Name | `smdh-openflow-test_tenant` |
| Kinesis Initial Stream Position | `LATEST` |
| Metrics Publishing | `DISABLED` |

**Destination Configuration:**

| Property | Value |
|----------|-------|
| Database | `SMDH_TENANT_TEST_TENANT` |
| Schema | `RAW` |
| Table | `SENSOR_READINGS` |
| Authentication | `SNOWFLAKE_SESSION_TOKEN` |
| Role | `OPENFLOW_RUNTIME_ROLE_KINESIS` |
| Warehouse | `SMDH_WH` |

**Stream-to-Table Mapping:**
```
smdh-test_tenant-stream:SENSOR_READINGS
```

#### Step 4: Start Everything
1. **Enable** all Controller Services (right-click each → Enable)
2. **Start** all Process Groups in order:
   - Kinesis JSON Source
   - Custom Transformations
   - Streaming Destination

### Phase 5: Validation (Claude)

```bash
# Send test data
./infrastructure/scripts/test_iot_pipeline.sh test_tenant SITE_001 5

# Wait 30-60 seconds, then verify
snowsql -q "USE DATABASE SMDH_TENANT_TEST_TENANT; SELECT COUNT(*) as count, MAX(ingestion_timestamp) as latest FROM raw.sensor_readings WHERE ingestion_timestamp >= DATEADD(MINUTE, -10, CURRENT_TIMESTAMP());"
```

---

## Key Technical Details

### IAM Role Details

**Role Name:** `smdh-snowflake-kinesis-role-dev`
**ARN:** `arn:aws:iam::471112943820:role/smdh-snowflake-kinesis-role-dev`

**Current Trust Policy:**
```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "AWS": "*" },
    "Action": "sts:AssumeRole"
  }]
}
```
*(Note: Permissive for testing. Tighten later with Snowflake's principal.)*

**Permissions:**
- `kinesis:*` on `arn:aws:kinesis:eu-west-2:471112943820:stream/smdh-*-stream`
- `dynamodb:*` on `arn:aws:dynamodb:eu-west-2:471112943820:table/smdh-openflow-*`
- `cloudwatch:PutMetricData`

### Data Flow Architecture

```
IoT Devices (MQTT)
    ↓
AWS IoT Core (topic: smdh/{tenant_id}/{site_id}/sensor-data)
    ↓
IoT Rule (smdh_route_test_tenant)
    - Enriches with: tenant_id, site_id, iot_timestamp, device_id
    ↓
Kinesis Stream (smdh-test_tenant-stream)
    ↓
Snowflake Openflow (Kinesis connector with Assume Role)
    ↓
Snowflake Table (SMDH_TENANT_TEST_TENANT.RAW.SENSOR_READINGS)
```

### UG65 Message Format

```json
{
  "applicationId": "smdh",
  "deviceEUI": "24E124707E043923",
  "deviceName": "AM308-TempHumidity-Floor1",
  "time": "2025-12-04T20:18:37.000Z",
  "fPort": 85,
  "fCntUp": 4001,
  "adr": true,
  "confirmedUplink": false,
  "data": {
    "temperature": 21.8,
    "humidity": 48.5,
    "co2": 420,
    "battery": 92
  },
  "rx": {
    "gatewayEUI": "24E124FFFEF35F39",
    "frequency": 868.1,
    "dataRate": "SF9BW125",
    "rssi": -95,
    "snr": 3.0
  }
}
```

---

## Key Files Reference

| File | Purpose |
|------|---------|
| `infrastructure/terraform/main.tf` | Root Terraform - orchestrates all modules |
| `infrastructure/terraform/modules/iam/main.tf` | IAM role for Openflow (Assume Role) |
| `infrastructure/terraform/modules/tenant/main.tf` | Per-tenant: Kinesis, IoT, certificates |
| `infrastructure/snowflake/sql/core/03_openflow_connector.sql` | Openflow roles, network rules, EAI |
| `infrastructure/snowflake/sql/tenant/12_create_tables.sql` | Creates RAW.SENSOR_READINGS table |
| `infrastructure/scripts/test_iot_pipeline.sh` | E2E test script (sends UG65 messages) |
| `tests/device-simulators/ug65_e2e_test.py` | Python MQTT simulator |
| `IMPLEMENTATION_PLAN.md` | Full rebuild plan (created this session) |

---

## Troubleshooting

### Check Openflow Logs
```sql
SELECT timestamp, value
FROM snowflake.telemetry.events
WHERE timestamp >= DATEADD(MINUTE, -5, CURRENT_TIMESTAMP())
  AND value LIKE '%ERROR%'
ORDER BY timestamp DESC
LIMIT 10;
```

### Check Kinesis Stream
```bash
aws kinesis describe-stream-summary --stream-name smdh-test_tenant-stream --region eu-west-2
```

### Check IAM Role
```bash
aws iam get-role --role-name smdh-snowflake-kinesis-role-dev
aws iam list-role-policies --role-name smdh-snowflake-kinesis-role-dev
```

### Common Issues

| Issue | Cause | Fix |
|-------|-------|-----|
| "Unable to load credentials" | Controller Service not configured | Set Assume Role ARN |
| "Access Denied" to Kinesis | Trust policy or permissions | Check IAM role |
| ConsumeKinesis stuck initializing | DynamoDB access issue | Check DynamoDB permissions |
| No data in Snowflake | Connector not started | Start all process groups |

---

## Success Criteria

1. **Test script succeeds**: `./infrastructure/scripts/test_iot_pipeline.sh test_tenant SITE_001 5`
2. **Data appears in Snowflake** within 60 seconds:
   ```sql
   SELECT COUNT(*) FROM SMDH_TENANT_TEST_TENANT.RAW.SENSOR_READINGS
   WHERE ingestion_timestamp >= DATEADD(MINUTE, -10, CURRENT_TIMESTAMP());
   ```
   Should return 5 records.
3. **No ERROR logs** in Openflow telemetry
4. **Openflow UI shows data flowing**: In > 0, Out > 0 on all process groups

---

## Environment Context

- **Project**: Smart Manufacturing Data Hub (SMDH)
- **Working Directory**: `/Users/david/projects/smdh`
- **AWS Account**: 471112943820
- **AWS Region**: eu-west-2
- **Snowflake Account**: AIAPPLIED (has ACCOUNTADMIN)
- **Git Branch**: `feature/implementation`
- **Platform**: macOS Darwin 24.6.0

---

## Quick Start Command for Next Session

```
Read next_session.md and execute the rebuild plan:

1. Run Phase 1: Cleanup Snowflake databases and local certificates
2. Run Phase 2: Execute Snowflake SQL scripts in order
3. Run Phase 3: Verify/apply Terraform for AWS resources
4. Guide user through Phase 4: Openflow UI configuration with Assume Role
5. Run Phase 5: Validate with test data

Key insight: Configure AWSCredentialsProviderControllerService with:
- Assume Role ARN: arn:aws:iam::471112943820:role/smdh-snowflake-kinesis-role-dev
- Assume Role Session Name: openflow-kinesis-session
```

---

*Created: 2025-12-04 20:30 UTC*
*Previous Session: Diagnosed Openflow credentials issue, discovered Assume Role support*
