# SMDH Infrastructure Test Results

**Test Date:** 2025-12-01
**Tester:** Claude Code (Automated Testing)
**Environment:** Snowflake Account qqoylnv-zy42691 / AWS eu-west-2
**Test Tenant:** test_tenant_01 "Test Tenant Ltd"

---

## Executive Summary

| Phase | Status | Notes |
|-------|--------|-------|
| Snowflake Core Infrastructure | **PASS** | Drop and deploy successful |
| Tenant Onboarding (Steps 1-7) | **PASS** | All core objects created |
| Tenant Onboarding (Step 8) | **FAIL** | Monitoring script needs fixes |
| Terraform Infrastructure | **PENDING** | Not yet tested |

---

## Issues Found and Fixed During Testing

### Critical Issues Fixed

| Script | Issue | Fix Applied |
|--------|-------|-------------|
| `01_infrastructure_setup.sql` | `devices` table FK to `sites` failed - wrong creation order | Swapped sections 5 & 6: sites now created before devices |
| `12_create_tables.sql` | `DATA_RETENTION_TIME_IN_DAYS` exceeded 90-day limit (Standard edition) | Changed 365/730 days to 90 days |
| `12_create_tables.sql` | View referenced non-existent `smdh_infrastructure.tenant_configs.devices` | Rewrote view to use local tenant tables |
| `12_create_tables.sql` | Reference to non-existent `v_tenant_objects` view | Removed reference |
| `13_create_streams.sql` | `SNOWFLAKE.ACCOUNT_USAGE.STREAMS` not accessible | Created placeholder view |
| `13_create_streams.sql` | `PARSE_JSON()` in VALUES clause not allowed | Changed to INSERT...SELECT |
| `13_create_streams.sql` | Reference to non-existent `schema_documentation` table | Deferred documentation to monitoring script |
| `15_create_dynamic_tables.sql` | Non-existent warehouses (SMDH_STREAMING_WH, etc.) | Changed all to SMDH_WH |
| `15_create_dynamic_tables.sql` | Dynamic table lag dependency (1 min < 2 min) | Increased DT_ALERT_CONDITIONS lag to 2 min |
| `15_create_dynamic_tables.sql` | `INFORMATION_SCHEMA.DYNAMIC_TABLES` not accessible | Created placeholder view |
| `16_create_roles.sql` | `CONCAT()` in CREATE ROLE COMMENT clause not allowed | Changed to static comments |
| `16_create_roles.sql` | Non-existent warehouses in GRANT statements | Changed all to SMDH_WH |
| `16_create_roles.sql` | String concatenation in SHOW statements | Removed problematic SHOW statements |
| `16_create_roles.sql` | `GRANT MONITOR ON ALL WAREHOUSES IN ACCOUNT` failed | Removed statement |

### Remaining Issues (17_create_monitoring.sql)

| Issue | Description | Recommended Fix |
|-------|-------------|-----------------|
| `INFORMATION_SCHEMA.TASKS` | Does not exist at database level | Use `SHOW TASKS` or `SNOWFLAKE.ACCOUNT_USAGE.TASK_HISTORY` |
| Invalid identifier `ROW_COUNT` | View references non-existent column | Check view definition |
| Invalid identifier `BYTES_SCANNED` | View references non-existent column | Check view definition |
| View creation order | Views reference other views not yet created | Reorder view creation |
| SHOW syntax in procedure | Cannot use variable in SHOW LIKE | Use alternative approach |

---

## Test Execution Log

### Phase 1: Core Infrastructure Drop
```
Timestamp: 2025-12-01 09:10:00 UTC
Command: ./snowflake.sh drop
Result: SUCCESS
Objects Dropped: smdh_infrastructure database, all roles, all tenant databases
```

### Phase 2: Core Infrastructure Deploy
```
Timestamp: 2025-12-01 09:11:00 UTC
Command: ./snowflake.sh deploy
Result: SUCCESS (with expected Openflow warnings)
Objects Created:
  - Database: smdh_infrastructure
  - Schemas: tenant_configs, monitoring, audit
  - Tables: tenants, tenant_users, sites, devices, ingestion_metrics,
            task_execution_log, alerts, user_access_log, data_modification_log
  - Roles: smdh_infrastructure_admin, smdh_monitoring
  - Views: v_active_tenants, v_device_connectivity, v_site_device_summary,
           v_thing_group_hierarchy, v_disconnected_devices, v_certificate_expiry_alerts
  - Warehouse: SMDH_WH
```

### Phase 3: Tenant Onboarding
```
Timestamp: 2025-12-01 09:15:00 - 09:45:00 UTC
Command: ./onboard_tenant.sh --tenant-id test_tenant_01 --tenant-name "Test Tenant Ltd" --num-sites 2
```

