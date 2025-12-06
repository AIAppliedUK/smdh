
 SMDH Snowflake Setup Guide

Complete setup guide for the Smart Manufacturing Data Hub (SMDH) Snowflake infrastructure and tenant onboarding.

 Overview

This directory contains all SQL scripts and automation tools needed to:
- Set up the core SMDH infrastructure in Snowflake
- Configure Kinesis integration via Snowflake Openflow
- Onboard new tenants with complete isolation
- Manage tenant lifecycle (onboarding, monitoring, offboarding)

 Architecture

```

                   SMDH Snowflake Platform                    

                                                              
    
   Infrastructure Database (smdh_infrastructure)          
   - Tenant registry                                      
   - Device metadata                                      
   - Platform monitoring                                  
   - Audit logs                                           
    
                                                              
    
   Tenant Database (per tenant)                           
   - RAW: Ingested data from Kinesis                      
   - NORMALIZED: Validated and flattened                  
   - AGGREGATED: Pre-computed metrics                     
   - ANALYTICS: Views and dashboards                      
    
                                                              
    
   Real-Time Pipeline                                     
   Kinesis → Streams → Tasks → Dynamic Tables            
    
                                                              

```

 Directory Structure

```
infrastructure/
├── scripts/                           # Main automation scripts
│   ├── onboard_tenant_full.sh         # ** FULL END-TO-END TENANT ONBOARDING **
│   └── validate_tenant.sh             # Validate tenant setup (AWS + Snowflake)
│
├── snowflake/
│   ├── scripts/                       # Snowflake-specific scripts
│   │   ├── snowflake.sh               # Core infrastructure: deploy/drop/status
│   │   ├── onboard_tenant.sh          # Snowflake-only tenant onboarding
│   │   ├── validate_setup.sh          # Full validation with tenant setup
│   │   ├── setup_openflow.sh          # Openflow infrastructure setup
│   │   ├── setup_kinesis_integration.sh # Legacy Kinesis connector setup
│   │   └── sync_aws_iot_metadata.sh   # Sync IoT device metadata
│   │
│   ├── sql/                           # SQL scripts
│   │   ├── core/                      # Core infrastructure scripts
│   │   │   ├── 00_drop_all.sql        # Clean teardown
│   │   │   ├── 00_prerequisites.sql   # Environment validation
│   │   │   ├── 01_infrastructure_setup.sql # Infrastructure database
│   │   │   ├── 02_shared_resources.sql    # Warehouses and roles
│   │   │   └── 03_openflow_connector.sql  # ** OPENFLOW KINESIS INTEGRATION **
│   │   │
│   │   ├── tenant/                    # Per-tenant setup scripts
│   │   │   ├── 10_create_tenant_database.sql
│   │   │   ├── 11_create_schemas.sql
│   │   │   ├── 12_create_tables.sql
│   │   │   ├── 13_create_streams.sql
│   │   │   ├── 14_create_tasks.sql
│   │   │   ├── 15_create_dynamic_tables.sql
│   │   │   ├── 16_create_roles.sql
│   │   │   └── 17_create_monitoring.sql
│   │   │
│   │   └── utility/                   # Utility SQL scripts
│   │       ├── check_current_state.sql
│   │       ├── check_role.sql
│   │       └── validate_tenant.sql
│   │
│   └── README.md
│
└── terraform/                         # AWS infrastructure
```

## Quick Start

```bash
# Set credentials
export SNOWSQL_PWD='your_password'
export AWS_REGION='eu-west-2'

# OPTION 1: Full automated tenant onboarding (AWS + Snowflake)
cd infrastructure/scripts
./onboard_tenant_full.sh \
  --tenant-id acme_corp \
  --tenant-name "ACME Corporation" \
  --num-sites 5

# OPTION 2: Snowflake-only onboarding (if AWS already configured)
cd infrastructure/snowflake/scripts
./onboard_tenant.sh \
  --tenant-id acme_corp \
  --tenant-name "ACME Corporation" \
  --num-sites 5 \
  --snowflake-account $SNOWFLAKE_ACCOUNT \
  --snowflake-user $SNOWFLAKE_USER

# Validate tenant setup
cd infrastructure/scripts
./validate_tenant.sh --tenant-id acme_corp

# Check Snowflake status
cd infrastructure/snowflake/scripts
./snowflake.sh status
```

---

## Snowflake Openflow Integration (Kinesis)

### Overview

SMDH uses **Snowflake Openflow** to ingest data from AWS Kinesis Data Streams. This provides:
- Native Kinesis integration (no external ETL tools)
- Sub-second latency
- Automatic checkpointing via DynamoDB
- Per-tenant stream isolation

### Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         DATA FLOW ARCHITECTURE                              │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────────────────────┐  │
│  │ IoT Devices  │───▶│ AWS IoT Core │───▶│ Kinesis Data Stream          │  │
│  │ (MQTT)       │    │ (Rules)      │    │ smdh-{tenant_id}-stream      │  │
│  └──────────────┘    └──────────────┘    └──────────────┬───────────────┘  │
│                                                         │                   │
│                                                         ▼                   │
│                              ┌───────────────────────────────────────────┐  │
│                              │     SNOWFLAKE OPENFLOW                    │  │
│                              │  ┌─────────────────────────────────────┐  │  │
│                              │  │  Deployment: smdh-openflow-deployment│  │  │
│                              │  │  Runtime: smdh-kinesis-runtime       │  │  │
│                              │  │  Role: OPENFLOW_RUNTIME_ROLE_KINESIS │  │  │
│                              │  │  Integration: OPENFLOW_AWS_EAI       │  │  │
│                              │  └─────────────────────────────────────┘  │  │
│                              └───────────────┬───────────────────────────┘  │
│                                              │                              │
│                    ┌─────────────────────────┼─────────────────────────┐    │
│                    ▼                         ▼                         ▼    │
│   ┌────────────────────────┐ ┌────────────────────────┐ ┌────────────────┐ │
│   │ SMDH_TENANT_ACME_CORP  │ │ SMDH_TENANT_XYZ_INC    │ │ SMDH_TENANT_...│ │
│   │ .RAW.SENSOR_READINGS   │ │ .RAW.SENSOR_READINGS   │ │ .RAW.SENSOR_...│ │
│   └────────────────────────┘ └────────────────────────┘ └────────────────┘ │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### What's Automated vs Manual

| Component | Automated | Manual (One-Time) |
|-----------|-----------|-------------------|
| AWS Kinesis Stream | ✅ `onboard_tenant_full.sh` | - |
| AWS IAM Role | ✅ `onboard_tenant_full.sh` | - |
| AWS IoT Rule | ✅ `onboard_tenant_full.sh` | - |
| Snowflake Tenant Database | ✅ `onboard_tenant_full.sh` | - |
| Openflow SQL Resources | ✅ `03_openflow_connector.sql` | - |
| Openflow Access Grants | ✅ `sp_grant_openflow_tenant_access()` | - |
| Connector Registration | ✅ `onboard_tenant_full.sh` | - |
| **Openflow Deployment** | ❌ | Snowsight UI (once) |
| **Openflow Runtime** | ❌ | Snowsight UI (once) |
| **Kinesis Connector Config** | ❌ | Snowsight UI (per tenant) |

### Step-by-Step Setup

#### Step 1: Run Core Infrastructure SQL (One-Time)

```bash
# Run in Snowsight or via SnowSQL
cd infrastructure/snowflake/sql/core

# Prerequisites
snowsql -f 00_prerequisites.sql

# Infrastructure database
snowsql -f 01_infrastructure_setup.sql

# Shared resources (warehouse, roles)
snowsql -f 02_shared_resources.sql

# Openflow connector infrastructure
snowsql -f 03_openflow_connector.sql
```

**What `03_openflow_connector.sql` creates:**

| Resource | Name | Purpose |
|----------|------|---------|
| Role | `OPENFLOW_ADMIN` | Administer Openflow deployments |
| Role | `OPENFLOW_RUNTIME_ROLE_KINESIS` | Runtime role for connectors |
| Database | `OPENFLOW` | Image repository for containers |
| Network Rule | `OPENFLOW_AWS_EU_WEST_2_RULE` | Egress to Kinesis/DynamoDB/STS |
| Integration | `OPENFLOW_AWS_EAI` | External access integration |
| Table | `openflow_connectors` | Connector tracking/registry |
| Procedure | `sp_grant_openflow_tenant_access()` | Grant tenant DB access |
| Views | `v_openflow_connector_status` | Monitoring views |

#### Step 2: Create Openflow Deployment (Snowsight UI - One-Time)

1. Open **Snowsight** → **Data** → **Openflow**
2. Click **Create Deployment**
3. Configure:
   - **Name**: `smdh-openflow-deployment`
   - **Type**: Snowflake Deployment (managed)
4. Click **Create**

#### Step 3: Create Runtime (Snowsight UI - One-Time)

1. In your deployment, click **Create Runtime**
2. Configure:
   - **Name**: `smdh-kinesis-runtime`
   - **Role**: `OPENFLOW_RUNTIME_ROLE_KINESIS`
   - **Warehouse**: `SMDH_WH`
   - **External Access Integration**: `OPENFLOW_AWS_EAI`
3. Click **Create**

#### Step 4: Onboard a Tenant (Automated)

```bash
cd infrastructure/scripts

./onboard_tenant_full.sh \
  --tenant-id acme_corp \
  --tenant-name "ACME Corporation" \
  --num-sites 5
```

