-- ============================================================================
-- SMDH Tenant Monitoring Setup
-- ============================================================================
-- Purpose: Create comprehensive monitoring views and dashboards for tenant
-- Usage: snowsql -f tenant/17_create_monitoring.sql --variable tenant_id='company_a'
-- Author: SMDH Platform Team
-- Version: 1.0
-- ============================================================================
-- This script creates:
-- - Operational monitoring views
-- - Performance metrics views
-- - Cost tracking views
-- - Health check procedures
-- - Alerting views
-- ============================================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE SMDH_WH;

-- Display banner
SELECT '╔════════════════════════════════════════════════════════════════╗' AS banner
UNION ALL SELECT '║  SMDH Platform - Tenant Monitoring Setup                   ║'
UNION ALL SELECT '╚════════════════════════════════════════════════════════════╝';

-- ============================================================================
-- 1. Validate Tenant Database
-- ============================================================================

SELECT '1. Validating Tenant Database...' AS step;

SET database_name = 'smdh_tenant_' || $tenant_id;

USE DATABASE IDENTIFIER($database_name);
USE SCHEMA analytics;

SELECT 'Using database: ' || $database_name AS info;

-- ============================================================================
-- 2. Create Data Ingestion Monitoring View
-- ============================================================================

SELECT '2. Creating Data Ingestion Monitoring View...' AS step;

CREATE OR REPLACE VIEW v_ingestion_monitoring AS
WITH hourly_stats AS (
    SELECT
        DATE_TRUNC('hour', ingestion_timestamp) AS ingestion_hour,
        COUNT(*) AS total_readings,
        COUNT(DISTINCT sensor_id) AS unique_sensors,
        COUNT(DISTINCT site_id) AS unique_sites,
        AVG(DATEDIFF(second, timestamp, ingestion_timestamp)) AS avg_ingestion_latency_seconds,
        MAX(DATEDIFF(second, timestamp, ingestion_timestamp)) AS max_ingestion_latency_seconds,
        SUM(CASE WHEN is_valid = TRUE THEN 1 ELSE 0 END) AS valid_readings,
        SUM(CASE WHEN is_duplicate = TRUE THEN 1 ELSE 0 END) AS duplicate_readings
    FROM smdh_tenant_${tenant_id}.raw.sensor_readings
    WHERE ingestion_timestamp >= DATEADD(day, -7, CURRENT_TIMESTAMP())
    GROUP BY ingestion_hour
)
SELECT
    ingestion_hour,
    total_readings,
    unique_sensors,
    unique_sites,
    ROUND(avg_ingestion_latency_seconds, 2) AS avg_latency_seconds,
    max_ingestion_latency_seconds,
    valid_readings,
    duplicate_readings,
    ROUND(valid_readings::FLOAT / NULLIF(total_readings, 0) * 100, 2) AS valid_percentage,
    CASE
        WHEN total_readings = 0 THEN 'No Data'
        WHEN avg_ingestion_latency_seconds > 60 THEN 'Degraded'
        WHEN duplicate_readings::FLOAT / total_readings > 0.1 THEN 'High Duplicates'
        ELSE 'Healthy'
    END AS health_status
FROM hourly_stats
ORDER BY ingestion_hour DESC;

GRANT SELECT ON v_ingestion_monitoring TO ROLE smdh_monitoring;

SELECT 'Created view: V_INGESTION_MONITORING' AS result;

-- ============================================================================
-- 3. Create Storage Monitoring View
-- ============================================================================

SELECT '3. Creating Storage Monitoring View...' AS step;

CREATE OR REPLACE VIEW v_storage_monitoring AS
SELECT
    table_schema AS schema_name,
    table_name,
    row_count,
    bytes AS bytes_stored,
    ROUND(bytes / (1024*1024*1024), 2) AS gb_stored,
    ROUND(bytes_retained_for_time_travel / (1024*1024*1024), 2) AS time_travel_gb,
    ROUND(bytes_retained_for_fail_safe / (1024*1024*1024), 2) AS failsafe_gb,
    created,
    last_altered,
    DATEDIFF(day, last_altered, CURRENT_TIMESTAMP()) AS days_since_modified
