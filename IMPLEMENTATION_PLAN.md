# SMDH Clean Rebuild Implementation Plan

## Executive Summary

**Root Cause Identified**: The Snowflake Openflow Kinesis connector **only supports AWS Access Key authentication**, not IAM role assumption. The current Terraform creates an IAM role for cross-account access, but Openflow cannot use roles - it requires Access Key ID and Secret Access Key.

**Solution**: Create an IAM user with the required permissions, generate access keys, and configure the Openflow connector with those credentials.

---

## Phase 1: Cleanup Existing Resources

### 1.1 AWS Resources to Delete (via Terraform destroy)

| Resource Type | Resource Name | Action |
|---------------|---------------|--------|
| Kinesis Stream | `smdh-test_tenant-stream` | Terraform destroy |
| IoT Things | `smdh-gateway-test_tenant-site_*-gw_001` | Terraform destroy |
| IoT Policy | `smdh-policy-test_tenant` | Terraform destroy |
| IoT Certificates | 4 certificates | Terraform destroy |
| IoT Rule | `smdh_route_test_tenant` | Terraform destroy |
| Thing Groups | `smdh-tenant-test_tenant`, etc. | Terraform destroy |
| CloudWatch Alarms | Various tenant alarms | Terraform destroy |

### 1.2 Snowflake Resources to Drop

```sql
-- Drop all SMDH databases
DROP DATABASE IF EXISTS SMDH_TENANT_TEST_TENANT;
DROP DATABASE IF EXISTS SMDH_OPENFLOW;
DROP DATABASE IF EXISTS SMDH_INFRASTRUCTURE;

-- Drop Openflow roles
DROP ROLE IF EXISTS OPENFLOW_ADMIN;
DROP ROLE IF EXISTS OPENFLOW_RUNTIME_ROLE_KINESIS;

-- Drop external access integration
DROP INTEGRATION IF EXISTS OPENFLOW_AWS_EAI;
```

### 1.3 Local Files to Delete

```bash
rm -f infrastructure/deployment/certificates/test_tenant_*
```

### 1.4 Openflow UI Cleanup (User Manual Step)

- Delete Kinesis connector
- Delete Runtime: `smdh-kinesis-runtime`
- Delete Deployment: `smdh-openflow-deployment`

---

## Phase 2: Terraform Changes

### 2.1 Add IAM User for Openflow (NEW)

The IAM module must be updated to create an IAM user (not just a role) for Openflow:

**File**: `infrastructure/terraform/modules/iam/main.tf`

Add:
```hcl
# IAM User for Openflow Kinesis connector
# Openflow only supports Access Key authentication (NOT IAM roles)
resource "aws_iam_user" "openflow_kinesis" {
  name = "${var.project_name}-openflow-kinesis-user-${var.environment}"
  path = "/openflow/"

  tags = merge(var.tags, {
    Name        = "${var.project_name}-openflow-kinesis-user"
    Purpose     = "Snowflake Openflow Kinesis Access"
    Description = "IAM user for Openflow connector - requires Access Keys"
  })
}

# Attach the existing Kinesis read policy to the user
resource "aws_iam_user_policy" "openflow_kinesis" {
  name   = "openflow-kinesis-access"
  user   = aws_iam_user.openflow_kinesis.name
  policy = data.aws_iam_policy_document.snowflake_kinesis_read.json
}

# Generate access keys for the user
resource "aws_iam_access_key" "openflow_kinesis" {
  user = aws_iam_user.openflow_kinesis.name
}
```

### 2.2 Store Credentials in Secrets Manager

Add to `infrastructure/terraform/modules/secrets-manager/main.tf`:

```hcl
# Openflow AWS credentials (Access Key for Kinesis connector)
resource "aws_secretsmanager_secret" "openflow_credentials" {
  name        = "${var.secret_name_prefix}-openflow-kinesis-credentials"
  description = "AWS credentials for Snowflake Openflow Kinesis connector"

  recovery_window_in_days = var.recovery_window_days

  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "openflow_credentials" {
  secret_id = aws_secretsmanager_secret.openflow_credentials.id
  secret_string = jsonencode({
    access_key_id     = var.openflow_access_key_id
    secret_access_key = var.openflow_secret_access_key
    aws_region        = "eu-west-2"
  })
}
```