This creates:
- AWS Kinesis stream: `smdh-acme_corp-stream`
- AWS IAM role: `smdh-openflow-acme_corp-role`
- AWS IoT rule: `smdh_acme_corp_to_kinesis`
- Snowflake database: `SMDH_TENANT_ACME_CORP`
- Grants Openflow access to tenant database
- Registers connector in tracking table

#### Step 5: Add Kinesis Connector (Snowsight UI - Per Tenant)

1. In `smdh-kinesis-runtime`, click **Add Connector**
2. Select **Kinesis Data Streams: JSON modularized**
3. **Enter the process group** by double-clicking it

4. Configure **AWSCredentialsProviderControllerService** (Access Keys Required):

| Parameter | Value |
|-----------|-------|
| AWS Access Key ID | `<your-access-key-id>` |
| AWS Secret Access Key | `<your-secret-access-key>` |

> **CRITICAL**: Openflow Kinesis connector does **NOT** support IAM Role Assumption. You must create a dedicated IAM user with access keys:
> ```bash
> aws iam create-user --user-name smdh-openflow-kinesis-user
> aws iam create-access-key --user-name smdh-openflow-kinesis-user
> ```
> See `docs/deployment/Openflow_Kinesis_Configuration_Guide.md` for the required IAM policy.

5. Configure **Kinesis Source Parameters**:

| Parameter | Value |
|-----------|-------|
| AWS Region | `eu-west-2` |
| Stream Name | `smdh-acme_corp-stream` |
| Application Name | `smdh-openflow-acme_corp` |
| Initial Position | `TRIM_HORIZON` (all data) or `LATEST` (new only) |
| **Consumer Type** | **`POLLING`** (Shared Throughput) |
| Metrics Publishing | `None` |

> **CRITICAL**: Consumer Type MUST be `POLLING` (Shared Throughput). Enhanced Fan-Out causes `InterruptedException` errors during initialization.

6. Configure **Streaming Destination**:

| Parameter | Value |
|-----------|-------|
| Snowflake Account | `<org>-<account>` (e.g., `qqoylnv-zy42691`) |
| Database | `SMDH_TENANT_ACME_CORP` |
| Schema | `RAW` |
| **Authentication Strategy** | **`SNOWFLAKE_SESSION_TOKEN`** |
| Role | `OPENFLOW_RUNTIME_ROLE_KINESIS` |
| Warehouse | `SMDH_WH` |

> **IMPORTANT**: Use `SNOWFLAKE_SESSION_TOKEN` authentication. Do NOT configure private key - Openflow runs inside Snowflake and uses session tokens automatically.

7. Enable all **Controller Services** in each process group

8. **Start** the flow from the parent process group level

#### Step 6: Deploy Data Routing Task

After Openflow is ingesting data, deploy the routing task to distribute data to typed sensor tables:

```bash
cd infrastructure/snowflake/sql/tenant
snowsql -a <account> -u <user> -r ACCOUNTADMIN -w SMDH_WH \
  -f 14_create_routing_task.sql \
  --variable tenant_id='acme_corp'
```

This creates:
- `OPENFLOW_LANDING_STREAM` - CDC stream on Openflow landing table
- `TASK_ROUTE_SENSOR_DATA` - Runs every minute when stream has data
- `sp_route_sensor_data()` - Routes data to typed tables
- `sp_backfill_typed_tables()` - Backfill historical data

**Data Flow:**
```
Openflow Landing Table ("SMDH-ACME_CORP-STREAM")
          ↓ (Stream + Task)
    ┌─────┴─────┬──────────────┬──────────────┬──────────────┐
    ↓           ↓              ↓              ↓              ↓
SENSOR_     ENVIRONMENTAL   VIBRATION      CLAMP        DEVICE
READINGS    _SENSOR_...     _SENSOR_...    _SENSOR_...  _STATUS
```

### Adding More Tenants

For subsequent tenants, run:

```bash
# 1. Automated AWS + Snowflake setup
./onboard_tenant_full.sh \
  --tenant-id new_tenant \
  --tenant-name "New Tenant Inc" \
  --num-sites 3

# 2. Add connector in Snowsight UI (or update existing connector's stream mapping)
```

**Multi-tenant stream mapping:**
```
smdh-acme_corp-stream:SMDH_TENANT_ACME_CORP.RAW.SENSOR_READINGS,
smdh-new_tenant-stream:SMDH_TENANT_NEW_TENANT.RAW.SENSOR_READINGS
```

### Monitoring Openflow Connectors

```sql
-- Connector status overview
SELECT * FROM smdh_infrastructure.monitoring.v_openflow_connector_status;

-- Health summary
SELECT * FROM smdh_infrastructure.monitoring.v_openflow_health_summary;

-- Grant access to new tenant (if not using automation script)
CALL smdh_infrastructure.tenant_configs.sp_grant_openflow_tenant_access('tenant_id');
```