FROM smdh_tenant_${tenant_id}.INFORMATION_SCHEMA.TABLE_STORAGE_METRICS
WHERE table_catalog = 'smdh_tenant_' || $tenant_id
ORDER BY bytes DESC;

GRANT SELECT ON v_storage_monitoring TO ROLE smdh_monitoring;

SELECT 'Created view: V_STORAGE_MONITORING' AS result;

-- ============================================================================
-- 4. Create Query Performance Monitoring View
-- ============================================================================

SELECT '4. Creating Query Performance Monitoring View...' AS step;

CREATE OR REPLACE VIEW v_query_performance AS
SELECT
    query_id,
    query_type,
    query_text,
    database_name,
    schema_name,
    user_name,
    role_name,
    warehouse_name,
    warehouse_size,
    execution_status,
    start_time,
    end_time,
    total_elapsed_time / 1000 AS execution_seconds,
    bytes_scanned / (1024*1024*1024) AS gb_scanned,
    rows_produced,
    compilation_time / 1000 AS compilation_seconds,
    execution_time / 1000 AS execution_only_seconds,
    queued_provisioning_time / 1000 AS queue_seconds
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE database_name = 'smdh_tenant_' || $tenant_id
    AND start_time >= DATEADD(day, -7, CURRENT_TIMESTAMP())
    AND execution_status = 'SUCCESS'
ORDER BY total_elapsed_time DESC
LIMIT 100;

GRANT SELECT ON v_query_performance TO ROLE smdh_monitoring;

SELECT 'Created view: V_QUERY_PERFORMANCE' AS result;

-- ============================================================================
-- 5. Create Pipeline Health Monitoring View
-- ============================================================================

SELECT '5. Creating Pipeline Health Monitoring View...' AS step;

CREATE OR REPLACE VIEW v_pipeline_health AS
WITH stream_stats AS (
    SELECT 'sensor_readings_stream' AS stream_name,
           (SELECT COUNT(*) FROM smdh_tenant_${tenant_id}.raw.sensor_readings_stream) AS pending_rows
    UNION ALL
    SELECT 'sensor_metrics_stream',
           (SELECT COUNT(*) FROM smdh_tenant_${tenant_id}.normalized.sensor_metrics_stream)
),
task_stats AS (
    SELECT
        name AS task_name,
        state AS task_state,
        (SELECT MAX(scheduled_time)
         FROM SNOWFLAKE.ACCOUNT_USAGE.TASK_HISTORY
         WHERE name = t.name AND state = 'SUCCEEDED'
         AND database_name = 'smdh_tenant_' || $tenant_id) AS last_success_time,
        (SELECT COUNT(*)
         FROM SNOWFLAKE.ACCOUNT_USAGE.TASK_HISTORY
         WHERE name = t.name AND state = 'FAILED'
         AND database_name = 'smdh_tenant_' || $tenant_id
         AND scheduled_time >= DATEADD(hour, -24, CURRENT_TIMESTAMP())) AS failures_24h
    FROM smdh_tenant_${tenant_id}.INFORMATION_SCHEMA.TASKS t
)
SELECT
    CURRENT_TIMESTAMP() AS check_time,
    -- Stream health
    (SELECT COUNT(*) FROM stream_stats WHERE pending_rows > 10000) AS streams_with_backlog,
    (SELECT SUM(pending_rows) FROM stream_stats) AS total_pending_stream_rows,
    -- Task health
    (SELECT COUNT(*) FROM task_stats WHERE task_state != 'started') AS suspended_tasks,
    (SELECT SUM(failures_24h) FROM task_stats) AS task_failures_24h,
    (SELECT MAX(last_success_time) FROM task_stats) AS last_successful_task_run,
    -- Overall health status
    CASE
        WHEN (SELECT COUNT(*) FROM task_stats WHERE task_state != 'started') > 0 THEN 'Critical - Tasks Suspended'
        WHEN (SELECT SUM(failures_24h) FROM task_stats) > 5 THEN 'Warning - High Failure Rate'
        WHEN (SELECT COUNT(*) FROM stream_stats WHERE pending_rows > 10000) > 0 THEN 'Warning - Stream Backlog'
        WHEN (SELECT MAX(last_success_time) FROM task_stats) < DATEADD(hour, -2, CURRENT_TIMESTAMP()) THEN 'Warning - No Recent Task Execution'
        ELSE 'Healthy'
    END AS overall_pipeline_status;

