-- ============================================================================
-- SMDH Tenant Validation Script
-- ============================================================================
-- Purpose: Validate tenant setup is complete and correct
-- Usage: snowsql -f scripts/validate_tenant.sql -D tenant_id='company_a'
-- Author: SMDH Platform Team
-- Version: 1.0
-- ============================================================================

USE ROLE ACCOUNTADMIN;

-- Display banner
SELECT '╔════════════════════════════════════════════════════════════════╗' AS banner
UNION ALL SELECT '║  SMDH Tenant Validation                                    ║'
UNION ALL SELECT '╚════════════════════════════════════════════════════════════╝';

SET database_name = 'smdh_tenant_' || '&tenant_id';

-- ============================================================================
-- 1. Database Validation
-- ============================================================================

SELECT '1. DATABASE VALIDATION' AS section;

SELECT
    CASE
        WHEN EXISTS (SELECT 1 FROM SNOWFLAKE.INFORMATION_SCHEMA.DATABASES WHERE DATABASE_NAME = &database_name)
        THEN '✓ PASS: Tenant database exists'
        ELSE '✗ FAIL: Tenant database not found'
    END AS check_result;

-- Check database is registered in infrastructure
SELECT
    CASE
        WHEN EXISTS (
            SELECT 1 FROM smdh_infrastructure.tenant_configs.tenants
            WHERE tenant_id = '&tenant_id'
        )
        THEN '✓ PASS: Tenant registered in infrastructure database'
        ELSE '✗ FAIL: Tenant not found in infrastructure registry'
    END AS check_result;

-- ============================================================================
-- 2. Schema Validation
-- ============================================================================

SELECT '2. SCHEMA VALIDATION' AS section;

USE DATABASE IDENTIFIER(&database_name);

WITH expected_schemas AS (
    SELECT 'RAW' AS schema_name
    UNION ALL SELECT 'NORMALIZED'
    UNION ALL SELECT 'AGGREGATED'
    UNION ALL SELECT 'ANALYTICS'
)
SELECT
    es.schema_name,
    CASE
        WHEN s.SCHEMA_NAME IS NOT NULL THEN '✓ PASS'
        ELSE '✗ FAIL'
    END AS status
FROM expected_schemas es
LEFT JOIN SNOWFLAKE.INFORMATION_SCHEMA.SCHEMATA s
    ON s.SCHEMA_NAME = es.schema_name
    AND s.CATALOG_NAME = &database_name
ORDER BY es.schema_name;

-- ============================================================================
-- 3. Table Validation
-- ============================================================================

SELECT '3. TABLE VALIDATION' AS section;

WITH expected_tables AS (
    SELECT 'RAW' AS schema_name, 'SENSOR_READINGS' AS table_name
    UNION ALL SELECT 'RAW', 'GATEWAY_CONNECTIONS'
    UNION ALL SELECT 'RAW', 'DEVICE_STATUS'
    UNION ALL SELECT 'RAW', 'UPLOADED_FILES'
    UNION ALL SELECT 'NORMALIZED', 'SENSOR_METRICS'
    UNION ALL SELECT 'NORMALIZED', 'DEVICE_EVENTS'
    UNION ALL SELECT 'NORMALIZED', 'SITE_METRICS'
    UNION ALL SELECT 'AGGREGATED', 'SENSOR_METRICS_HOURLY'
    UNION ALL SELECT 'AGGREGATED', 'SENSOR_METRICS_DAILY'
    UNION ALL SELECT 'AGGREGATED', 'SITE_PERFORMANCE_DAILY'
)
SELECT
    et.schema_name || '.' || et.table_name AS full_table_name,
    CASE
        WHEN t.TABLE_NAME IS NOT NULL THEN '✓ PASS'
        ELSE '✗ FAIL'
    END AS status,
    COALESCE(t.ROW_COUNT, 0) AS row_count
FROM expected_tables et
LEFT JOIN SNOWFLAKE.INFORMATION_SCHEMA.TABLES t
    ON t.TABLE_SCHEMA = et.schema_name
    AND t.TABLE_NAME = et.table_name
    AND t.TABLE_CATALOG = &database_name
ORDER BY et.schema_name, et.table_name;