### Troubleshooting Openflow

| Issue | Solution |
|-------|----------|
| **InterruptedException during init** | Change Consumer Type to `POLLING` (NOT Enhanced Fan-Out) |
| **"Private Key not configured"** | Use `SNOWFLAKE_SESSION_TOKEN` authentication, not key-pair |
| **"Insufficient privileges on schema"** | Run `CALL sp_grant_openflow_tenant_access('tenant_id')` |
| **"Access Denied" from AWS** | Use IAM Access Keys (NOT role assumption); check DynamoDB permissions |
| No data appearing | Check connector status in Snowsight UI; verify Kinesis stream has data |
| Network timeout | Verify `OPENFLOW_AWS_EAI` integration is enabled |
| High latency | Increase Kinesis shards; check warehouse size |
| Connector stuck in "Stopping" | Right-click processor → Terminate to kill stuck thread |
| **Routing task failing** | Check `INFORMATION_SCHEMA.TASK_HISTORY()` for error messages |

See full troubleshooting guide: `docs/deployment/Openflow_Kinesis_Configuration_Guide.md`

---

## Full Tenant Onboarding (End-to-End)

### Using the Automation Script

```bash
cd infrastructure/scripts

# Full onboarding (AWS + Snowflake)
./onboard_tenant_full.sh \
  --tenant-id acme_corp \
  --tenant-name "ACME Corporation" \
  --num-sites 5 \
  --contact-email ops@acme.com

# Dry run (see what would happen)
./onboard_tenant_full.sh \
  --tenant-id acme_corp \
  --tenant-name "ACME Corporation" \
  --num-sites 5 \
  --dry-run

# Skip AWS (Snowflake only)
./onboard_tenant_full.sh \
  --tenant-id acme_corp \
  --tenant-name "ACME Corporation" \
  --num-sites 5 \
  --skip-aws

# Skip Snowflake (AWS only)
./onboard_tenant_full.sh \
  --tenant-id acme_corp \
  --tenant-name "ACME Corporation" \
  --num-sites 5 \
  --skip-snowflake
```

### Validation

```bash
# Validate complete tenant setup
./validate_tenant.sh --tenant-id acme_corp

# Validate and send test message
./validate_tenant.sh --tenant-id acme_corp --send-test-message
```

**Validation checks:**
- ✅ Kinesis stream exists and is ACTIVE
- ✅ IAM role exists with correct policies
- ✅ IoT rule exists and is enabled
- ✅ Snowflake database and schemas exist
- ✅ Tenant registered in infrastructure DB
- ✅ Openflow connector registered
- ✅ Openflow role has correct grants

---

  Snowflake Compatibility

All SQL scripts have been validated for % Snowflake compatibility:

 Supported Constraints:
- PRIMARY KEY
- FOREIGN KEY (with `NOT ENFORCED`)
- NOT NULL
- UNIQUE

 Not Supported:
- CHECK constraints (removed from all scripts)

All removed CHECK constraints are documented with comments indicating valid values. Data validation is enforced at the application layer and through business logic.

Note: All FOREIGN KEY constraints use `NOT ENFORCED` as required for Snowflake standard tables. While Snowflake supports unenforced foreign keys for metadata and query optimization, actual enforcement happens at the application layer.

 Prerequisites

 . Snowflake Account
- Edition: Enterprise or higher (required for Dynamic Tables)
- Region: eu-west- (London) recommended for optimal Kinesis integration
- Version: .+ for Dynamic Tables support

 . Required Tools
```bash
 Install SnowSQL CLI
brew install snowflake-snowsql   macOS
 Or download from: https://docs.snowflake.com/en/user-guide/snowsql-install-config.html

 Verify installation
snowsql --version
```

 . AWS Prerequisites
- Kinesis Data Stream created in eu-west-
- IAM role configured for Snowflake cross-account access
- External ID for secure role assumption

 . Credentials
Set environment variables:
```bash
export SNOWFLAKE_ACCOUNT="your-account"
export SNOWFLAKE_USER="your-user"
export AWS_REGION="eu-west-"
```

---

  Critical: Snowflake Variable Naming Convention

This is a common source of errors. Read carefully.

 Two Variable Systems

Our setup uses Snowflake's native variable system (`$variable_name`), NOT SnowSQL's text-replacement system (`&variable_name`).

| Aspect | SnowSQL Text Substitution | Snowflake Session Variables |
|--------|-------------------------|---------------------------|
| Syntax | `&variable_name` | `$variable_name` |
| When set | Before executing SQL (command line) | During SQL execution |
| How it works | Text replacement (literal substitution) | SQL parameter binding |
| Best for | Simple placeholder replacement | Complex SQL with proper typing |
| Used in | Legacy scripts, simple templates | Modern Snowflake scripts (OUR STANDARD) |

  WRONG: Old SnowSQL Syntax
