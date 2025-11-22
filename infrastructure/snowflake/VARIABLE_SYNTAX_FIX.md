# SnowSQL Variable Syntax Fix - Complete

## Problem
SQL files were using `$variable` syntax (incorrect) instead of `&variable` syntax (correct per Snowflake docs).

## Root Cause
According to [Snowflake SnowSQL Documentation](https://docs.snowflake.com/en/user-guide/snowsql-use):
- SnowSQL uses **`&variable`** for variable substitution in SQL
- The `-D variable=value` flag defines variables
- Must enable `-o variable_substitution=true`
- The `$variable` syntax is **NOT** supported

## Changes Made

### 1. Updated All SQL Files (9 files, 217 lines)
Replaced all variable references:
- `$tenant_id` → `&tenant_id`
- `$tenant_name` → `&tenant_name`
- `$aws_region` → `&aws_region`
- `$aws_iam_role_arn` → `&aws_iam_role_arn`
- `$aws_external_id` → `&aws_external_id`
- `$kinesis_stream_arn` → `&kinesis_stream_arn`
- `$num_sites` → `&num_sites`
- `$database_name` → `&database_name`
- `$admin_role_name` → `&admin_role_name`
- `$user_role_name` → `&user_role_name`
- `$readonly_role_name` → `&readonly_role_name`
- `$tenant_db` → `&tenant_db`

### 2. Updated validate_setup.sh
- Added `-o variable_substitution=true` to SNOWSQL_OPTS
- Updated verification SQL to use `&variable` syntax
- Added debug logging to troubleshoot command execution

## Files Modified

### SQL Files Updated:
1. `tenant/10_create_tenant_database.sql` - 73 lines
2. `tenant/11_create_schemas.sql` - 6 lines
3. `tenant/12_create_tables.sql` - 14 lines
4. `tenant/13_create_streams.sql` - 13 lines
5. `tenant/14_create_tasks.sql` - 12 lines
6. `tenant/15_create_dynamic_tables.sql` - 9 lines
7. `tenant/16_create_roles.sql` - 49 lines
8. `tenant/17_create_monitoring.sql` - 13 lines
9. `03_openflow_connector.sql` - 6 lines
10. `validate_tenant.sql` - 22 lines

### Shell Script:
- `validate_setup.sh` - Added variable substitution option

## How to Run

Now you can run the validation script and variables will be properly passed:

```bash
cd /Users/david/projects/smdh/infrastructure/snowflake
./validate_setup.sh
```

This will:
1. Use default values: `test_tenant`, `TestTenant`, `eu-west-2`, `5`
2. Enable variable substitution with `-o variable_substitution=true`
3. Pass variables with `-D variable=value`
4. Create `SMDH_TENANT_TEST_TENANT` database successfully

Or with custom values:

```bash
./validate_setup.sh company_a "CompanyA" eu-west-2 10
```

## Verification

After running, you should see in Snowflake UI:
- `SMDH_INFRASTRUCTURE` ✅
- `SMDH_OPENFLOW_TEST` ✅
- `SMDH_TENANT_TEST_TENANT` ✅ (newly created)

Each tenant database contains:
- `raw` schema
- `normalized` schema
- `aggregated` schema
- `analytics` schema

---

**Fixed By:** Claude Code Session
**Date:** 2025-11-22
**Reference:** https://docs.snowflake.com/en/user-guide/snowsql-use#using-variables
