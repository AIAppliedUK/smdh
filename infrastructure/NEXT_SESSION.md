# Next Session: Full Tear-Down and Rebuild Test

## Objective
Perform a complete tear-down and rebuild using **only** the deployment guides and scripts to validate documentation accuracy.

---

## Current State

**AWS Infrastructure:** Deployed (manufacturing_demo tenant active)
- Kinesis stream: `smdh-manufacturing_demo-stream`
- IoT rules, thing groups, certificates all provisioned
- IAM roles configured

**Snowflake Infrastructure:** Unknown state (may need teardown)

**Terraform State:** Valid, tracking all resources

---

## Key Files to Use

| Document | Location | Purpose |
|----------|----------|---------|
| Core Infrastructure Deployment Guide | `infrastructure/deployment/Core_Infrastructure_Deployment_Guide.md` | Full deployment sequence |
| Tenant Onboarding Guide | `infrastructure/deployment/Tenant_Onboarding_Guide.md` | Per-tenant setup |
| Terraform README | `infrastructure/terraform/README.md` | Quick reference |

---

## Terraform Configuration (NEW Structure)

```
infrastructure/terraform/environments/dev/
├── 01_tags.tfvars       # Tagging values (rarely changed)
├── 02_core.tfvars       # Core settings (rarely changed)
├── 03_tenants.tfvars    # Tenant definitions (edit to add/remove tenants)
```

**All commands require three var-files:**
```bash
cd infrastructure/terraform

# Destroy
terraform destroy \
  -var-file=environments/dev/01_tags.tfvars \
  -var-file=environments/dev/02_core.tfvars \
  -var-file=environments/dev/03_tenants.tfvars

# Apply
terraform apply \
  -var-file=environments/dev/01_tags.tfvars \
  -var-file=environments/dev/02_core.tfvars \
  -var-file=environments/dev/03_tenants.tfvars
```

---

## Deployment Sequence (from Guide)

1. **Phase 1: Prerequisites** - Tools, credentials, state storage
2. **Phase 2: AWS Core (Terraform)** - IoT Core, IAM, CloudWatch
3. **Phase 3: Snowflake Core (SQL)** - Run `01_infrastructure_setup.sql`, `02_shared_resources.sql`, `03_openflow_connector.sql`
4. **Phase 4: OpenFlow UI (Snowsight)** - Create deployment + runtime manually
5. **Phase 5: Tenant Onboarding** - Per-tenant resources

---

## Critical OpenFlow Configuration (Documented in Guide)

| Setting | Correct Value | Wrong Value |
|---------|---------------|-------------|
| Consumer Type | `Shared Throughput` | Enhanced Fan-Out |
| SF Auth Strategy | `SNOWFLAKE_SESSION_TOKEN` | KEY_PAIR |
| Metrics Publishing | `DISABLED` | None |
| AWS Auth | IAM Access Keys | Role Assumption |

---

## Snowflake Scripts Sequence

```bash
cd infrastructure/snowflake/sql/core

# Core setup (run in order)
snowsql -r ACCOUNTADMIN -f 01_infrastructure_setup.sql
snowsql -r ACCOUNTADMIN -f 02_shared_resources.sql
snowsql -r ACCOUNTADMIN -f 03_openflow_connector.sql

cd ../tenant

# Per-tenant (after OpenFlow connector configured in Snowsight UI)
snowsql -r ACCOUNTADMIN -f 10_create_tenant_database.sql --variable tenant_id="manufacturing_demo"
snowsql -r ACCOUNTADMIN -f 11_create_schemas.sql --variable tenant_id="manufacturing_demo"
snowsql -r ACCOUNTADMIN -f 12_create_tables.sql --variable tenant_id="manufacturing_demo"
snowsql -r ACCOUNTADMIN -f 13_create_streams.sql --variable tenant_id="manufacturing_demo"
snowsql -r ACCOUNTADMIN -f 16_create_roles.sql --variable tenant_id="manufacturing_demo"

# After OpenFlow landing table exists (connector running):
snowsql -r ACCOUNTADMIN -f 14_create_routing_task.sql --variable tenant_id="manufacturing_demo"
```

---

## What Was Fixed This Session

1. **Terraform reorganised** into 3 separate tfvars files for easier maintenance
2. **Old files removed**: `terraform.tfvars`, `core.tfvars`
3. **Deployment guide updated** (v1.3) with full multi-file documentation
4. **Tenant guide updated** with Method 2: Terraform + Snowflake workflow
5. **Routing task script** (`14_create_routing_task.sql`) fixed for correct column mappings

---

## Teardown Commands

### AWS (Terraform)
```bash
cd infrastructure/terraform
terraform destroy \
  -var-file=environments/dev/01_tags.tfvars \
  -var-file=environments/dev/02_core.tfvars \
  -var-file=environments/dev/03_tenants.tfvars
```

### Snowflake (Manual via SnowSQL)
```sql
-- Connect as ACCOUNTADMIN
-- Drop tenant database
DROP DATABASE IF EXISTS SMDH_TENANT_MANUFACTURING_DEMO;

-- Drop core databases
DROP DATABASE IF EXISTS SMDH_OPENFLOW;
DROP DATABASE IF EXISTS SMDH_INFRASTRUCTURE;

-- Drop warehouse
DROP WAREHOUSE IF EXISTS SMDH_WH;

-- Drop roles (check dependencies first)
DROP ROLE IF EXISTS OPENFLOW_RUNTIME_ROLE_KINESIS;
DROP ROLE IF EXISTS OPENFLOW_ADMIN;
DROP ROLE IF EXISTS smdh_infrastructure_admin;
DROP ROLE IF EXISTS smdh_tenant_operator;
DROP ROLE IF EXISTS smdh_data_engineer;
DROP ROLE IF EXISTS smdh_monitoring;
```

### OpenFlow (Snowsight UI)
1. Navigate to **Ingestion** → **Openflow**
2. Stop and delete any running connectors
3. Delete runtime: `smdh-kinesis-runtime`
4. Delete deployment: `smdh-openflow-deployment`

---

## Test Validation After Rebuild

1. **Terraform outputs:**
   ```bash
   terraform output
   ```

2. **Snowflake databases:**
   ```sql
   SHOW DATABASES LIKE 'SMDH%';
   SHOW WAREHOUSES LIKE 'SMDH%';
   ```

3. **Send test MQTT message:**
   ```bash
   cd infrastructure/scripts
   ./test_iot_pipeline.sh manufacturing_demo SITE_001 5
   ```

4. **Verify data in Snowflake:**
   ```sql
   USE DATABASE SMDH_TENANT_MANUFACTURING_DEMO;
   SELECT COUNT(*) FROM RAW.SENSOR_READINGS;
   ```

---

## Notes

- The deployment guide is now comprehensive - follow it step by step
- All critical OpenFlow settings are documented in Section 4.3 of the Core guide
- If OpenFlow connector fails, check Consumer Type first (most common issue)
- IAM user access keys are required for OpenFlow (role assumption not supported)

---

*Last Updated: 6 December 2025*