```bash
  DO NOT USE THIS
snowsql -r ACCOUNTADMIN -f script.sql -D tenant_id='my_tenant'
```

In the SQL script:
```sql
--  WRONG - DO NOT DO THIS
SET database_name = 'smdh_tenant_' || '&tenant_id';  -- Syntax error!
WHERE tenant_id = '&tenant_id';                       -- Literal '&tenant_id' string!
```

  CORRECT: Snowflake Native Syntax
```bash
  USE THIS
snowsql -r ACCOUNTADMIN -f script.sql --variable tenant_id='my_tenant'
```

In the SQL script:
```sql
--  CORRECT
SET database_name = 'smdh_tenant_' || $tenant_id;  -- Proper variable concat
WHERE tenant_id = $tenant_id;                       -- Actual value substitution
```

 Key Differences

SnowSQL `-D` flag (text replacement):
- Replaces `&variable_name` with literal text BEFORE Snowflake sees the SQL
- Cannot be used inside expressions like `'&var'` safely
- Causes syntax errors with characters like `||`, `&`, `{`, etc.
-  DO NOT USE IN THIS PROJECT

Snowflake `--variable` flag (native):
- Passes variable as a parameter to Snowflake engine
- Works correctly in expressions: `'prefix_' || $var || '_suffix'`
- Type-safe and properly quoted
-  USE THIS STANDARD

 Common Pitfalls

 . Quoted Variable in String ( WRONG)
```sql
--  This will cause syntax errors
SELECT 'Hello &tenant_id' AS message;
INSERT INTO table VALUES ('&value', &value);
SET db_name = 'smdh_' || '&tenant_id';
```

 . Variable in WHERE Clause ( WRONG)
```sql
--  This will fail
WHERE tenant_id = '&tenant_id';
WHERE status IN ('&status', '&status');
```

 . Correct Pattern ( RIGHT)
```sql
--  Always use $ syntax with --variable flag
SELECT 'Hello ' || $tenant_id AS message;
INSERT INTO table VALUES ($value, $value);
SET db_name = 'smdh_' || $tenant_id;
WHERE tenant_id = $tenant_id;
WHERE status IN ($status, $status);
```

 Implementation Checklist

When creating new Snowflake scripts:

- [ ] Usage comment shows `--variable` flag (NOT `-D`)
  ```bash
   Usage: snowsql -f script.sql --variable tenant_id='value'
  ```

- [ ] All variables use `$variable_name` syntax (NOT `&variable_name`)
  ```sql
  SET var = $my_variable;
  WHERE id = $my_variable;
  SELECT $my_variable || 'suffix';
  ```

- [ ] No quoted variables like `'$var'` - variables aren't strings
  ```sql
  --  WRONG
  WHERE id = '$tenant_id'

  --  CORRECT
  WHERE id = $tenant_id
  ```

- [ ] Test script with actual values to verify proper substitution

 Why This Matters

+ syntax errors appeared when old scripts used `&variable_name` with `-D flags`:
- Snowflake received literal `&` characters in SQL
- Ampersands triggered compiler errors
- String concatenation failed
- All subsequent operations failed

Fixed by converting to `$variable_name` with `--variable` flags:
- All setup scripts now execute successfully
- Variables properly typed and substituted
- String concatenation works correctly
- Full automation achievable

---

 Quick Start - Automated Setup

NEW: Use the automated validation script for a complete, reproducible setup:

```bash
cd infrastructure/snowflake
./validate_setup.sh test_tenant
```

This script will:
.  Drop existing infrastructure (clean slate)
.  Create all core infrastructure
.  Configure shared resources and warehouses
.  Set up Openflow Kinesis connector
.  Create complete tenant database
.  Verify all objects created successfully
.  Generate comprehensive validation report

Time: - minutes for complete setup and validation

Benefits:
- Guaranteed reproducibility (drop and recreate anytime)
- Automatic error detection and reporting
- Log files saved to `/tmp/smdh_.log` for troubleshooting
- Comprehensive verification of all objects

---

 Initial Platform Setup (Manual)

Run these scripts once to set up the platform infrastructure:

 Step  (Optional): Clean Slate
```bash
 Only run this if you want to drop existing infrastructure
snowsql -r ACCOUNTADMIN -f _drop_all.sql
```

 Step : Validate Environment
```bash
snowsql -r ACCOUNTADMIN -f _prerequisites.sql
```

Expected output:
-  Account is in eu-west- region
-  Dynamic Tables supported (Snowflake .+)
-  Current role has CREATE DATABASE privilege

 Step : Create Infrastructure Database
```bash
snowsql -r ACCOUNTADMIN -f _infrastructure_setup.sql
```

