 SnowSQL Variable Syntax Fix - Complete

 Problem
SQL files were using `$variable` syntax (incorrect) instead of `&variable` syntax (correct per Snowflake docs).

 Root Cause
According to [Snowflake SnowSQL Documentation](https://docs.snowflake.com/en/user-guide/snowsql-use):
- SnowSQL uses `&variable` for variable substitution in SQL
- The `-D variable=value` flag defines variables
- Must enable `-o variable_substitution=true`
- The `$variable` syntax is NOT supported

 Changes Made

 . Updated All SQL Files ( files,  lines)
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

 . Updated validate_setup.sh
- Added `-o variable_substitution=true` to SNOWSQL_OPTS
- Updated verification SQL to use `&variable` syntax
- Added debug logging to troubleshoot command execution

 Files Modified

 SQL Files Updated:
. `tenant/_create_tenant_database.sql` -  lines
. `tenant/_create_schemas.sql` -  lines
. `tenant/_create_tables.sql` -  lines
. `tenant/_create_streams.sql` -  lines
. `tenant/_create_tasks.sql` -  lines
. `tenant/_create_dynamic_tables.sql` -  lines
. `tenant/_create_roles.sql` -  lines
. `tenant/_create_monitoring.sql` -  lines
. `_openflow_connector.sql` -  lines
. `validate_tenant.sql` -  lines

 Shell Script:
- `validate_setup.sh` - Added variable substitution option

 How to Run

Now you can run the validation script and variables will be properly passed:

```bash
cd /Users/david/projects/smdh/infrastructure/snowflake
./validate_setup.sh
```

This will:
. Use default values: `test_tenant`, `TestTenant`, `eu-west-`, ``
. Enable variable substitution with `-o variable_substitution=true`
. Pass variables with `-D variable=value`
. Create `SMDH_TENANT_TEST_TENANT` database successfully

Or with custom values:

```bash
./validate_setup.sh company_a "CompanyA" eu-west- 
```

 Verification

After running, you should see in Snowflake UI:
- `SMDH_INFRASTRUCTURE` 
- `SMDH_OPENFLOW_TEST` 
- `SMDH_TENANT_TEST_TENANT`  (newly created)

Each tenant database contains:
- `raw` schema
- `normalized` schema
- `aggregated` schema
- `analytics` schema

---

Date: --
Reference: https://docs.snowflake.com/en/user-guide/snowsql-useusing-variables
