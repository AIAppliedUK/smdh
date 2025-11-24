
# SMDH Snowflake Setup Guide

Complete setup guide for the Smart Manufacturing Data Hub (SMDH) Snowflake infrastructure and tenant onboarding.

## Overview

This directory contains all SQL scripts and automation tools needed to:
- Set up the core SMDH infrastructure in Snowflake
- Configure Kinesis integration via Snowflake Openflow
- Onboard new tenants with complete isolation
- Manage tenant lifecycle (onboarding, monitoring, offboarding)

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                   SMDH Snowflake Platform                    │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ Infrastructure Database (smdh_infrastructure)        │  │
│  │ - Tenant registry                                    │  │
│  │ - Device metadata                                    │  │
│  │ - Platform monitoring                                │  │
│  │ - Audit logs                                         │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ Tenant Database (per tenant)                         │  │
│  │ - RAW: Ingested data from Kinesis                    │  │
│  │ - NORMALIZED: Validated and flattened                │  │
│  │ - AGGREGATED: Pre-computed metrics                   │  │
│  │ - ANALYTICS: Views and dashboards                    │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ Real-Time Pipeline                                   │  │
│  │ Kinesis → Streams → Tasks → Dynamic Tables          │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

## Directory Structure

```
infrastructure/snowflake/
├── 00_drop_all.sql               # Clean infrastructure teardown
├── 00_prerequisites.sql          # Environment validation
├── 01_infrastructure_setup.sql   # Core infrastructure
├── 02_shared_resources.sql       # Warehouses and roles
├── 03_openflow_connector.sql     # Kinesis integration
├── validate_setup.sh             # Complete setup validation script
├── tenant/
│   ├── 10_create_tenant_database.sql    # Tenant database creation
│   ├── 11_create_schemas.sql            # Schema configuration
│   ├── 12_create_tables.sql             # Table definitions
│   ├── 13_create_streams.sql            # CDC streams
│   ├── 14_create_tasks.sql              # ETL automation
│   ├── 15_create_dynamic_tables.sql     # Real-time aggregations
│   ├── 16_create_roles.sql              # RBAC configuration
│   └── 17_create_monitoring.sql         # Monitoring setup
├── scripts/
│   ├── onboard_tenant.sh         # Automated onboarding
│   └── validate_tenant.sql       # Validation checks
└── README.md                      # This file
```

## ⚡ Snowflake Compatibility

All SQL scripts have been validated for 100% Snowflake compatibility:

**✅ Supported Constraints:**
- PRIMARY KEY
- FOREIGN KEY (with `NOT ENFORCED`)
- NOT NULL
- UNIQUE

**❌ Not Supported:**
- CHECK constraints (removed from all scripts)

All removed CHECK constraints are documented with comments indicating valid values. Data validation is enforced at the application layer and through business logic.

**Note:** All FOREIGN KEY constraints use `NOT ENFORCED` as required for Snowflake standard tables. While Snowflake supports unenforced foreign keys for metadata and query optimization, actual enforcement happens at the application layer.

## Prerequisites

### 1. Snowflake Account
- **Edition**: Enterprise or higher (required for Dynamic Tables)
- **Region**: eu-west-2 (London) recommended for optimal Kinesis integration
- **Version**: 7.0+ for Dynamic Tables support

### 2. Required Tools
```bash
# Install SnowSQL CLI
brew install snowflake-snowsql  # macOS
# Or download from: https://docs.snowflake.com/en/user-guide/snowsql-install-config.html

# Verify installation
snowsql --version
```

### 3. AWS Prerequisites
- Kinesis Data Stream created in eu-west-2
- IAM role configured for Snowflake cross-account access
- External ID for secure role assumption

### 4. Credentials
Set environment variables:
```bash
export SNOWFLAKE_ACCOUNT="your-account"
export SNOWFLAKE_USER="your-user"
export AWS_REGION="eu-west-2"
```

---

## 🚨 Critical: Snowflake Variable Naming Convention

**This is a common source of errors. Read carefully.**

### Two Variable Systems