### 2.3 Output the Access Keys

Add to `infrastructure/terraform/modules/iam/outputs.tf`:

```hcl
output "openflow_access_key_id" {
  description = "Access Key ID for Openflow Kinesis connector"
  value       = aws_iam_access_key.openflow_kinesis.id
  sensitive   = true
}

output "openflow_secret_access_key" {
  description = "Secret Access Key for Openflow Kinesis connector"
  value       = aws_iam_access_key.openflow_kinesis.secret
  sensitive   = true
}
```

---

## Phase 3: Test Tenant Configuration

### 3.1 Tenant Definition in tfvars

**File**: `infrastructure/terraform/environments/dev/terraform.tfvars`

```hcl
tenants = {
  test_tenant = {
    name            = "Test Tenant"
    num_sites       = 2
    deployment_mode = "gateway"
    contact_email   = "ops@example.com"
  }
}
```

### 3.2 Resources Created per Tenant

| Resource | Name Pattern | Purpose |
|----------|--------------|---------|
| Kinesis Stream | `smdh-{tenant_id}-stream` | Per-tenant data isolation |
| IoT Policy | `smdh-policy-{tenant_id}` | MQTT access control |
| IoT Rule | `smdh_route_{tenant_id}` | Route data to Kinesis |
| IoT Things | `smdh-gateway-{tenant_id}-{site_id}-gw_001` | Device registry |
| IoT Certificates | Per gateway | Device authentication |
| Thing Groups | `smdh-tenant-{tenant_id}`, `smdh-{tenant_id}-{site_id}` | Device organization |
| Snowflake DB | `SMDH_TENANT_{TENANT_ID}` | Isolated data storage |

---

## Phase 4: Snowflake Setup

### 4.1 Execution Order

1. `infrastructure/snowflake/sql/core/00_drop_all.sql` - Clean slate
2. `infrastructure/snowflake/sql/core/01_infrastructure_setup.sql` - Create SMDH_INFRASTRUCTURE
3. `infrastructure/snowflake/sql/core/02_shared_resources.sql` - Create warehouse, roles
4. `infrastructure/snowflake/sql/core/03_openflow_connector.sql` - Create Openflow resources

### 4.2 Tenant Onboarding

For each tenant, run in order:
1. `10_create_tenant_database.sql`
2. `11_create_schemas.sql`
3. `12_create_tables.sql`
4. `13_create_streams.sql`
5. `14_create_tasks.sql` (optional)
6. `15_create_dynamic_tables.sql` (optional)
7. `16_create_roles.sql`
8. `17_create_monitoring.sql` (optional)

---

## Phase 5: Openflow Configuration

### 5.1 Create Deployment (Snowsight UI)

1. Navigate to: **Data > Openflow**
2. Click **Create Deployment**
3. Configure:
   - Name: `smdh-openflow-deployment`
   - Type: **Snowflake Deployment** (managed)

### 5.2 Create Runtime (Snowsight UI)

1. In the deployment, click **Create Runtime**
2. Configure:
   - Name: `smdh-kinesis-runtime`
   - Role: `OPENFLOW_RUNTIME_ROLE_KINESIS`
   - Warehouse: `SMDH_WH`
   - External Access Integration: `OPENFLOW_AWS_EAI`

### 5.3 Add Kinesis Connector (Snowsight UI)

1. In the runtime, click **Add Connector** > **Amazon Kinesis**
2. Configure **Kinesis Source**:

| Parameter | Value |
|-----------|-------|
| AWS Region | `eu-west-2` |
| AWS Access Key ID | *(from Secrets Manager or Terraform output)* |
| AWS Secret Access Key | *(from Secrets Manager or Terraform output)* |
| Kinesis Stream Name | `smdh-test_tenant-stream` |
| Kinesis Application Name | `smdh-openflow-test_tenant` |
| Kinesis Initial Stream Position | `LATEST` |
| Metrics Publishing | `DISABLED` |

