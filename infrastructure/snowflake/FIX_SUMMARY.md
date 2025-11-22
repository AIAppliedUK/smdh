# Snowflake Variable Passing Fix - Summary

## Problem Diagnosed

The tenant database creation was failing because the `validate_setup.sh` script was only passing one variable (`tenant_id`) to the SQL scripts, but the SQL files required **four** variables:

1. `$tenant_id` - Tenant identifier
2. `$tenant_name` - Tenant display name
3. `$aws_region` - AWS region for IoT Core
4. `$num_sites` - Number of manufacturing sites

**Error in logs:**
```
002211 (02000): SQL compilation error: error line 1 at position 24
Session variable '$TENANT_ID' does not exist
```

## Root Cause

In `validate_setup.sh` line 123-124 (old version):
```bash
run_sql_script "$SCRIPT_DIR/tenant/10_create_tenant_database.sql" \
    "-D tenant_id='${TENANT_ID}'" || exit 1
```

But `10_create_tenant_database.sql` lines 33-36 expected:
```sql
SELECT 'Tenant ID: ' || $tenant_id AS parameter;
SELECT 'Tenant Name: ' || $tenant_name AS parameter;
SELECT 'AWS Region: ' || $aws_region AS parameter;
SELECT 'Number of Sites: ' || $num_sites AS parameter;
```

## Changes Made

### 1. Updated Script Parameters (lines 21-24)
```bash
TENANT_ID="${1:-test_tenant}"
TENANT_NAME="${2:-Test Tenant}"
AWS_REGION="${3:-eu-west-2}"
NUM_SITES="${4:-5}"
```

### 2. Enhanced Banner Output (lines 75-80)
Now displays all tenant configuration parameters for visibility.

### 3. Fixed Variable Passing (lines 130-134)
```bash
# Define tenant variables for all scripts
TENANT_VARS="-D tenant_id='${TENANT_ID}' -D tenant_name='${TENANT_NAME}' -D aws_region='${AWS_REGION}' -D num_sites=${NUM_SITES}"

# Create tenant database
run_sql_script "$SCRIPT_DIR/tenant/10_create_tenant_database.sql" \
    "$TENANT_VARS" || exit 1
```

### 4. Updated Usage Documentation (lines 6-7)
```bash
# Usage: ./validate_setup.sh [tenant_id] [tenant_name] [aws_region] [num_sites]
# Example: ./validate_setup.sh test_tenant "Test Tenant" eu-west-2 5
```

## How to Run

### Option 1: Use defaults (recommended for testing)
```bash
cd /Users/david/projects/smdh/infrastructure/snowflake
./validate_setup.sh
```

This will create:
- Tenant ID: `test_tenant`
- Tenant Name: `Test Tenant`
- AWS Region: `eu-west-2`
- Number of Sites: `5`
- Database: `SMDH_TENANT_TEST_TENANT`

### Option 2: Provide custom parameters
```bash
./validate_setup.sh company_a "Company A Manufacturing Ltd" eu-west-2 10
```

This will create:
- Tenant ID: `company_a`
- Tenant Name: `Company A Manufacturing Ltd`
- AWS Region: `eu-west-2`
- Number of Sites: `10`
- Database: `SMDH_TENANT_COMPANY_A`

## Expected Outcome

After running successfully, you should see:
1. ✅ `SMDH_INFRASTRUCTURE` database (already exists)
2. ✅ `SMDH_OPENFLOW_TEST` database (already exists)
3. ✅ `SMDH_TENANT_TEST_TENANT` database (newly created)

Each tenant database will have 4 schemas:
- `raw` - Raw ingested sensor data
- `normalized` - Cleaned and validated data
- `aggregated` - Pre-aggregated metrics and KPIs
- `analytics` - Analytics views and ML results

## Verification

Check the Snowflake UI to verify:
1. Database appears in the database list
2. All four schemas are created
3. Tenant is registered in `SMDH_INFRASTRUCTURE.tenant_configs.tenants`

Or run this SQL in Snowflake:
```sql
-- Check databases
SHOW DATABASES LIKE 'smdh%';

-- Check tenant registry
SELECT * FROM smdh_infrastructure.tenant_configs.tenants;

-- Check schemas
USE DATABASE smdh_tenant_test_tenant;
SHOW SCHEMAS;
```

## Files Modified

- ✅ `infrastructure/snowflake/validate_setup.sh` - Added all 4 variables with defaults

## Next Steps

1. Run `./validate_setup.sh` to create the tenant database
2. Verify in Snowflake UI that `SMDH_TENANT_TEST_TENANT` appears
3. If successful, commit the fix to git
4. Document the solution in project documentation

---

**Fixed By:** Claude Code Session
**Date:** 2025-11-22
**Version:** 1.1