Our setup uses **Snowflake's native variable system** (`$variable_name`), NOT SnowSQL's text-replacement system (`&variable_name`).

| Aspect | SnowSQL Text Substitution | Snowflake Session Variables |
|--------|-------------------------|---------------------------|
| **Syntax** | `&variable_name` | `$variable_name` |
| **When set** | Before executing SQL (command line) | During SQL execution |
| **How it works** | Text replacement (literal substitution) | SQL parameter binding |
| **Best for** | Simple placeholder replacement | Complex SQL with proper typing |
| **Used in** | Legacy scripts, simple templates | Modern Snowflake scripts (OUR STANDARD) |

### ❌ WRONG: Old SnowSQL Syntax
```bash
# ❌ DO NOT USE THIS
snowsql -r ACCOUNTADMIN -f script.sql -D tenant_id='my_tenant'
```

In the SQL script:
```sql
-- ❌ WRONG - DO NOT DO THIS
SET database_name = 'smdh_tenant_' || '&tenant_id';  -- Syntax error!
WHERE tenant_id = '&tenant_id';                       -- Literal '&tenant_id' string!
```

### ✅ CORRECT: Snowflake Native Syntax
```bash
# ✅ USE THIS
snowsql -r ACCOUNTADMIN -f script.sql --variable tenant_id='my_tenant'
```

In the SQL script:
```sql
-- ✅ CORRECT
SET database_name = 'smdh_tenant_' || $tenant_id;  -- Proper variable concat
WHERE tenant_id = $tenant_id;                       -- Actual value substitution
```

### Key Differences

**SnowSQL `-D` flag (text replacement):**
- Replaces `&variable_name` with literal text BEFORE Snowflake sees the SQL
- Cannot be used inside expressions like `'&var'` safely
- Causes syntax errors with characters like `||`, `&`, `{`, etc.
- ❌ **DO NOT USE IN THIS PROJECT**

**Snowflake `--variable` flag (native):**
- Passes variable as a parameter to Snowflake engine
- Works correctly in expressions: `'prefix_' || $var || '_suffix'`
- Type-safe and properly quoted
- ✅ **USE THIS STANDARD**

### Common Pitfalls

#### 1. Quoted Variable in String (❌ WRONG)
```sql
-- ❌ This will cause syntax errors
SELECT 'Hello &tenant_id' AS message;
INSERT INTO table VALUES ('&value1', &value2);
SET db_name = 'smdh_' || '&tenant_id';
```

#### 2. Variable in WHERE Clause (❌ WRONG)
```sql
-- ❌ This will fail
WHERE tenant_id = '&tenant_id';
WHERE status IN ('&status1', '&status2');
```

#### 3. Correct Pattern (✅ RIGHT)
```sql
-- ✅ Always use $ syntax with --variable flag
SELECT 'Hello ' || $tenant_id AS message;
INSERT INTO table VALUES ($value1, $value2);
SET db_name = 'smdh_' || $tenant_id;
WHERE tenant_id = $tenant_id;
WHERE status IN ($status1, $status2);
```

### Implementation Checklist

When creating new Snowflake scripts:

- [ ] **Usage comment** shows `--variable` flag (NOT `-D`)
  ```bash
  # Usage: snowsql -f script.sql --variable tenant_id='value'
  ```

- [ ] **All variables** use `$variable_name` syntax (NOT `&variable_name`)
  ```sql
  SET var = $my_variable;
  WHERE id = $my_variable;
  SELECT $my_variable || 'suffix';
  ```

- [ ] **No quoted variables** like `'$var'` - variables aren't strings
  ```sql
  -- ❌ WRONG
  WHERE id = '$tenant_id'

  -- ✅ CORRECT
  WHERE id = $tenant_id
  ```

- [ ] **Test script** with actual values to verify proper substitution

### Why This Matters

**200+ syntax errors appeared** when old scripts used `&variable_name` with `-D flags`:
- Snowflake received literal `&` characters in SQL
- Ampersands triggered compiler errors
- String concatenation failed
- All subsequent operations failed