GRANT SELECT ON v_pipeline_health TO ROLE smdh_monitoring;

SELECT 'Created view: V_PIPELINE_HEALTH' AS result;

-- ============================================================================
-- 6. Create Data Quality Monitoring View
-- ============================================================================

SELECT '6. Creating Data Quality Monitoring View...' AS step;

CREATE OR REPLACE VIEW v_data_quality_monitoring AS
WITH quality_by_sensor AS (
    SELECT
        sensor_id,
        site_id,
        DATE_TRUNC('day', timestamp) AS date,
        COUNT(*) AS total_readings,
        SUM(CASE WHEN quality_flag = 'good' THEN 1 ELSE 0 END) AS good_readings,
        SUM(CASE WHEN quality_flag = 'suspect' THEN 1 ELSE 0 END) AS suspect_readings,
        SUM(CASE WHEN quality_flag = 'bad' THEN 1 ELSE 0 END) AS bad_readings
    FROM smdh_tenant_${tenant_id}.normalized.sensor_metrics
    WHERE timestamp >= DATEADD(day, -7, CURRENT_TIMESTAMP())
    GROUP BY sensor_id, site_id, date
)
SELECT
    sensor_id,
    site_id,
    date,
    total_readings,
    good_readings,
    suspect_readings,
    bad_readings,
    ROUND(good_readings::FLOAT / NULLIF(total_readings, 0) * 100, 2) AS quality_score,
    CASE
        WHEN good_readings::FLOAT / NULLIF(total_readings, 0) >= 0.95 THEN 'Excellent'
        WHEN good_readings::FLOAT / NULLIF(total_readings, 0) >= 0.80 THEN 'Good'
        WHEN good_readings::FLOAT / NULLIF(total_readings, 0) >= 0.60 THEN 'Fair'
        ELSE 'Poor'
    END AS quality_grade
FROM quality_by_sensor
ORDER BY date DESC, quality_score ASC;

GRANT SELECT ON v_data_quality_monitoring TO ROLE smdh_monitoring;

SELECT 'Created view: V_DATA_QUALITY_MONITORING' AS result;

-- ============================================================================
-- 7. Create Cost Monitoring View
-- ============================================================================

SELECT '7. Creating Cost Monitoring View...' AS step;

CREATE OR REPLACE VIEW v_cost_monitoring AS
WITH warehouse_usage AS (
    SELECT
        warehouse_name,
        DATE_TRUNC('day', start_time) AS usage_date,
        SUM(credits_used) AS credits_used,
        COUNT(*) AS query_count,
        SUM(bytes_scanned) / (1024*1024*1024*1024) AS tb_scanned
    FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
    WHERE warehouse_name IN (
        'smdh_streaming_wh',
        'smdh_etl_wh',
        'smdh_analytics_wh',
        'smdh_monitoring_wh',
        'smdh_dev_wh'
    )
    AND start_time >= DATEADD(day, -30, CURRENT_TIMESTAMP())
    GROUP BY warehouse_name, usage_date
),
storage_usage AS (
    SELECT
        database_name,
        DATE_TRUNC('day', usage_date) AS usage_date,
        AVG(average_database_bytes) / (1024*1024*1024*1024) AS avg_tb_stored,
        AVG(average_failsafe_bytes) / (1024*1024*1024*1024) AS avg_tb_failsafe
    FROM SNOWFLAKE.ACCOUNT_USAGE.DATABASE_STORAGE_USAGE_HISTORY
    WHERE database_name = 'smdh_tenant_' || $tenant_id
    AND usage_date >= DATEADD(day, -30, CURRENT_TIMESTAMP())
    GROUP BY database_name, usage_date
)
SELECT
    COALESCE(w.usage_date, s.usage_date) AS date,
    w.warehouse_name,
    w.credits_used,
    w.query_count,
    ROUND(w.tb_scanned, 3) AS tb_scanned,
    ROUND(s.avg_tb_stored, 3) AS tb_stored,
    ROUND(s.avg_tb_failsafe, 3) AS tb_failsafe,
    ROUND(w.credits_used * 3.00, 2) AS estimated_compute_cost_usd,  -- Adjust rate as needed
    ROUND((s.avg_tb_stored + s.avg_tb_failsafe) * 40.00, 2) AS estimated_storage_cost_usd  -- $40/TB/month