Important: All scripts require the ACCOUNTADMIN role. Use `-r ACCOUNTADMIN` or `--rolename ACCOUNTADMIN`.

Creates:
- Database: `smdh_infrastructure`
- Schemas: `tenant_configs`, `monitoring`, `audit`
- Tables: `tenants`, `devices`, `sites`, etc.
- Roles: `smdh_infrastructure_admin`, `smdh_monitoring`

 Step : Create Shared Resources
```bash
snowsql -r ACCOUNTADMIN -f _shared_resources.sql
```

Creates:
- Warehouse: `SMDH_WH` (consolidated single warehouse for all workloads)
- Resource monitor: `smdh_platform_monitor` (cost control)
- Roles: `smdh_tenant_operator`, `smdh_data_engineer`
- Service account: `smdh_automation_svc`

 Step : Configure Openflow Connector (Per-Tenant)

**IMPORTANT: Per-Tenant Stream Architecture**

Each tenant requires their own Kinesis stream and Openflow connector because Openflow cannot filter records from a shared stream.

```bash
 1. Run the SQL script to set up Openflow infrastructure (once)
snowsql -r ACCOUNTADMIN -f sql/core/03_openflow_connector.sql

 2. Create Openflow Deployment and Runtime in Snowsight UI (once)
 See: docs/deployment/Tenant_Onboarding_Guide.md

 3. For each tenant, add a Kinesis connector in Snowsight:
    - Stream: smdh-{tenant_id}-stream
    - Target: SMDH_TENANT_{TENANT_ID}.RAW.SENSOR_READINGS
```

The IAM role uses a wildcard pattern (`smdh-*-stream`) to allow Snowflake to read from any tenant's stream.

---

 Tenant Onboarding

 Automated Onboarding (Recommended)

Use the automated script for fastest onboarding:

```bash
./scripts/onboard_tenant.sh \
  --tenant-id company_a \
  --tenant-name "Company A Manufacturing Ltd" \
  --num-sites  \
  --contact-email contact@companya.com \
  --snowflake-account $SNOWFLAKE_ACCOUNT \
  --snowflake-user $SNOWFLAKE_USER
```

What it does:
. Creates tenant database: `smdh_tenant_company_a`
. Configures  schemas (raw, normalized, aggregated, analytics)
. Creates + tables for data storage
. Sets up  CDC streams for real-time processing
. Creates  automated ETL tasks
. Configures  dynamic tables for live aggregations
. Creates  tenant-specific roles
. Sets up comprehensive monitoring views
. Validates entire setup

Time: - minutes

 Manual Onboarding

For custom setups or troubleshooting, run scripts individually:

```bash
TENANT_ID="company_a"
TENANT_NAME="Company A Manufacturing Ltd"

 Step : Create database
snowsql -a $SNOWFLAKE_ACCOUNT -u $SNOWFLAKE_USER \
  -f tenant/_create_tenant_database.sql \
  -D tenant_id="$TENANT_ID" \
  -D tenant_name="$TENANT_NAME" \
  -D aws_region="eu-west-" \
  -D num_sites=

 Step : Configure schemas
snowsql -a $SNOWFLAKE_ACCOUNT -u $SNOWFLAKE_USER \
  -f tenant/_create_schemas.sql \
  -D tenant_id="$TENANT_ID"

 Step : Create tables
snowsql -a $SNOWFLAKE_ACCOUNT -u $SNOWFLAKE_USER \
  -f tenant/_create_tables.sql \
  -D tenant_id="$TENANT_ID"

 Step : Create streams
snowsql -a $SNOWFLAKE_ACCOUNT -u $SNOWFLAKE_USER \
  -f tenant/_create_streams.sql \
  -D tenant_id="$TENANT_ID"

 Step : Create tasks
snowsql -a $SNOWFLAKE_ACCOUNT -u $SNOWFLAKE_USER \
  -f tenant/_create_tasks.sql \
  -D tenant_id="$TENANT_ID"

 Step : Create dynamic tables
snowsql -a $SNOWFLAKE_ACCOUNT -u $SNOWFLAKE_USER \
  -f tenant/_create_dynamic_tables.sql \
  -D tenant_id="$TENANT_ID"

 Step : Configure RBAC
snowsql -a $SNOWFLAKE_ACCOUNT -u $SNOWFLAKE_USER \
  -f tenant/_create_roles.sql \
  -D tenant_id="$TENANT_ID"

 Step : Setup monitoring
snowsql -a $SNOWFLAKE_ACCOUNT -u $SNOWFLAKE_USER \
  -f tenant/_create_monitoring.sql \
  -D tenant_id="$TENANT_ID"
```

 Validation

After onboarding, validate the setup:

```bash
snowsql -a $SNOWFLAKE_ACCOUNT -u $SNOWFLAKE_USER \
  -f scripts/validate_tenant.sql \
  -D tenant_id="company_a"
```