**Fixed by converting to `$variable_name` with `--variable` flags:**
- All setup scripts now execute successfully
- Variables properly typed and substituted
- String concatenation works correctly
- Full automation achievable

---

## Quick Start - Automated Setup

**NEW:** Use the automated validation script for a complete, reproducible setup:

```bash
cd infrastructure/snowflake
./validate_setup.sh test_tenant
```

This script will:
1. ✅ Drop existing infrastructure (clean slate)
2. ✅ Create all core infrastructure
3. ✅ Configure shared resources and warehouses
4. ✅ Set up Openflow Kinesis connector
5. ✅ Create complete tenant database
6. ✅ Verify all objects created successfully
7. ✅ Generate comprehensive validation report

**Time:** 5-10 minutes for complete setup and validation

**Benefits:**
- Guaranteed reproducibility (drop and recreate anytime)
- Automatic error detection and reporting
- Log files saved to `/tmp/smdh_*.log` for troubleshooting
- Comprehensive verification of all objects

---

## Initial Platform Setup (Manual)

Run these scripts **once** to set up the platform infrastructure:

### Step 0 (Optional): Clean Slate
```bash
# Only run this if you want to drop existing infrastructure
snowsql -r ACCOUNTADMIN -f 00_drop_all.sql
```

### Step 1: Validate Environment
```bash
snowsql -r ACCOUNTADMIN -f 00_prerequisites.sql
```

**Expected output:**
- ✓ Account is in eu-west-2 region
- ✓ Dynamic Tables supported (Snowflake 7.0+)
- ✓ Current role has CREATE DATABASE privilege

### Step 2: Create Infrastructure Database
```bash
snowsql -r ACCOUNTADMIN -f 01_infrastructure_setup.sql
```

**Important:** All scripts require the ACCOUNTADMIN role. Use `-r ACCOUNTADMIN` or `--rolename ACCOUNTADMIN`.

**Creates:**
- Database: `smdh_infrastructure`
- Schemas: `tenant_configs`, `monitoring`, `audit`
- Tables: `tenants`, `devices`, `sites`, etc.
- Roles: `smdh_infrastructure_admin`, `smdh_monitoring`

### Step 3: Create Shared Resources
```bash
snowsql -r ACCOUNTADMIN -f 02_shared_resources.sql
```

**Creates:**
- Warehouses: `smdh_streaming_wh`, `smdh_etl_wh`, `smdh_analytics_wh`, etc.
- Resource monitor: `smdh_platform_monitor` (cost control)
- Roles: `smdh_tenant_operator`, `smdh_data_engineer`
- Service account: `smdh_automation_svc`

### Step 4: Configure Kinesis Integration
```bash
# Get AWS IAM role details first
aws iam get-role --role-name smdh-snowflake-kinesis-role

# Run Openflow connector setup
snowsql -r ACCOUNTADMIN -f 03_openflow_connector.sql \
  -D aws_iam_role_arn='arn:aws:iam::123456789012:role/smdh-snowflake-kinesis-role' \
  -D aws_external_id='your-external-id' \
  -D kinesis_stream_arn='arn:aws:kinesis:eu-west-2:123456789012:stream/smdh-sensor-data-stream'
```

**Important:** After running this script, copy the `STORAGE_AWS_IAM_USER_ARN` and `STORAGE_AWS_EXTERNAL_ID` from the output and update your AWS IAM role trust policy.

---

## Tenant Onboarding

### Automated Onboarding (Recommended)

Use the automated script for fastest onboarding:

```bash
./scripts/onboard_tenant.sh \
  --tenant-id company_a \
  --tenant-name "Company A Manufacturing Ltd" \
  --num-sites 5 \
  --contact-email contact@companya.com \
  --snowflake-account $SNOWFLAKE_ACCOUNT \
  --snowflake-user $SNOWFLAKE_USER
```