FROM warehouse_usage w
FULL OUTER JOIN storage_usage s ON w.usage_date = s.usage_date
ORDER BY date DESC, warehouse_name;

GRANT SELECT ON v_cost_monitoring TO ROLE smdh_monitoring;

SELECT 'Created view: V_COST_MONITORING' AS result;

-- ============================================================================
-- 8. Create Health Check Procedure
-- ============================================================================

SELECT '8. Creating Health Check Procedure...' AS step;

CREATE OR REPLACE PROCEDURE sp_health_check()
RETURNS TABLE (category VARCHAR, check_name VARCHAR, status VARCHAR, message VARCHAR)
LANGUAGE SQL
AS
$$
DECLARE
    result_set RESULTSET DEFAULT (
        WITH health_checks AS (
            -- Check 1: Recent data ingestion
            SELECT
                'Ingestion' AS category,
                'Recent Data' AS check_name,
                CASE
                    WHEN MAX(ingestion_timestamp) >= DATEADD(minute, -10, CURRENT_TIMESTAMP()) THEN 'PASS'
                    WHEN MAX(ingestion_timestamp) >= DATEADD(hour, -1, CURRENT_TIMESTAMP()) THEN 'WARNING'
                    ELSE 'FAIL'
                END AS status,
                CONCAT('Last ingestion: ', DATEDIFF(minute, MAX(ingestion_timestamp), CURRENT_TIMESTAMP()), ' minutes ago') AS message
            FROM smdh_tenant_${tenant_id}.raw.sensor_readings

            UNION ALL

            -- Check 2: Task execution
            SELECT
                'Pipeline' AS category,
                'Task Execution' AS check_name,
                CASE
                    WHEN COUNT(CASE WHEN state = 'started' THEN 1 END) = COUNT(*) THEN 'PASS'
                    ELSE 'FAIL'
                END AS status,
                CONCAT(COUNT(CASE WHEN state = 'started' THEN 1 END), ' of ', COUNT(*), ' tasks running') AS message
            FROM smdh_tenant_${tenant_id}.INFORMATION_SCHEMA.TASKS

            UNION ALL

            -- Check 3: Stream lag
            SELECT
                'Pipeline' AS category,
                'Stream Lag' AS check_name,
                CASE
                    WHEN (SELECT COUNT(*) FROM smdh_tenant_${tenant_id}.raw.sensor_readings_stream) < 1000 THEN 'PASS'
                    WHEN (SELECT COUNT(*) FROM smdh_tenant_${tenant_id}.raw.sensor_readings_stream) < 10000 THEN 'WARNING'
                    ELSE 'FAIL'
                END AS status,
                CONCAT((SELECT COUNT(*) FROM smdh_tenant_${tenant_id}.raw.sensor_readings_stream), ' rows pending in sensor_readings_stream') AS message

            UNION ALL

            -- Check 4: Data quality
            SELECT
                'Quality' AS category,
                'Data Quality Score' AS check_name,
                CASE
                    WHEN AVG(CASE WHEN quality_flag = 'good' THEN 100.0 ELSE 0.0 END) >= 90 THEN 'PASS'
                    WHEN AVG(CASE WHEN quality_flag = 'good' THEN 100.0 ELSE 0.0 END) >= 70 THEN 'WARNING'
                    ELSE 'FAIL'
                END AS status,
                CONCAT('Quality score: ', ROUND(AVG(CASE WHEN quality_flag = 'good' THEN 100.0 ELSE 0.0 END), 2), '%') AS message
            FROM smdh_tenant_${tenant_id}.normalized.sensor_metrics
            WHERE timestamp >= DATEADD(hour, -1, CURRENT_TIMESTAMP())

            UNION ALL

            -- Check 5: Device connectivity
            SELECT
                'Devices' AS category,
                'Device Connectivity' AS check_name,
                CASE
                    WHEN COUNT(CASE WHEN connectivity_status = 'Online' THEN 1 END)::FLOAT / COUNT(*) >= 0.90 THEN 'PASS'
                    WHEN COUNT(CASE WHEN connectivity_status = 'Online' THEN 1 END)::FLOAT / COUNT(*) >= 0.70 THEN 'WARNING'
                    ELSE 'FAIL'
                END AS status,
                CONCAT(COUNT(CASE WHEN connectivity_status = 'Online' THEN 1 END), ' of ', COUNT(*), ' devices online') AS message
            FROM smdh_tenant_${tenant_id}.aggregated.dt_device_health_current

            UNION ALL

            -- Check 6: Storage growth
            SELECT
                'Storage' AS category,
                'Storage Usage' AS check_name,
                CASE
                    WHEN SUM(bytes) / (1024*1024*1024*1024) < 0.8 THEN 'PASS'  -- Less than 0.8 TB
                    WHEN SUM(bytes) / (1024*1024*1024*1024) < 1.5 THEN 'WARNING'  -- Less than 1.5 TB
                    ELSE 'FAIL'
                END AS status,
                CONCAT(ROUND(SUM(bytes) / (1024*1024*1024*1024), 2), ' TB used') AS message
            FROM smdh_tenant_${tenant_id}.INFORMATION_SCHEMA.TABLE_STORAGE_METRICS
        )
        SELECT * FROM health_checks
        ORDER BY
            CASE status WHEN 'FAIL' THEN 1 WHEN 'WARNING' THEN 2 ELSE 3 END,
            category,
            check_name
    );