-- ============================================================================
-- 4. Stream Validation
-- ============================================================================

SELECT '4. STREAM VALIDATION' AS section;

WITH expected_streams AS (
    SELECT 'RAW' AS schema_name, 'SENSOR_READINGS_STREAM' AS stream_name
    UNION ALL SELECT 'RAW', 'DEVICE_STATUS_STREAM'
    UNION ALL SELECT 'RAW', 'GATEWAY_CONNECTIONS_STREAM'
    UNION ALL SELECT 'RAW', 'UPLOADED_FILES_STREAM'
    UNION ALL SELECT 'NORMALIZED', 'SENSOR_METRICS_STREAM'
    UNION ALL SELECT 'NORMALIZED', 'DEVICE_EVENTS_STREAM'
)
SELECT
    es.schema_name || '.' || es.stream_name AS full_stream_name,
    CASE
        WHEN s.NAME IS NOT NULL THEN '✓ PASS'
        ELSE '✗ FAIL'
    END AS status,
    COALESCE(s.STALE, 'N/A') AS is_stale
FROM expected_streams es
LEFT JOIN SNOWFLAKE.INFORMATION_SCHEMA.STREAMS s
    ON s.TABLE_SCHEMA = es.schema_name
    AND s.NAME = es.stream_name
    AND s.TABLE_CATALOG = &database_name
ORDER BY es.schema_name, es.stream_name;

-- ============================================================================
-- 5. Task Validation
-- ============================================================================

SELECT '5. TASK VALIDATION' AS section;

WITH expected_tasks AS (
    SELECT 'RAW' AS schema_name, 'TASK_NORMALIZE_SENSOR_READINGS' AS task_name
    UNION ALL SELECT 'RAW', 'TASK_PROCESS_DEVICE_STATUS'
    UNION ALL SELECT 'RAW', 'TASK_UPDATE_DEVICE_REGISTRY'
    UNION ALL SELECT 'NORMALIZED', 'TASK_AGGREGATE_HOURLY'
    UNION ALL SELECT 'NORMALIZED', 'TASK_AGGREGATE_DAILY'
)
SELECT
    et.schema_name || '.' || et.task_name AS full_task_name,
    CASE
        WHEN t.NAME IS NOT NULL THEN '✓ PASS'
        ELSE '✗ FAIL'
    END AS status,
    COALESCE(t.STATE, 'NOT FOUND') AS task_state,
    COALESCE(t.SCHEDULE, 'N/A') AS schedule
FROM expected_tasks et
LEFT JOIN SNOWFLAKE.INFORMATION_SCHEMA.TASKS t
    ON t.SCHEMA_NAME = et.schema_name
    AND t.NAME = et.task_name
    AND t.DATABASE_NAME = &database_name
ORDER BY et.schema_name, et.task_name;

-- Check if tasks are running
SELECT
    CASE
        WHEN COUNT(CASE WHEN STATE = 'started' THEN 1 END) = COUNT(*)
        THEN '✓ PASS: All tasks are running'
        ELSE '⚠ WARNING: ' || (COUNT(*) - COUNT(CASE WHEN STATE = 'started' THEN 1 END)) || ' tasks are suspended'
    END AS task_status_check
FROM SNOWFLAKE.INFORMATION_SCHEMA.TASKS
WHERE DATABASE_NAME = &database_name;

-- ============================================================================
-- 6. Dynamic Table Validation
-- ============================================================================

SELECT '6. DYNAMIC TABLE VALIDATION' AS section;

WITH expected_dynamic_tables AS (
    SELECT 'AGGREGATED' AS schema_name, 'DT_SENSOR_METRICS_REALTIME' AS dt_name
    UNION ALL SELECT 'AGGREGATED', 'DT_DEVICE_HEALTH_CURRENT'
    UNION ALL SELECT 'AGGREGATED', 'DT_SITE_PERFORMANCE_CURRENT'
    UNION ALL SELECT 'AGGREGATED', 'DT_HOURLY_TRENDS_24H'
    UNION ALL SELECT 'AGGREGATED', 'DT_ALERT_CONDITIONS'
    UNION ALL SELECT 'AGGREGATED', 'DT_DATA_QUALITY_SUMMARY'
)
SELECT
    ed.schema_name || '.' || ed.dt_name AS full_dt_name,
    CASE
        WHEN dt.NAME IS NOT NULL THEN '✓ PASS'
        ELSE '✗ FAIL'
    END AS status,
    COALESCE(dt.SCHEDULING_STATE, 'NOT FOUND') AS scheduling_state,
    COALESCE(dt.TARGET_LAG, 'N/A') AS target_lag