**What it does:**
1. Creates tenant database: `smdh_tenant_company_a`
2. Configures 4 schemas (raw, normalized, aggregated, analytics)
3. Creates 10+ tables for data storage
4. Sets up 6 CDC streams for real-time processing
5. Creates 5 automated ETL tasks
6. Configures 6 dynamic tables for live aggregations
7. Creates 7 tenant-specific roles
8. Sets up comprehensive monitoring views
9. Validates entire setup

**Time:** 5-10 minutes

### Manual Onboarding

For custom setups or troubleshooting, run scripts individually:

```bash
TENANT_ID="company_a"
TENANT_NAME="Company A Manufacturing Ltd"

# Step 1: Create database
snowsql -a $SNOWFLAKE_ACCOUNT -u $SNOWFLAKE_USER \
  -f tenant/10_create_tenant_database.sql \
  -D tenant_id="$TENANT_ID" \
  -D tenant_name="$TENANT_NAME" \
  -D aws_region="eu-west-2" \
  -D num_sites=5

# Step 2: Configure schemas
snowsql -a $SNOWFLAKE_ACCOUNT -u $SNOWFLAKE_USER \
  -f tenant/11_create_schemas.sql \
  -D tenant_id="$TENANT_ID"

# Step 3: Create tables
snowsql -a $SNOWFLAKE_ACCOUNT -u $SNOWFLAKE_USER \
  -f tenant/12_create_tables.sql \
  -D tenant_id="$TENANT_ID"

# Step 4: Create streams
snowsql -a $SNOWFLAKE_ACCOUNT -u $SNOWFLAKE_USER \
  -f tenant/13_create_streams.sql \
  -D tenant_id="$TENANT_ID"

# Step 5: Create tasks
snowsql -a $SNOWFLAKE_ACCOUNT -u $SNOWFLAKE_USER \
  -f tenant/14_create_tasks.sql \
  -D tenant_id="$TENANT_ID"

# Step 6: Create dynamic tables
snowsql -a $SNOWFLAKE_ACCOUNT -u $SNOWFLAKE_USER \
  -f tenant/15_create_dynamic_tables.sql \
  -D tenant_id="$TENANT_ID"

# Step 7: Configure RBAC
snowsql -a $SNOWFLAKE_ACCOUNT -u $SNOWFLAKE_USER \
  -f tenant/16_create_roles.sql \
  -D tenant_id="$TENANT_ID"

# Step 8: Setup monitoring
snowsql -a $SNOWFLAKE_ACCOUNT -u $SNOWFLAKE_USER \
  -f tenant/17_create_monitoring.sql \
  -D tenant_id="$TENANT_ID"
```

### Validation

After onboarding, validate the setup:

```bash
snowsql -a $SNOWFLAKE_ACCOUNT -u $SNOWFLAKE_USER \
  -f scripts/validate_tenant.sql \
  -D tenant_id="company_a"
```

**Checks:**
- ✓ Database and schemas exist
- ✓ All tables created
- ✓ Streams configured and not stale
- ✓ Tasks running
- ✓ Dynamic tables refreshing
- ✓ Roles created with proper permissions
- ✓ Monitoring views functional

---

## Tenant Management

### Create a User

```sql
USE DATABASE smdh_tenant_company_a;
USE SCHEMA analytics;

CALL sp_create_tenant_user(
    'john_smith',                  -- Username
    'john@companya.com',           -- Email
    'data_analyst',                -- Role type
    'smdh_analytics_wh'            -- Default warehouse
);
```

**Available role types:**
- `admin` - Full access to tenant database
- `user` - Standard read/write access
- `readonly` - Read-only for reporting
- `data_engineer` - ETL development
- `data_analyst` - Analytics development
- `api_service` - Programmatic access
- `auditor` - Compliance/audit access

### Health Check

```sql
USE DATABASE smdh_tenant_company_a;
CALL analytics.sp_health_check();
```

### Monitor Data Ingestion

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

### Pause/Resume Ingestion

```sql
-- Pause all tasks (stops data processing)
CALL analytics.sp_suspend_all_tasks();

-- Resume all tasks
CALL analytics.sp_resume_all_tasks();
```

### Cost Monitoring