| Step | Script | Status | Objects Created |
|------|--------|--------|-----------------|
| 1/8 | 10_create_tenant_database.sql | **PASS** | smdh_tenant_test_tenant_01 database, tenant registration |
| 2/8 | 11_create_schemas.sql | **PASS** | raw, normalized, aggregated, analytics schemas |
| 3/8 | 12_create_tables.sql | **PASS** | 10+ data tables across all schemas |
| 4/8 | 13_create_streams.sql | **PASS** | 6 CDC streams |
| 5/8 | 14_create_tasks.sql | **PASS** | 5 ETL tasks (started) |
| 6/8 | 15_create_dynamic_tables.sql | **PASS** | 6 dynamic tables |
| 7/8 | 16_create_roles.sql | **PASS** | 7 tenant roles, v_role_hierarchy view, sp_create_tenant_user procedure |
| 8/8 | 17_create_monitoring.sql | **FAIL** | Requires fixes (see issues above) |

---

## Snowflake SQL Scripting Lessons Learned

### CLAUDE.md Guidelines Validated

1. **DEFAULT clause limitation** - Confirmed: Session variables cannot be used in DEFAULT clauses
2. **Cross-schema task predecessors** - Not tested directly but documented
3. **INFORMATION_SCHEMA limitations** - Confirmed: TASKS and STREAMS not available at database level
4. **Shell variable syntax** - Confirmed: IDENTIFIER() must be used with session variables

### New Constraints Discovered

1. **DATA_RETENTION_TIME_IN_DAYS** - Standard edition limits to 90 days maximum
2. **CONCAT() in DDL** - Cannot use CONCAT() with session variables in COMMENT clauses
3. **SHOW statement limitations** - Cannot use string concatenation or IDENTIFIER() in SHOW LIKE
4. **Dynamic table lag dependencies** - Child DT lag must be >= parent DT lag
5. **PARSE_JSON() in VALUES** - Cannot use PARSE_JSON() in VALUES clause, must use INSERT...SELECT
6. **View creation dependencies** - SNOWFLAKE.ACCOUNT_USAGE has 2-hour latency for new objects
7. **Warehouse references** - All warehouse references must match actually created warehouses

---

## Verification Queries

### Core Infrastructure Verification
```sql
-- Verify infrastructure database
SHOW DATABASES LIKE 'smdh_infrastructure';

-- Verify tables
USE DATABASE smdh_infrastructure;
SHOW TABLES IN SCHEMA tenant_configs;
SHOW TABLES IN SCHEMA monitoring;
SHOW TABLES IN SCHEMA audit;

-- Verify roles
SHOW ROLES LIKE 'smdh_%';

-- Verify warehouse
SHOW WAREHOUSES LIKE 'SMDH%';
```

### Tenant Verification
```sql
-- Verify tenant database
SHOW DATABASES LIKE 'smdh_tenant_%';

-- Verify tenant objects
USE DATABASE smdh_tenant_test_tenant_01;
SHOW SCHEMAS;
SHOW TABLES IN SCHEMA raw;
SHOW STREAMS;
SHOW TASKS;
SHOW DYNAMIC TABLES;

-- Verify tenant registration
SELECT * FROM smdh_infrastructure.tenant_configs.tenants;
```

---

## Files Modified During Testing

| File | Changes Made |
|------|--------------|
| `sql/core/01_infrastructure_setup.sql` | Swapped sites/devices creation order |
| `sql/tenant/12_create_tables.sql` | Fixed retention times, removed bad references |
| `sql/tenant/13_create_streams.sql` | Fixed view, INSERT statement, removed MERGE |
| `sql/tenant/15_create_dynamic_tables.sql` | Fixed warehouse names, lag dependencies, views |
| `sql/tenant/16_create_roles.sql` | Fixed warehouse names, comments, removed problematic statements |

---

## Recommendations

### Immediate Actions Required

1. **Fix 17_create_monitoring.sql** - The monitoring script needs the same pattern of fixes applied to earlier scripts:
   - Replace INFORMATION_SCHEMA references with SNOWFLAKE.ACCOUNT_USAGE or SHOW commands
   - Fix invalid column references
   - Ensure view creation order is correct

2. **Update CLAUDE.md** - Add newly discovered constraints:
   - DATA_RETENTION_TIME_IN_DAYS limit on Standard edition
   - CONCAT() limitations in DDL statements
   - Dynamic table lag dependencies
   - PARSE_JSON() limitations in VALUES clause

### Long-term Improvements

1. **Warehouse Consolidation** - Consider if multiple warehouses are truly needed, or if SMDH_WH suffices
2. **Monitoring Views** - Consider using procedures instead of views for dynamic metadata queries
3. **Validation Scripts** - Add pre-flight checks for Snowflake edition and available features
4. **Unit Tests** - Create individual SQL test files for each script

---

## Test Environment Cleanup

```bash
# To clean up test tenant:
snowsql -r ACCOUNTADMIN -q "DROP DATABASE IF EXISTS smdh_tenant_test_tenant_01;"
snowsql -r ACCOUNTADMIN -q "DELETE FROM smdh_infrastructure.tenant_configs.tenants WHERE tenant_id = 'test_tenant_01';"

# To drop all roles created for test tenant:
snowsql -r ACCOUNTADMIN -q "DROP ROLE IF EXISTS smdh_tenant_test_tenant_01_admin;"
snowsql -r ACCOUNTADMIN -q "DROP ROLE IF EXISTS smdh_tenant_test_tenant_01_user;"
# ... (similar for other roles)
```

---

*Report generated by Claude Code Infrastructure Testing Agent*
*Version: 1.0*