3. Configure **Destination**:

| Parameter | Value |
|-----------|-------|
| Database | `SMDH_TENANT_TEST_TENANT` |
| Schema | `RAW` |
| Table | `SENSOR_READINGS` |
| Authentication | `SNOWFLAKE_SESSION_TOKEN` |
| Role | `OPENFLOW_RUNTIME_ROLE_KINESIS` |
| Warehouse | `SMDH_WH` |

4. Configure **Stream-to-Table Mapping**:
```
smdh-test_tenant-stream:SENSOR_READINGS
```

5. Click **Create** > **Start**

---

## Phase 6: Validation

### 6.1 Send Test Data

```bash
./infrastructure/scripts/test_iot_pipeline.sh test_tenant SITE_001 5
```

### 6.2 Verify in Snowflake

```sql
USE DATABASE SMDH_TENANT_TEST_TENANT;
SELECT * FROM raw.sensor_readings
WHERE ingestion_timestamp >= DATEADD(MINUTE, -10, CURRENT_TIMESTAMP())
ORDER BY ingestion_timestamp DESC;
```

### 6.3 Expected Result

5 records with UG65-formatted sensor data including:
- deviceEUI
- deviceName
- time
- data (temperature, humidity, etc.)
- tenant_id, site_id (enriched by IoT Rule)

---

## Key Documentation Updates Required

### Update Deployment Guide

**File**: `infrastructure/deployment/Tenant_Onboarding_Guide.md`

1. Add section on **AWS Access Key Configuration**
2. Remove references to IAM role assumption for Openflow
3. Add instructions for retrieving credentials from Secrets Manager or Terraform output
4. Update Openflow connector configuration with Access Key fields

### Update CLAUDE.md

Add to "IoT Pipeline E2E Testing" section:
```markdown
### Openflow Kinesis Authentication

**Important**: Snowflake Openflow Kinesis connector only supports Access Key authentication.
- IAM roles CANNOT be used for Openflow Kinesis connectors
- Access Key ID and Secret Access Key must be provided in the connector configuration
- Credentials are stored in AWS Secrets Manager: `smdh-openflow-kinesis-credentials`
```

---

## Execution Checklist

### Pre-Cleanup
- [ ] User confirms they've backed up any needed data
- [ ] User deletes Openflow connector in Snowsight UI
- [ ] User deletes Openflow runtime in Snowsight UI
- [ ] User deletes Openflow deployment in Snowsight UI

### Cleanup Phase
- [ ] Run Terraform destroy for tenant resources
- [ ] Run Snowflake DROP scripts
- [ ] Delete local certificate files

### Terraform Updates
- [ ] Update IAM module to create user + access keys
- [ ] Update Secrets Manager module to store credentials
- [ ] Update outputs to expose access key info

### Rebuild Phase
- [ ] Run `terraform apply`
- [ ] Run Snowflake core setup scripts (01-03)
- [ ] Run Snowflake tenant setup scripts (10-17)

### Openflow Configuration
- [ ] Create Deployment in Snowsight
- [ ] Create Runtime in Snowsight
- [ ] Add Kinesis connector with Access Key credentials
- [ ] Start the connector

### Validation
- [ ] Send test data through pipeline
- [ ] Verify data appears in Snowflake

---

## Sources

- [Snowflake Openflow Kinesis Setup](https://docs.snowflake.com/en/user-guide/data-integration/openflow/connectors/kinesis/setup)
- [About Openflow Kinesis Connector](https://docs.snowflake.com/en/user-guide/data-integration/openflow/connectors/kinesis/about)
- [AWS Cross-Account Kinesis Access](https://aws.amazon.com/blogs/architecture/field-notes-how-to-enable-cross-account-access-for-amazon-kinesis-data-streams-using-kinesis-client-library-2-x/)