```sql
-- Daily costs (last 30 days)
SELECT
    date,
    SUM(estimated_compute_cost_usd) AS compute_cost,
    SUM(estimated_storage_cost_usd) AS storage_cost,
    SUM(estimated_compute_cost_usd + estimated_storage_cost_usd) AS total_cost
FROM analytics.v_cost_monitoring
WHERE date >= DATEADD(day, -30, CURRENT_DATE())
GROUP BY date
ORDER BY date DESC;

-- Warehouse utilization
SELECT * FROM smdh_infrastructure.monitoring.v_warehouse_utilization
WHERE warehouse_name LIKE 'smdh_%'
ORDER BY credits_used DESC;
```

---

## Data Pipeline

### Data Flow

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
Task: task_normalize_sensor_readings (1 min)
    ↓
NORMALIZED.SENSOR_METRICS
    ↓
Stream: sensor_metrics_stream (CDC)
    ↓
Task: task_aggregate_hourly (5 min) → AGGREGATED.SENSOR_METRICS_HOURLY
Task: task_aggregate_daily (daily)  → AGGREGATED.SENSOR_METRICS_DAILY
Dynamic Tables (1-10 min lag)        → Real-time dashboards
```

### Key Objects

**Streams (CDC):**
- `sensor_readings_stream` - New raw data
- `sensor_metrics_stream` - Normalized metrics
- `device_status_stream` - Device health events

**Tasks (Automated ETL):**
- `task_normalize_sensor_readings` - Raw → Normalized (every 1 min)
- `task_aggregate_hourly` - Hourly rollups (every 5 min)
- `task_aggregate_daily` - Daily rollups (01:00 UTC)
- `task_process_device_status` - Device event processing (every 2 min)
- `task_update_device_registry` - Device metadata sync (every 10 min)

**Dynamic Tables (Real-Time):**
- `dt_sensor_metrics_realtime` - Last 15 minutes (1-min lag)
- `dt_device_health_current` - Current device status (2-min lag)
- `dt_site_performance_current` - Site KPIs (5-min lag)
- `dt_hourly_trends_24h` - 24-hour trends (10-min lag)
- `dt_alert_conditions` - Real-time alerting (1-min lag)
- `dt_data_quality_summary` - Quality monitoring (5-min lag)

---

## Troubleshooting

### Tasks Not Running

```sql
-- Check task status
SELECT * FROM analytics.v_task_status;

-- Check task history for errors
SELECT * FROM analytics.v_task_history
WHERE state = 'FAILED'
ORDER BY scheduled_time DESC
LIMIT 10;

-- Resume suspended tasks
CALL analytics.sp_resume_all_tasks();
```

### Stream Backlog

```sql
-- Check stream lag
SELECT * FROM analytics.v_stream_lag;

-- If backlog is high, check task execution
SELECT * FROM analytics.v_task_history
WHERE task_name LIKE '%normalize%'
ORDER BY scheduled_time DESC;
```

### No Data Ingestion

```sql
-- Check recent data
SELECT
    COUNT(*) AS recent_readings,
    MAX(ingestion_timestamp) AS last_ingestion,
    DATEDIFF(minute, MAX(ingestion_timestamp), CURRENT_TIMESTAMP()) AS minutes_ago
FROM raw.sensor_readings
WHERE ingestion_timestamp >= DATEADD(hour, -1, CURRENT_TIMESTAMP());

-- Check pipe status
SELECT SYSTEM$PIPE_STATUS('pipe_name');

-- Verify Kinesis connector
DESC INTEGRATION smdh_kinesis_integration;
```

### High Costs

```sql
-- Check warehouse usage
SELECT * FROM smdh_infrastructure.monitoring.v_warehouse_utilization
WHERE hour >= DATEADD(day, -7, CURRENT_TIMESTAMP())
ORDER BY credits_used DESC;

-- Suspend non-essential warehouses
ALTER WAREHOUSE smdh_dev_wh SUSPEND;