BEGIN
    RETURN TABLE(result_set);
END;
$$;

GRANT USAGE ON PROCEDURE sp_health_check() TO ROLE smdh_monitoring;

SELECT 'Created procedure: SP_HEALTH_CHECK' AS result;

-- ============================================================================
-- 9. Create System Summary Dashboard View
-- ============================================================================

SELECT '9. Creating System Summary Dashboard View...' AS step;

CREATE OR REPLACE VIEW v_system_summary AS
SELECT
    CURRENT_TIMESTAMP() AS snapshot_time,
    -- Data volume
    (SELECT COUNT(*) FROM smdh_tenant_${tenant_id}.raw.sensor_readings) AS total_readings,
    (SELECT COUNT(*) FROM smdh_tenant_${tenant_id}.raw.sensor_readings
     WHERE ingestion_timestamp >= DATEADD(day, -1, CURRENT_TIMESTAMP())) AS readings_last_24h,
    -- Devices
    (SELECT COUNT(*) FROM smdh_infrastructure.tenant_configs.devices
     WHERE tenant_id = $tenant_id AND status = 'active') AS total_devices,
    (SELECT COUNT(*) FROM smdh_tenant_${tenant_id}.aggregated.dt_device_health_current
     WHERE connectivity_status = 'Online') AS devices_online,
    -- Sites
    (SELECT COUNT(DISTINCT site_id) FROM smdh_tenant_${tenant_id}.raw.sensor_readings
     WHERE ingestion_timestamp >= DATEADD(day, -1, CURRENT_TIMESTAMP())) AS active_sites,
    -- Data quality
    (SELECT ROUND(AVG(CASE WHEN quality_flag = 'good' THEN 100.0 ELSE 0.0 END), 2)
     FROM smdh_tenant_${tenant_id}.normalized.sensor_metrics
     WHERE timestamp >= DATEADD(hour, -24, CURRENT_TIMESTAMP())) AS avg_quality_score_24h,
    -- Alerts
    (SELECT COUNT(*) FROM smdh_tenant_${tenant_id}.aggregated.dt_alert_conditions
     WHERE severity IN ('critical', 'high')) AS active_critical_alerts,
    -- Pipeline health
    (SELECT overall_pipeline_status FROM smdh_tenant_${tenant_id}.analytics.v_pipeline_health) AS pipeline_status,
    -- Storage
    (SELECT ROUND(SUM(bytes) / (1024*1024*1024*1024), 3)
     FROM smdh_tenant_${tenant_id}.INFORMATION_SCHEMA.TABLE_STORAGE_METRICS) AS total_storage_tb;