Checks:
-  Database and schemas exist
-  All tables created
-  Streams configured and not stale
-  Tasks running
-  Dynamic tables refreshing
-  Roles created with proper permissions
-  Monitoring views functional

---

 Tenant Management

 Create a User

```sql
USE DATABASE smdh_tenant_company_a;
USE SCHEMA analytics;

CALL sp_create_tenant_user(
    'john_smith',                  -- Username
    'john@companya.com',           -- Email
    'data_analyst',                -- Role type
    'SMDH_WH'                      -- Default warehouse
);
```

Available role types:
- `admin` - Full access to tenant database
- `user` - Standard read/write access
- `readonly` - Read-only for reporting
- `data_engineer` - ETL development
- `data_analyst` - Analytics development
- `api_service` - Programmatic access
- `auditor` - Compliance/audit access

 Health Check

```sql
USE DATABASE smdh_tenant_company_a;
CALL analytics.sp_health_check();
```

 Monitor Data Ingestion

```sql
-- Real-time summary
SELECT  FROM analytics.v_system_summary;

-- Ingestion metrics
SELECT  FROM analytics.v_ingestion_monitoring;

-- Pipeline health
SELECT  FROM analytics.v_pipeline_health;

-- Active alerts
SELECT  FROM analytics.v_active_alerts;
```

 Pause/Resume Ingestion

```sql
-- Pause all tasks (stops data processing)
CALL analytics.sp_suspend_all_tasks();

-- Resume all tasks
CALL analytics.sp_resume_all_tasks();
```

 Cost Monitoring

```sql
-- Daily costs (last  days)
SELECT
    date,
    SUM(estimated_compute_cost_usd) AS compute_cost,
    SUM(estimated_storage_cost_usd) AS storage_cost,
    SUM(estimated_compute_cost_usd + estimated_storage_cost_usd) AS total_cost
FROM analytics.v_cost_monitoring
WHERE date >= DATEADD(day, -, CURRENT_DATE())
GROUP BY date
ORDER BY date DESC;

-- Warehouse utilization
SELECT  FROM smdh_infrastructure.monitoring.v_warehouse_utilization
WHERE warehouse_name LIKE 'smdh_%'
ORDER BY credits_used DESC;
```

---

 Data Pipeline

 Data Flow

```
IoT Device (MQTT)
    ↓
AWS IoT Core
    ↓
IoT Rules Engine
    ↓
Kinesis Data Stream (partition by tenant_id)
    ↓
Snowflake Openflow Connector
    ↓
RAW.SENSOR_READINGS (via Pipe)
    ↓
Stream: sensor_readings_stream (CDC)
    ↓
Task: task_normalize_sensor_readings ( min)
    ↓
NORMALIZED.SENSOR_METRICS
    ↓
Stream: sensor_metrics_stream (CDC)
    ↓
Task: task_aggregate_hourly ( min) → AGGREGATED.SENSOR_METRICS_HOURLY
Task: task_aggregate_daily (daily)  → AGGREGATED.SENSOR_METRICS_DAILY
Dynamic Tables (- min lag)        → Real-time dashboards
```

 Key Objects

Streams (CDC):
- `sensor_readings_stream` - New raw data
- `sensor_metrics_stream` - Normalized metrics
- `device_status_stream` - Device health events

Tasks (Automated ETL):
- `task_normalize_sensor_readings` - Raw → Normalized (every  min)
- `task_aggregate_hourly` - Hourly rollups (every  min)
- `task_aggregate_daily` - Daily rollups (: UTC)
- `task_process_device_status` - Device event processing (every  min)
- `task_update_device_registry` - Device metadata sync (every  min)

Dynamic Tables (Real-Time):
- `dt_sensor_metrics_realtime` - Last  minutes (-min lag)
- `dt_device_health_current` - Current device status (-min lag)
- `dt_site_performance_current` - Site KPIs (-min lag)
- `dt_hourly_trends_h` - -hour trends (-min lag)
- `dt_alert_conditions` - Real-time alerting (-min lag)
- `dt_data_quality_summary` - Quality monitoring (-min lag)

---

 Troubleshooting

 Tasks Not Running

```sql
-- Check task status
SELECT  FROM analytics.v_task_status;

-- Check task history for errors
SELECT  FROM analytics.v_task_history
WHERE state = 'FAILED'
ORDER BY scheduled_time DESC
LIMIT ;

-- Resume suspended tasks
CALL analytics.sp_resume_all_tasks();
```

 Stream Backlog

```sql
-- Check stream lag
SELECT  FROM analytics.v_stream_lag;

-- If backlog is high, check task execution
SELECT  FROM analytics.v_task_history
WHERE task_name LIKE '%normalize%'
ORDER BY scheduled_time DESC;
```

 No Data Ingestion