-- Adjust auto-suspend time
ALTER WAREHOUSE smdh_analytics_wh SET AUTO_SUSPEND = 60;  -- 1 minute
```

---

## Best Practices

### Security

1. **Use Key-Pair Authentication** for service accounts
2. **Enable MFA** for all human users
3. **Rotate credentials** regularly (automated via Secrets Manager)
4. **Audit access** via `audit.user_access_log` table
5. **Restrict IP ranges** if possible (network policies)

### Performance

1. **Monitor warehouse utilization** - Right-size warehouses based on usage
2. **Check query performance** - Optimize slow queries via `v_query_performance`
3. **Review clustering** - Tables are pre-clustered by date and sensor_id
4. **Use result cache** - Identical queries return cached results
5. **Leverage dynamic tables** - Avoid redundant aggregation queries

### Cost Optimization

1. **Set auto-suspend** - All warehouses suspend after idle time
2. **Use resource monitors** - Alert at 75%, 90%, suspend at 100%
3. **Monitor storage growth** - Regularly check `v_storage_monitoring`
4. **Adjust data retention** - Balance retention with storage costs
5. **Review underused objects** - Drop unused tables/views

### Data Quality

1. **Monitor quality scores** - Check `v_data_quality_monitoring` daily
2. **Define quality rules** - Use `data_quality_rules` table
3. **Alert on bad data** - Dynamic table `dt_alert_conditions` detects issues
4. **Validate ingestion** - Check `v_ingestion_monitoring` for anomalies

---

## Maintenance Tasks

### Daily
- ✓ Check `sp_health_check()` for any FAIL statuses
- ✓ Review active alerts in `v_active_alerts`
- ✓ Monitor data ingestion in `v_ingestion_monitoring`

### Weekly
- ✓ Review cost trends in `v_cost_monitoring`
- ✓ Check task execution history for failures
- ✓ Validate storage growth is within expectations
- ✓ Review slow queries in `v_query_performance`

### Monthly
- ✓ Review user access logs for suspicious activity
- ✓ Update data quality rules based on patterns
- ✓ Optimize warehouse sizes based on usage
- ✓ Archive or drop old data if retention allows

---

## Support

### Common Queries

**1. List all tenants:**
```sql
SELECT * FROM smdh_infrastructure.tenant_configs.tenants;
```

**2. Check device connectivity:**
```sql
SELECT * FROM smdh_infrastructure.monitoring.v_device_connectivity;
```

**3. View platform costs:**
```sql
SELECT * FROM smdh_infrastructure.monitoring.v_daily_costs
WHERE usage_date >= DATEADD(day, -30, CURRENT_DATE());
```

**4. Export tenant data:**
```sql
COPY INTO @stage_name
FROM (SELECT * FROM raw.sensor_readings WHERE timestamp >= '2024-01-01')
FILE_FORMAT = (TYPE = 'PARQUET');
```

### Documentation

- [Snowflake Streams](https://docs.snowflake.com/en/user-guide/streams.html)
- [Snowflake Tasks](https://docs.snowflake.com/en/user-guide/tasks-intro.html)
- [Dynamic Tables](https://docs.snowflake.com/en/user-guide/dynamic-tables-about.html)
- [Snowflake Openflow](https://docs.snowflake.com/en/user-guide/data-load-snowpipe-streaming-overview.html)

### Contact

For issues or questions:
- Platform Team: platform@smdh.com
- Documentation: See `/docs` folder
- GitHub Issues: https://github.com/your-org/smdh/issues

---

## Summary

You now have a complete, automated Snowflake infrastructure for the SMDH platform with:

✅ **Multi-tenant isolation** - Separate databases per tenant
✅ **Real-time processing** - Sub-minute latency with streams and dynamic tables
✅ **Automated ETL** - Self-managing tasks with dependency handling
✅ **Cost controls** - Resource monitors and auto-suspend warehouses
✅ **Comprehensive monitoring** - Health checks, dashboards, and alerts
✅ **Scalable architecture** - Ready for 30+ tenants and millions of daily messages
✅ **Enterprise security** - RBAC, audit logs, encryption at rest and in transit

**Next Steps:** Run the initial platform setup scripts, then onboard your first tenant!