FROM expected_dynamic_tables ed
LEFT JOIN SNOWFLAKE.INFORMATION_SCHEMA.DYNAMIC_TABLES dt
    ON dt.SCHEMA_NAME = ed.schema_name
    AND dt.NAME = ed.dt_name
ORDER BY ed.schema_name, ed.dt_name;

-- ============================================================================
-- 7. Role Validation
-- ============================================================================

SELECT '7. ROLE VALIDATION' AS section;

WITH expected_roles AS (
    SELECT 'smdh_tenant_' || '&tenant_id' || '_admin' AS role_name
    UNION ALL SELECT 'smdh_tenant_' || '&tenant_id' || '_user'
    UNION ALL SELECT 'smdh_tenant_' || '&tenant_id' || '_readonly'
    UNION ALL SELECT 'smdh_tenant_' || '&tenant_id' || '_data_engineer'
    UNION ALL SELECT 'smdh_tenant_' || '&tenant_id' || '_data_analyst'
    UNION ALL SELECT 'smdh_tenant_' || '&tenant_id' || '_api_service'
    UNION ALL SELECT 'smdh_tenant_' || '&tenant_id' || '_auditor'
)
SELECT
    er.role_name,
    CASE
        WHEN r.NAME IS NOT NULL THEN '✓ PASS'
        ELSE '✗ FAIL'
    END AS status
FROM expected_roles er
LEFT JOIN SNOWFLAKE.ACCOUNT_USAGE.ROLES r
    ON r.NAME = er.role_name
    AND r.DELETED_ON IS NULL
ORDER BY er.role_name;

-- ============================================================================
-- 8. View Validation
-- ============================================================================

SELECT '8. MONITORING VIEW VALIDATION' AS section;

WITH expected_views AS (
    SELECT 'ANALYTICS' AS schema_name, 'V_CURRENT_SENSOR_STATUS' AS view_name
    UNION ALL SELECT 'ANALYTICS', 'V_TENANT_OBJECTS'
    UNION ALL SELECT 'ANALYTICS', 'V_SCHEMA_STORAGE'
    UNION ALL SELECT 'ANALYTICS', 'V_STREAM_STATUS'
    UNION ALL SELECT 'ANALYTICS', 'V_STREAM_LAG'
    UNION ALL SELECT 'ANALYTICS', 'V_TASK_STATUS'
    UNION ALL SELECT 'ANALYTICS', 'V_INGESTION_MONITORING'
    UNION ALL SELECT 'ANALYTICS', 'V_STORAGE_MONITORING'
    UNION ALL SELECT 'ANALYTICS', 'V_QUERY_PERFORMANCE'
    UNION ALL SELECT 'ANALYTICS', 'V_PIPELINE_HEALTH'
    UNION ALL SELECT 'ANALYTICS', 'V_DATA_QUALITY_MONITORING'
    UNION ALL SELECT 'ANALYTICS', 'V_COST_MONITORING'
    UNION ALL SELECT 'ANALYTICS', 'V_SYSTEM_SUMMARY'
)
SELECT
    ev.schema_name || '.' || ev.view_name AS full_view_name,
    CASE
        WHEN v.TABLE_NAME IS NOT NULL THEN '✓ PASS'
        ELSE '✗ FAIL'
    END AS status
FROM expected_views ev
LEFT JOIN SNOWFLAKE.INFORMATION_SCHEMA.VIEWS v
    ON v.TABLE_SCHEMA = ev.schema_name
    AND v.TABLE_NAME = ev.view_name
    AND v.TABLE_CATALOG = &database_name
ORDER BY ev.schema_name, ev.view_name;

-- ============================================================================
-- 9. Procedure Validation
-- ============================================================================