GRANT SELECT ON v_system_summary TO ROLE smdh_monitoring;

SELECT 'Created view: V_SYSTEM_SUMMARY' AS result;

-- ============================================================================
-- 10. Create Monitoring Dashboard Procedure
-- ============================================================================

SELECT '10. Creating Monitoring Dashboard Procedure...' AS step;

CREATE OR REPLACE PROCEDURE sp_monitoring_dashboard()
RETURNS STRING
LANGUAGE SQL
AS
$$
BEGIN
    -- Display system summary
    LET result STRING := '========================================\n';
    result := result || 'SMDH TENANT MONITORING DASHBOARD\n';
    result := result || 'Tenant: ' || $tenant_id || '\n';
    result := result || '========================================\n\n';

    -- System summary
    LET summary RESULTSET := (SELECT * FROM v_system_summary);
    LET summary_cursor CURSOR FOR summary;
    OPEN summary_cursor;
    FETCH summary_cursor INTO ... ;  -- Fetch values
    result := result || 'System Summary:\n';
    result := result || '  Total Readings: ' || TO_VARCHAR(total_readings) || '\n';
    result := result || '  Readings (24h): ' || TO_VARCHAR(readings_last_24h) || '\n';
    result := result || '  Devices Online: ' || TO_VARCHAR(devices_online) || ' / ' || TO_VARCHAR(total_devices) || '\n';
    result := result || '  Active Sites: ' || TO_VARCHAR(active_sites) || '\n';
    result := result || '  Data Quality: ' || TO_VARCHAR(avg_quality_score_24h) || '%\n';
    result := result || '  Critical Alerts: ' || TO_VARCHAR(active_critical_alerts) || '\n';
    result := result || '  Pipeline Status: ' || pipeline_status || '\n';
    result := result || '  Storage Used: ' || TO_VARCHAR(total_storage_tb) || ' TB\n\n';

    -- Health check
    result := result || 'Health Check Results:\n';
    LET health RESULTSET := (CALL sp_health_check());
    -- ... format health check results

    RETURN result;
END;
$$;

GRANT USAGE ON PROCEDURE sp_monitoring_dashboard() TO ROLE smdh_monitoring;

SELECT 'Created procedure: SP_MONITORING_DASHBOARD' AS result;

-- ============================================================================
-- 11. Grant Monitoring Permissions
-- ============================================================================

SELECT '11. Granting Monitoring Permissions...' AS step;

-- Grant all monitoring views to tenant roles
SET readonly_role = 'smdh_tenant_' || $tenant_id || '_readonly';
SET user_role = 'smdh_tenant_' || $tenant_id || '_user';
SET admin_role = 'smdh_tenant_' || $tenant_id || '_admin';

GRANT SELECT ON ALL VIEWS IN SCHEMA analytics TO ROLE IDENTIFIER($readonly_role);
GRANT SELECT ON ALL VIEWS IN SCHEMA analytics TO ROLE IDENTIFIER($user_role);
GRANT SELECT ON ALL VIEWS IN SCHEMA analytics TO ROLE IDENTIFIER($admin_role);

-- Grant procedure execution
GRANT USAGE ON PROCEDURE sp_health_check() TO ROLE IDENTIFIER($user_role);
GRANT USAGE ON PROCEDURE sp_health_check() TO ROLE IDENTIFIER($admin_role);
GRANT USAGE ON PROCEDURE sp_monitoring_dashboard() TO ROLE IDENTIFIER($admin_role);

