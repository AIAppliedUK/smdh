# CLAUDE.md - Project Guidelines for AI Assistants

## Project Overview
SMDH (Smart Monitoring Data Hub) - IoT data platform connecting AWS IoT Core to Snowflake for multi-tenant sensor data processing.

## Snowflake SQL Scripting Rules

### Variable Substitution
1. **SnowSQL command-line variables** use `--variable name=value` and are accessed via `&name` in SQL
2. **Session variables** are set with `SET var = value;` and accessed via `$var`
3. **Convert SnowSQL vars to session vars** at script start:
   ```sql
   !set variable_substitution=true
   SET tenant_id = '&tenant_id';
   ```

### Critical Constraints - DO NOT VIOLATE

1. **DEFAULT clause limitation**: Session variables (`$var`) CANNOT be used in DEFAULT clauses
   ```sql
   -- WRONG - Will cause silent failure
   tenant_id VARCHAR(100) NOT NULL DEFAULT $tenant_id,

   -- CORRECT - Set value at insert time via application/pipeline
   tenant_id VARCHAR(100) NOT NULL,
   ```

2. **CREATE TASK syntax order** (must follow this exact order):
   ```sql
   CREATE OR REPLACE TASK task_name
       WAREHOUSE = warehouse_name
       SCHEDULE = 'schedule_expression'
       COMMENT = 'description'           -- COMMENT before WHEN
       AFTER predecessor_task            -- optional
       WHEN condition                    -- WHEN after COMMENT
   AS
       sql_statement;
   ```

3. **Cross-schema task predecessors NOT allowed**:
   ```sql
   -- WRONG - Tasks can only have predecessors from same schema
   CREATE TASK normalized.task_aggregate_hourly
       AFTER raw.task_normalize_sensor_readings  -- ERROR!

   -- CORRECT - Use WHEN SYSTEM$STREAM_HAS_DATA() instead
   CREATE TASK normalized.task_aggregate_hourly
       WHEN SYSTEM$STREAM_HAS_DATA('sensor_metrics_stream')
   ```

4. **Schema context for ALTER TASK**: Always use fully qualified names
   ```sql
   -- WRONG - May look in wrong schema
   ALTER TASK task_normalize_sensor_readings RESUME;

   -- CORRECT - Explicit schema
   ALTER TASK raw.task_normalize_sensor_readings RESUME;
   ```

5. **INFORMATION_SCHEMA limitations**:
   - `INFORMATION_SCHEMA.TASKS` and `INFORMATION_SCHEMA.STREAMS` don't exist at database level
   - Use `SNOWFLAKE.ACCOUNT_USAGE.TASKS` and `SNOWFLAKE.ACCOUNT_USAGE.STREAMS` instead
   - Or use `SHOW STREAMS/TASKS` commands and query results

6. **Shell variable syntax** (`${var}`) is NOT valid in SQL:
   ```sql
   -- WRONG
   USE DATABASE smdh_tenant_${tenant_id};

   -- CORRECT - Use IDENTIFIER() with session variable
   SET database_name = 'smdh_tenant_' || $tenant_id;
   USE DATABASE IDENTIFIER($database_name);
   ```

7. **DATA_RETENTION_TIME_IN_DAYS** - Standard edition limit is 90 days max:
   ```sql
   -- WRONG - Will fail on Standard edition
   DATA_RETENTION_TIME_IN_DAYS = 365

   -- CORRECT
   DATA_RETENTION_TIME_IN_DAYS = 90
   ```

8. **PARSE_JSON() cannot be used in VALUES clause**:
   ```sql
   -- WRONG - SQL compilation error
   INSERT INTO my_table (col1, payload)
   VALUES ('value', PARSE_JSON('{"key": "value"}'));

   -- CORRECT - Use INSERT...SELECT
   INSERT INTO my_table (col1, payload)
   SELECT 'value', PARSE_JSON('{"key": "value"}');
   ```

9. **Dynamic table TARGET_LAG** - Child lag must be >= parent lag:
   ```sql
   -- Parent dynamic table
   CREATE DYNAMIC TABLE dt_parent TARGET_LAG = '2 minutes' ...;

   -- WRONG - Child lag (1 min) < parent lag (2 min)
   CREATE DYNAMIC TABLE dt_child TARGET_LAG = '1 minute' AS
   SELECT * FROM dt_parent;

   -- CORRECT - Child lag >= parent lag
   CREATE DYNAMIC TABLE dt_child TARGET_LAG = '2 minutes' AS
   SELECT * FROM dt_parent;
   ```

10. **CONCAT() and expressions NOT allowed in CREATE ROLE/COMMENT clauses**:
    ```sql
    -- WRONG - Cannot use expressions in COMMENT
    CREATE ROLE my_role
        COMMENT = CONCAT('Role for ', $tenant_id);

    -- CORRECT - Use static string
    CREATE ROLE my_role
        COMMENT = 'Role for tenant access';
    ```