```sql
-- Check recent data
SELECT
    COUNT() AS recent_readings,
    MAX(ingestion_timestamp) AS last_ingestion,
    DATEDIFF(minute, MAX(ingestion_timestamp), CURRENT_TIMESTAMP()) AS minutes_ago
FROM raw.sensor_readings
WHERE ingestion_timestamp >= DATEADD(hour, -, CURRENT_TIMESTAMP());

-- Check pipe status
SELECT SYSTEM$PIPE_STATUS('pipe_name');

-- Verify Kinesis connector
DESC INTEGRATION smdh_kinesis_integration;
```

 High Costs

```sql
-- Check warehouse usage
SELECT * FROM smdh_infrastructure.monitoring.v_warehouse_utilization
WHERE hour >= DATEADD(day, -7, CURRENT_TIMESTAMP())
ORDER BY credits_used DESC;

-- Suspend warehouse when not needed
ALTER WAREHOUSE SMDH_WH SUSPEND;

-- Adjust auto-suspend time (default is 5 minutes)
ALTER WAREHOUSE SMDH_WH SET AUTO_SUSPEND = 60;  -- 1 minute
```

---

 Best Practices

 Security

. Use Key-Pair Authentication for service accounts
. Enable MFA for all human users
. Rotate credentials regularly (automated via Secrets Manager)
. Audit access via `audit.user_access_log` table
. Restrict IP ranges if possible (network policies)

 Performance

. Monitor warehouse utilization - Right-size warehouses based on usage
. Check query performance - Optimize slow queries via `v_query_performance`
. Review clustering - Tables are pre-clustered by date and sensor_id
. Use result cache - Identical queries return cached results
. Leverage dynamic tables - Avoid redundant aggregation queries

 Cost Optimization

. Set auto-suspend - All warehouses suspend after idle time
. Use resource monitors - Alert at %, %, suspend at %
. Monitor storage growth - Regularly check `v_storage_monitoring`
. Adjust data retention - Balance retention with storage costs
. Review underused objects - Drop unused tables/views

 Data Quality

. Monitor quality scores - Check `v_data_quality_monitoring` daily
. Define quality rules - Use `data_quality_rules` table
. Alert on bad data - Dynamic table `dt_alert_conditions` detects issues
. Validate ingestion - Check `v_ingestion_monitoring` for anomalies

---

 Maintenance Tasks

 Daily
-  Check `sp_health_check()` for any FAIL statuses
-  Review active alerts in `v_active_alerts`
-  Monitor data ingestion in `v_ingestion_monitoring`

 Weekly
-  Review cost trends in `v_cost_monitoring`
-  Check task execution history for failures
-  Validate storage growth is within expectations
-  Review slow queries in `v_query_performance`

 Monthly
-  Review user access logs for suspicious activity
-  Update data quality rules based on patterns
-  Optimize warehouse sizes based on usage
-  Archive or drop old data if retention allows

---

 Support

 Common Queries

. List all tenants:
```sql
SELECT  FROM smdh_infrastructure.tenant_configs.tenants;
```

. Check device connectivity:
```sql
SELECT  FROM smdh_infrastructure.monitoring.v_device_connectivity;
```

. View platform costs:
```sql
SELECT  FROM smdh_infrastructure.monitoring.v_daily_costs
WHERE usage_date >= DATEADD(day, -, CURRENT_DATE());
```

. Export tenant data:
```sql
COPY INTO @stage_name
FROM (SELECT  FROM raw.sensor_readings WHERE timestamp >= '--')
FILE_FORMAT = (TYPE = 'PARQUET');
```

 Documentation

- [Snowflake Streams](https://docs.snowflake.com/en/user-guide/streams.html)
- [Snowflake Tasks](https://docs.snowflake.com/en/user-guide/tasks-intro.html)
- [Dynamic Tables](https://docs.snowflake.com/en/user-guide/dynamic-tables-about.html)
- [Snowflake Openflow](https://docs.snowflake.com/en/user-guide/data-load-snowpipe-streaming-overview.html)

 Contact

For issues or questions:
- Platform Team: platform@smdh.com
- Documentation: See `/docs` folder
- GitHub Issues: https://github.com/your-org/smdh/issues

---

 Summary

You now have a complete, automated Snowflake infrastructure for the SMDH platform with:

 Multi-tenant isolation - Separate databases per tenant
 Real-time processing - Sub-minute latency with streams and dynamic tables
 Automated ETL - Self-managing tasks with dependency handling
 Cost controls - Resource monitors and auto-suspend warehouses
 Comprehensive monitoring - Health checks, dashboards, and alerts
 Scalable architecture - Ready for + tenants and millions of daily messages
 Enterprise security - RBAC, audit logs, encryption at rest and in transit

Next Steps: Run the initial platform setup scripts, then onboard your first tenant!