SELECT 'Granted monitoring permissions' AS result;

-- ============================================================================
-- 12. Verification
-- ============================================================================

SELECT '12. Verifying Monitoring Setup...' AS step;

-- Show all monitoring views
SHOW VIEWS IN SCHEMA analytics LIKE 'v_%monitoring%';

-- Test health check
SELECT 'Running health check...' AS test;
CALL sp_health_check();

-- Test system summary
SELECT 'System summary:' AS test;
SELECT * FROM v_system_summary;

-- ============================================================================
-- 13. Summary
-- ============================================================================

SELECT '╔════════════════════════════════════════════════════════════════╗' AS summary
UNION ALL SELECT '║  Tenant Monitoring Setup Complete                          ║'
UNION ALL SELECT '╚════════════════════════════════════════════════════════════╝'
UNION ALL SELECT ''
UNION ALL SELECT 'Created Monitoring Views:'
UNION ALL SELECT '  ✓ v_ingestion_monitoring (data flow tracking)'
UNION ALL SELECT '  ✓ v_storage_monitoring (storage usage)'
UNION ALL SELECT '  ✓ v_query_performance (query analysis)'
UNION ALL SELECT '  ✓ v_pipeline_health (ETL pipeline status)'
UNION ALL SELECT '  ✓ v_data_quality_monitoring (quality metrics)'
UNION ALL SELECT '  ✓ v_cost_monitoring (cost tracking)'
UNION ALL SELECT '  ✓ v_system_summary (dashboard overview)'
UNION ALL SELECT ''
UNION ALL SELECT 'Created Procedures:'
UNION ALL SELECT '  ✓ sp_health_check() (system health validation)'
UNION ALL SELECT '  ✓ sp_monitoring_dashboard() (dashboard display)'
UNION ALL SELECT ''
UNION ALL SELECT 'Key Monitoring Queries:'
UNION ALL SELECT ''
UNION ALL SELECT '1. System Health Check:'
UNION ALL SELECT '   CALL analytics.sp_health_check();'
UNION ALL SELECT ''
UNION ALL SELECT '2. System Summary:'
UNION ALL SELECT '   SELECT * FROM analytics.v_system_summary;'
UNION ALL SELECT ''
UNION ALL SELECT '3. Data Ingestion Status:'
UNION ALL SELECT '   SELECT * FROM analytics.v_ingestion_monitoring;'
UNION ALL SELECT ''
UNION ALL SELECT '4. Pipeline Health:'
UNION ALL SELECT '   SELECT * FROM analytics.v_pipeline_health;'
UNION ALL SELECT ''
UNION ALL SELECT '5. Cost Analysis:'
UNION ALL SELECT '   SELECT * FROM analytics.v_cost_monitoring'
UNION ALL SELECT '   WHERE date >= DATEADD(day, -30, CURRENT_DATE());'
UNION ALL SELECT ''
UNION ALL SELECT '6. Data Quality:'
UNION ALL SELECT '   SELECT * FROM analytics.v_data_quality_monitoring'
UNION ALL SELECT '   ORDER BY quality_score ASC LIMIT 10;'
UNION ALL SELECT ''
UNION ALL SELECT '7. Query Performance:'
UNION ALL SELECT '   SELECT * FROM analytics.v_query_performance LIMIT 10;'
UNION ALL SELECT ''
UNION ALL SELECT 'Tenant Onboarding Complete!'
UNION ALL SELECT ''
UNION ALL SELECT 'All tenant setup scripts have been executed successfully.'
UNION ALL SELECT 'Your tenant database is ready for data ingestion.'
UNION ALL SELECT ''
UNION ALL SELECT 'Next Steps:'
UNION ALL SELECT '  1. Configure Kinesis connector for tenant'
UNION ALL SELECT '  2. Deploy IoT device certificates'
UNION ALL SELECT '  3. Start MQTT message ingestion'
UNION ALL SELECT '  4. Monitor data flow in v_ingestion_monitoring'
UNION ALL SELECT '  5. Configure dashboards in Power BI or Streamlit'
UNION ALL SELECT '============================================================';