11. **Table FK dependencies** - Create referenced tables before referencing tables:
    ```sql
    -- WRONG ORDER - sites doesn't exist yet when devices is created
    CREATE TABLE devices (site_id REFERENCES sites(site_id));
    CREATE TABLE sites (site_id VARCHAR PRIMARY KEY);

    -- CORRECT ORDER
    CREATE TABLE sites (site_id VARCHAR PRIMARY KEY);
    CREATE TABLE devices (site_id REFERENCES sites(site_id));
    ```

### Warehouse References
- Only use warehouses that exist in `02_shared_resources.sql`
- Currently only `SMDH_WH` is defined
- Do NOT reference `SMDH_ETL_WH` or `SMDH_MONITORING_WH` unless created

### Error Handling
- SnowSQL returns exit code 0 even on SQL compilation errors
- Validation scripts must parse output for error patterns like `SQL compilation error`
- Use explicit verification queries after CREATE statements

## AWS/Terraform Rules

### IoT Thing Types
- Thing types require 5-minute deprecation period before deletion
- Cannot delete thing types that have associated things
- Deprecate first with `aws iot deprecate-thing-type`, wait, then delete

### Tagging
- All resources must have standard tags: Project, Environment, ManagedBy, Tenant
- Use `local.common_tags` in Terraform modules

## Directory Structure
```
infrastructure/
├── snowflake/           # Snowflake SQL scripts
│   ├── 00-03*.sql       # Shared infrastructure
│   └── tenant/          # Per-tenant scripts (10-17*.sql)
├── terraform/           # AWS infrastructure
│   ├── modules/         # Reusable modules
│   └── environments/    # Environment configs
└── scripts/             # Utility scripts
```

## Testing Commands
```bash
# Validate Snowflake setup
cd infrastructure/snowflake
export SNOWSQL_PWD='SnowflakeRocks*01'
./validate_setup.sh test_tenant "Test Tenant" eu-west-2 5

# Onboard new tenant
./scripts/onboard_tenant.sh tenant_id "Tenant Name" region

# Terraform
cd infrastructure/terraform
terraform plan -var-file=environments/dev/terraform.tfvars
terraform apply -var-file=environments/dev/terraform.tfvars
```

## IoT Pipeline E2E Testing

### Test Scripts

Located in `infrastructure/scripts/`:

| Script | Purpose |
|--------|---------|
| `test_iot_pipeline.sh` | Send UG65-formatted test messages through IoT pipeline |
| `check_iot_pipeline.sh` | Health check for all pipeline components |

### Run E2E Test

```bash
# Basic test (5 messages to test_tenant/SITE_001)
./infrastructure/scripts/test_iot_pipeline.sh

# Custom test
./infrastructure/scripts/test_iot_pipeline.sh tenant_id site_id count
./infrastructure/scripts/test_iot_pipeline.sh test_tenant SITE_001 10

# Using Python MQTT simulator directly (requires certificates)
python tests/device-simulators/ug65_e2e_test.py \
    --tenant-id test_tenant \
    --site-id SITE_001 \
    --count 5
```

### Check Pipeline Health

```bash
./infrastructure/scripts/check_iot_pipeline.sh test_tenant
```

Checks:
- Kinesis stream status
- IoT rule configuration
- Active certificates
- Recent ingestion metrics
- Live pipeline test

### UG65 Message Format

Messages must follow the Milesight UG65 LoRaWAN gateway format (see `docs/sensor-docs/Zoho WorkDrive/ug65_mqtt_integration.md`):

```json
{
  "applicationId": "smdh",
  "deviceEUI": "24E124707E043923",
  "deviceName": "AM308-TempHumidity-Floor1",
  "time": "2025-12-04T16:12:00.000Z",
  "fPort": 85,
  "fCntUp": 1001,
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
    "rssi": -102,
    "snr": -3.2
  }
}
```

### MQTT Topic Pattern

IoT rule expects: `smdh/{tenant_id}/{site_id}/sensor-data`

The IoT rule enriches messages with:
- `tenant_id` - extracted from topic(2)
- `site_id` - extracted from topic(3)
- `iot_timestamp` - server timestamp
- `device_id` - client ID

### IoT Certificate Management

Certificates are stored in `infrastructure/deployment/certificates/`:
- `{tenant_id}_{site_id}_certificate.pem` - Device certificate
- `{tenant_id}_{site_id}_private_key.pem` - Private key
- `ca/AmazonRootCA1.pem` - AWS root CA

To create a new certificate:
```bash
aws iot create-keys-and-certificate \
    --set-as-active \
    --certificate-pem-outfile cert.pem \
    --private-key-outfile key.pem \
    --region eu-west-2

# Attach policy
aws iot attach-policy \
    --policy-name "smdh-policy-{tenant_id}" \
    --target "arn:aws:iot:...:cert/{cert_id}" \
    --region eu-west-2
```

### Verify Data in Snowflake

After running tests, verify data arrived:
```sql
USE DATABASE SMDH_TENANT_TEST_TENANT;
SELECT * FROM raw.sensor_readings
WHERE ingestion_timestamp >= DATEADD(MINUTE, -10, CURRENT_TIMESTAMP())
ORDER BY ingestion_timestamp DESC;
```