SELECT '9. PROCEDURE VALIDATION' AS section;

SELECT
    PROCEDURE_SCHEMA || '.' || PROCEDURE_NAME AS procedure_name,
    '✓ EXISTS' AS status,
    ARGUMENT_SIGNATURE
FROM SNOWFLAKE.INFORMATION_SCHEMA.PROCEDURES
WHERE PROCEDURE_CATALOG = &database_name
    AND PROCEDURE_SCHEMA IN ('RAW', 'NORMALIZED', 'AGGREGATED', 'ANALYTICS')
ORDER BY PROCEDURE_SCHEMA, PROCEDURE_NAME;

-- ============================================================================
-- 10. Data Pipeline Health Check
-- ============================================================================

SELECT '10. DATA PIPELINE HEALTH CHECK' AS section;

USE SCHEMA analytics;

-- Run health check procedure if it exists
BEGIN
    CALL sp_health_check();
EXCEPTION
    WHEN OTHER THEN
        SELECT '⚠ WARNING: Health check procedure not available or failed' AS health_check_status;
END;

-- ============================================================================
-- 11. Warehouse Access Validation
-- ============================================================================

SELECT '11. WAREHOUSE ACCESS VALIDATION' AS section;

SELECT
    GRANTEE_NAME AS role_name,
    NAME AS warehouse_name,
    PRIVILEGE,
    '✓ GRANTED' AS status
FROM SNOWFLAKE.ACCOUNT_USAGE.GRANTS_TO_ROLES
WHERE GRANTEE_NAME LIKE 'smdh_tenant_' || '&tenant_id' || '%'
    AND GRANTED_ON = 'WAREHOUSE'
    AND NAME LIKE 'smdh_%'
    AND DELETED_ON IS NULL
ORDER BY GRANTEE_NAME, NAME;

-- ============================================================================
-- 12. Storage Usage Check
-- ============================================================================

SELECT '12. STORAGE USAGE CHECK' AS section;

SELECT
    ROUND(SUM(ACTIVE_BYTES) / (1024*1024*1024), 2) AS active_storage_gb,
    ROUND(SUM(TIME_TRAVEL_BYTES) / (1024*1024*1024), 2) AS time_travel_gb,
    ROUND(SUM(FAILSAFE_BYTES) / (1024*1024*1024), 2) AS failsafe_gb,
    ROUND(SUM(ACTIVE_BYTES + TIME_TRAVEL_BYTES + FAILSAFE_BYTES) / (1024*1024*1024), 2) AS total_storage_gb
FROM SNOWFLAKE.ACCOUNT_USAGE.DATABASE_STORAGE_USAGE_HISTORY
WHERE DATABASE_NAME = &database_name
    AND USAGE_DATE = CURRENT_DATE();

-- ============================================================================
-- 13. Summary
-- ============================================================================

SELECT '╔════════════════════════════════════════════════════════════════╗' AS summary
UNION ALL SELECT '║  Tenant Validation Complete                                ║'
UNION ALL SELECT '╚════════════════════════════════════════════════════════════╝'
UNION ALL SELECT ''
UNION ALL SELECT 'Tenant: ' || '&tenant_id'
UNION ALL SELECT 'Database: smdh_tenant_' || '&tenant_id'
UNION ALL SELECT ''
UNION ALL SELECT 'Validation Summary:'
UNION ALL SELECT '  • Review the check results above'
UNION ALL SELECT '  • All items should show ✓ PASS or ✓ EXISTS'
UNION ALL SELECT '  • Address any ✗ FAIL or ⚠ WARNING items'
UNION ALL SELECT ''
UNION ALL SELECT 'If all checks pass, the tenant is ready for data ingestion.'
UNION ALL SELECT ''
UNION ALL SELECT 'Next Steps:'
UNION ALL SELECT '  1. Configure Kinesis connector for this tenant'
UNION ALL SELECT '  2. Deploy IoT device certificates'
UNION ALL SELECT '  3. Start MQTT message ingestion'
UNION ALL SELECT '  4. Monitor data flow: SELECT * FROM analytics.v_ingestion_monitoring;'
UNION ALL SELECT '============================================================';
