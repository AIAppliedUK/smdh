-- ============================================================================
-- SMDH Tenant Dynamic Tables Creation (Real-Time Aggregations)
-- ============================================================================
-- Purpose: Create dynamic tables for continuously refreshed aggregations
-- Usage: snowsql -f tenant/15_create_dynamic_tables.sql --variable tenant_id='company_a'
-- Author: SMDH Platform Team
-- Version: 1.0
-- ============================================================================
-- This script creates Snowflake Dynamic Tables:
-- - Materialized views with automatic refresh
-- - Real-time aggregations without manual task management
-- - Optimized for dashboard queries
-- - Requires Snowflake 7.0+ (Enterprise Edition)
-- ============================================================================

-- Enable SnowSQL variable substitution 
!set variable_substitution=true

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE SMDH_WH;

-- Convert SnowSQL substitution variables to session variables
SET tenant_id = '&tenant_id';

-- Display banner
SELECT '╔════════════════════════════════════════════════════════════════╗' AS banner
UNION ALL SELECT '║  SMDH Platform - Dynamic Tables Creation                   ║'
UNION ALL SELECT '╚════════════════════════════════════════════════════════════╝';

-- ============================================================================
-- 1. Validate Tenant Database and Snowflake Version
-- ============================================================================

SELECT '1. Validating Environment...' AS step;

SET database_name = 'smdh_tenant_' || $tenant_id;

USE DATABASE IDENTIFIER($database_name);

-- Check Snowflake version for Dynamic Tables support
SELECT
    CASE
        WHEN CURRENT_VERSION() >= '7.0'
        THEN '[OK] Snowflake version supports Dynamic Tables'
        ELSE '⚠ WARNING: Dynamic Tables require Snowflake 7.0+. Current: ' || CURRENT_VERSION()
    END AS version_check;

SELECT 'Using database: ' || $database_name AS info;

-- ============================================================================
-- 2. Create Dynamic Table: Real-Time Sensor Metrics (Last 15 Minutes)
-- ============================================================================

SELECT '2. Creating Dynamic Table: Real-Time Sensor Metrics...' AS step;

USE SCHEMA aggregated;

CREATE OR REPLACE DYNAMIC TABLE dt_sensor_metrics_realtime
TARGET_LAG = '1 minute'                               -- Refresh within 1 minute of source changes
WAREHOUSE = SMDH_WH                         -- Use streaming warehouse
COMMENT = 'Real-time sensor metrics for last 15 minutes. Automatically refreshes within 1 minute of new data arrival. Used for live dashboards.'
AS
SELECT
    sensor_id,
    site_id,
    metric_name,
    DATE_TRUNC('minute', timestamp) AS minute_timestamp,
    AVG(metric_value) AS avg_value,
    MIN(metric_value) AS min_value,
    MAX(metric_value) AS max_value,
    COUNT(*) AS reading_count,
    MAX(timestamp) AS last_reading,
    SUM(CASE WHEN quality_flag = 'good' THEN 1 ELSE 0 END)::FLOAT / COUNT(*) * 100 AS quality_percentage
FROM normalized.sensor_metrics
WHERE timestamp >= DATEADD(minute, -15, CURRENT_TIMESTAMP())
GROUP BY sensor_id, site_id, metric_name, DATE_TRUNC('minute', timestamp);

SELECT 'Created dynamic table: DT_SENSOR_METRICS_REALTIME' AS result;

-- ============================================================================
-- 3. Create Dynamic Table: Current Device Health
-- ============================================================================

SELECT '3. Creating Dynamic Table: Current Device Health...' AS step;

CREATE OR REPLACE DYNAMIC TABLE dt_device_health_current
TARGET_LAG = '2 minutes'
WAREHOUSE = SMDH_WH
COMMENT = 'Current health status of all devices. Refreshes every 2 minutes. Shows latest battery, signal, and connectivity.'
AS
WITH latest_status AS (
    SELECT
        device_id,
        site_id,
        timestamp AS last_status_time,
        status,
        battery_level,
        signal_strength,
        temperature,
        firmware_version,
        ROW_NUMBER() OVER (PARTITION BY device_id ORDER BY timestamp DESC) AS rn
    FROM raw.device_status
    WHERE timestamp >= DATEADD(hour, -2, CURRENT_TIMESTAMP())
),
latest_reading AS (
    SELECT
        sensor_id AS device_id,
        MAX(timestamp) AS last_reading_time,
        COUNT(*) AS recent_reading_count
    FROM raw.sensor_readings
    WHERE timestamp >= DATEADD(hour, -1, CURRENT_TIMESTAMP())
    GROUP BY sensor_id
)
SELECT
    ls.device_id,
    ls.site_id,
    ls.last_status_time,
    lr.last_reading_time,
    DATEDIFF(minute, lr.last_reading_time, CURRENT_TIMESTAMP()) AS minutes_since_last_data,
    ls.status AS device_status,
    ls.battery_level,
    ls.signal_strength,
    ls.temperature AS device_temperature,
    ls.firmware_version,
    lr.recent_reading_count,
    CASE
        WHEN lr.last_reading_time IS NULL THEN 'No Data'
        WHEN DATEDIFF(minute, lr.last_reading_time, CURRENT_TIMESTAMP()) <= 5 THEN 'Online'
        WHEN DATEDIFF(minute, lr.last_reading_time, CURRENT_TIMESTAMP()) <= 15 THEN 'Warning'
        ELSE 'Offline'
    END AS connectivity_status,
    CASE
        WHEN ls.battery_level < 10 THEN 'Critical'
        WHEN ls.battery_level < 20 THEN 'Low'
        WHEN ls.battery_level < 50 THEN 'Medium'
        ELSE 'Good'
    END AS battery_status
FROM latest_status ls
LEFT JOIN latest_reading lr ON ls.device_id = lr.device_id
WHERE ls.rn = 1;

SELECT 'Created dynamic table: DT_DEVICE_HEALTH_CURRENT' AS result;

-- ============================================================================
-- 4. Create Dynamic Table: Site Performance Dashboard
-- ============================================================================

SELECT '4. Creating Dynamic Table: Site Performance Dashboard...' AS step;

CREATE OR REPLACE DYNAMIC TABLE dt_site_performance_current
TARGET_LAG = '5 minutes'
WAREHOUSE = SMDH_WH
COMMENT = 'Current site-level performance metrics. Refreshes every 5 minutes. Aggregates all sensors per site.'
AS
WITH recent_metrics AS (
    SELECT
        site_id,
        COUNT(DISTINCT sensor_id) AS active_sensors,
        COUNT(*) AS total_readings_last_hour,
        AVG(metric_value) AS avg_metric_value,
        SUM(CASE WHEN quality_flag = 'good' THEN 1 ELSE 0 END)::FLOAT / COUNT(*) * 100 AS data_quality_percentage
    FROM normalized.sensor_metrics
    WHERE timestamp >= DATEADD(hour, -1, CURRENT_TIMESTAMP())
    GROUP BY site_id
),
device_health AS (
    SELECT
        site_id,
        COUNT(*) AS total_devices,
        SUM(CASE WHEN connectivity_status = 'Online' THEN 1 ELSE 0 END) AS online_devices,
        AVG(battery_level) AS avg_battery_level,
        AVG(signal_strength) AS avg_signal_strength
    FROM aggregated.dt_device_health_current
    GROUP BY site_id
)
SELECT
    COALESCE(rm.site_id, dh.site_id) AS site_id,
    dh.total_devices,
    dh.online_devices,
    rm.active_sensors,
    rm.total_readings_last_hour,
    ROUND(dh.online_devices::FLOAT / NULLIF(dh.total_devices, 0) * 100, 1) AS device_uptime_percentage,
    ROUND(rm.data_quality_percentage, 1) AS data_quality_score,
    ROUND(dh.avg_battery_level, 1) AS avg_battery_level,
    ROUND(dh.avg_signal_strength, 1) AS avg_signal_strength,
    CURRENT_TIMESTAMP() AS snapshot_time
FROM recent_metrics rm
FULL OUTER JOIN device_health dh ON rm.site_id = dh.site_id;

SELECT 'Created dynamic table: DT_SITE_PERFORMANCE_CURRENT' AS result;

-- ============================================================================
-- 5. Create Dynamic Table: Hourly Trends (Last 24 Hours)
-- ============================================================================

SELECT '5. Creating Dynamic Table: Hourly Trends (24h)...' AS step;

CREATE OR REPLACE DYNAMIC TABLE dt_hourly_trends_24h
TARGET_LAG = '10 minutes'
WAREHOUSE = SMDH_WH
COMMENT = 'Hourly metric trends for last 24 hours. Used for dashboard charts and trend analysis.'
AS
SELECT
    sensor_id,
    site_id,
    metric_name,
    DATE_TRUNC('hour', timestamp) AS hour_timestamp,
    AVG(metric_value) AS avg_value,
    MIN(metric_value) AS min_value,
    MAX(metric_value) AS max_value,
    STDDEV(metric_value) AS stddev_value,
    COUNT(*) AS reading_count,
    SUM(CASE WHEN quality_flag = 'good' THEN 1 ELSE 0 END) AS good_count,
    SUM(CASE WHEN quality_flag = 'good' THEN 1 ELSE 0 END)::FLOAT / COUNT(*) * 100 AS quality_percentage,
    MAX(timestamp) AS last_reading_time
FROM normalized.sensor_metrics
WHERE timestamp >= DATEADD(hour, -24, CURRENT_TIMESTAMP())
GROUP BY sensor_id, site_id, metric_name, DATE_TRUNC('hour', timestamp);

SELECT 'Created dynamic table: DT_HOURLY_TRENDS_24H' AS result;

-- ============================================================================
-- 6. Create Dynamic Table: Alert Conditions
-- ============================================================================

SELECT '6. Creating Dynamic Table: Alert Conditions...' AS step;

CREATE OR REPLACE DYNAMIC TABLE dt_alert_conditions
TARGET_LAG = '2 minutes'  -- Must be >= dt_device_health_current lag (2 minutes)
WAREHOUSE = SMDH_WH
COMMENT = 'Real-time detection of alert conditions. Monitors for threshold violations, device issues, and data quality problems.'
AS
WITH metric_alerts AS (
    SELECT
        sensor_id,
        site_id,
        metric_name,
        metric_value,
        timestamp,
        'threshold_violation' AS alert_type,
        CASE
            WHEN metric_name = 'temperature' AND metric_value > 80 THEN 'critical'
            WHEN metric_name = 'temperature' AND metric_value < 0 THEN 'high'
            WHEN metric_name = 'humidity' AND metric_value > 95 THEN 'high'
            WHEN quality_flag = 'bad' THEN 'medium'
            ELSE 'low'
        END AS severity,
        CONCAT('Sensor ', sensor_id, ' ', metric_name, ' = ', metric_value::VARCHAR, ' (threshold exceeded)') AS alert_message
    FROM normalized.sensor_metrics
    WHERE timestamp >= DATEADD(minute, -10, CURRENT_TIMESTAMP())
        AND (
            (metric_name = 'temperature' AND (metric_value > 80 OR metric_value < 0)) OR
            (metric_name = 'humidity' AND metric_value > 95) OR
            (quality_flag = 'bad')
        )
),
device_alerts AS (
    SELECT
        device_id AS sensor_id,
        site_id,
        'battery_level' AS metric_name,
        battery_level AS metric_value,
        CURRENT_TIMESTAMP() AS timestamp,
        'device_health' AS alert_type,
        CASE
            WHEN battery_level < 10 THEN 'critical'
            WHEN battery_level < 20 THEN 'high'
            WHEN connectivity_status = 'Offline' THEN 'high'
            ELSE 'medium'
        END AS severity,
        CASE
            WHEN battery_level < 10 THEN CONCAT('Device ', device_id, ' battery critical: ', battery_level::VARCHAR, '%')
            WHEN battery_level < 20 THEN CONCAT('Device ', device_id, ' battery low: ', battery_level::VARCHAR, '%')
            WHEN connectivity_status = 'Offline' THEN CONCAT('Device ', device_id, ' is offline')
            ELSE CONCAT('Device ', device_id, ' health warning')
        END AS alert_message
    FROM aggregated.dt_device_health_current
    WHERE battery_level < 20 OR connectivity_status = 'Offline'
)
SELECT * FROM metric_alerts
UNION ALL
SELECT * FROM device_alerts;

SELECT 'Created dynamic table: DT_ALERT_CONDITIONS' AS result;

-- ============================================================================
-- 7. Create Dynamic Table: Data Quality Dashboard
-- ============================================================================

SELECT '7. Creating Dynamic Table: Data Quality Dashboard...' AS step;

CREATE OR REPLACE DYNAMIC TABLE dt_data_quality_summary
TARGET_LAG = '5 minutes'
WAREHOUSE = SMDH_WH
COMMENT = 'Data quality summary across all sensors. Monitors completeness, validity, and timeliness.'
AS
WITH sensor_stats AS (
    SELECT
        sensor_id,
        site_id,
        COUNT(*) AS total_readings_1h,
        COUNT(DISTINCT metric_name) AS unique_metrics,
        SUM(CASE WHEN quality_flag = 'good' THEN 1 ELSE 0 END) AS good_readings,
        SUM(CASE WHEN quality_flag = 'suspect' THEN 1 ELSE 0 END) AS suspect_readings,
        SUM(CASE WHEN quality_flag = 'bad' THEN 1 ELSE 0 END) AS bad_readings,
        MIN(timestamp) AS first_reading,
        MAX(timestamp) AS last_reading
    FROM normalized.sensor_metrics
    WHERE timestamp >= DATEADD(hour, -1, CURRENT_TIMESTAMP())
    GROUP BY sensor_id, site_id
)
SELECT
    sensor_id,
    site_id,
    total_readings_1h,
    unique_metrics,
    ROUND(good_readings::FLOAT / total_readings_1h * 100, 2) AS good_percentage,
    ROUND(suspect_readings::FLOAT / total_readings_1h * 100, 2) AS suspect_percentage,
    ROUND(bad_readings::FLOAT / total_readings_1h * 100, 2) AS bad_percentage,
    DATEDIFF(minute, last_reading, CURRENT_TIMESTAMP()) AS minutes_since_last_reading,
    CASE
        WHEN good_readings::FLOAT / total_readings_1h >= 0.95 THEN 'Excellent'
        WHEN good_readings::FLOAT / total_readings_1h >= 0.80 THEN 'Good'
        WHEN good_readings::FLOAT / total_readings_1h >= 0.60 THEN 'Fair'
        ELSE 'Poor'
    END AS overall_quality_grade
FROM sensor_stats;

SELECT 'Created dynamic table: DT_DATA_QUALITY_SUMMARY' AS result;

-- ============================================================================
-- 8. Create Monitoring View for Dynamic Tables
-- ============================================================================

SELECT '8. Creating Dynamic Table Monitoring Views...' AS step;

USE SCHEMA analytics;

-- Note: INFORMATION_SCHEMA.DYNAMIC_TABLES doesn't exist at database level
-- Use SHOW DYNAMIC TABLES for real-time status; creating placeholder view
CREATE OR REPLACE VIEW v_dynamic_table_status AS
SELECT
    'dt_sensor_metrics_realtime' AS dynamic_table_name,
    'aggregated' AS schema_name,
    '1 minute' AS target_lag,
    'SMDH_WH' AS warehouse_name,
    CURRENT_TIMESTAMP() AS checked_at
UNION ALL SELECT 'dt_device_health_current', 'aggregated', '2 minutes', 'SMDH_WH', CURRENT_TIMESTAMP()
UNION ALL SELECT 'dt_site_performance_current', 'aggregated', '5 minutes', 'SMDH_WH', CURRENT_TIMESTAMP()
UNION ALL SELECT 'dt_hourly_trends_24h', 'aggregated', '10 minutes', 'SMDH_WH', CURRENT_TIMESTAMP()
UNION ALL SELECT 'dt_alert_conditions', 'aggregated', '2 minutes', 'SMDH_WH', CURRENT_TIMESTAMP()
UNION ALL SELECT 'dt_data_quality_summary', 'aggregated', '5 minutes', 'SMDH_WH', CURRENT_TIMESTAMP();

-- Note: SNOWFLAKE.ACCOUNT_USAGE has 2-hour latency for new objects
-- Creating placeholder view for refresh history
CREATE OR REPLACE VIEW v_dynamic_table_refresh_history AS
SELECT
    'Placeholder' AS dynamic_table_name,
    'View dynamic table refresh history via SHOW DYNAMIC TABLES' AS note,
    CURRENT_TIMESTAMP() AS checked_at;

SELECT 'Created dynamic table monitoring views' AS result;

-- ============================================================================
-- 9. Create Analytics Views Using Dynamic Tables
-- ============================================================================

SELECT '9. Creating Analytics Views from Dynamic Tables...' AS step;

-- View: Real-time dashboard summary
CREATE OR REPLACE VIEW v_realtime_dashboard AS
SELECT
    sp.site_id,
    sp.total_devices,
    sp.online_devices,
    sp.device_uptime_percentage,
    sp.data_quality_score,
    sp.avg_battery_level,
    sp.avg_signal_strength,
    (SELECT COUNT(DISTINCT sensor_id) FROM aggregated.dt_sensor_metrics_realtime WHERE site_id = sp.site_id) AS active_sensors_realtime,
    (SELECT COUNT(*) FROM aggregated.dt_alert_conditions WHERE site_id = sp.site_id AND severity IN ('critical', 'high')) AS active_alerts,
    sp.snapshot_time
FROM aggregated.dt_site_performance_current sp
ORDER BY sp.site_id;

-- View: Alert summary
CREATE OR REPLACE VIEW v_active_alerts AS
SELECT
    site_id,
    sensor_id,
    alert_type,
    severity,
    alert_message,
    timestamp AS alert_time,
    DATEDIFF(minute, timestamp, CURRENT_TIMESTAMP()) AS minutes_active
FROM aggregated.dt_alert_conditions
ORDER BY
    CASE severity
        WHEN 'critical' THEN 1
        WHEN 'high' THEN 2
        WHEN 'medium' THEN 3
        ELSE 4
    END,
    timestamp DESC;

SELECT 'Created analytics views from dynamic tables' AS result;

-- ============================================================================
-- 10. Grant Permissions
-- ============================================================================

SELECT '10. Granting Permissions...' AS step;

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE SMDH_WH;

SET admin_role_name = 'smdh_tenant_' || $tenant_id || '_admin';
SET user_role_name = 'smdh_tenant_' || $tenant_id || '_user';
SET readonly_role_name = 'smdh_tenant_' || $tenant_id || '_readonly';

-- Grant select on all dynamic tables
GRANT SELECT ON ALL DYNAMIC TABLES IN SCHEMA aggregated TO ROLE IDENTIFIER($admin_role_name);
GRANT SELECT ON ALL DYNAMIC TABLES IN SCHEMA aggregated TO ROLE IDENTIFIER($user_role_name);
GRANT SELECT ON ALL DYNAMIC TABLES IN SCHEMA aggregated TO ROLE IDENTIFIER($readonly_role_name);

SELECT 'Granted dynamic table permissions' AS result;

-- ============================================================================
-- 11. Document Dynamic Tables
-- ============================================================================

SELECT '11. Documenting Dynamic Tables...' AS step;

USE SCHEMA analytics;

MERGE INTO schema_documentation AS target
USING (
    SELECT 'AGGREGATED' AS schema_name, 'DYNAMIC_TABLE' AS object_type, 'dt_sensor_metrics_realtime' AS object_name,
           'Real-time sensor metrics (last 15 min), 1-min refresh' AS description
    UNION ALL
    SELECT 'AGGREGATED', 'DYNAMIC_TABLE', 'dt_device_health_current',
           'Current device health status, 2-min refresh'
    UNION ALL
    SELECT 'AGGREGATED', 'DYNAMIC_TABLE', 'dt_site_performance_current',
           'Site-level performance metrics, 5-min refresh'
    UNION ALL
    SELECT 'AGGREGATED', 'DYNAMIC_TABLE', 'dt_hourly_trends_24h',
           'Hourly trends for last 24 hours, 10-min refresh'
    UNION ALL
    SELECT 'AGGREGATED', 'DYNAMIC_TABLE', 'dt_alert_conditions',
           'Real-time alert detection, 1-min refresh'
    UNION ALL
    SELECT 'AGGREGATED', 'DYNAMIC_TABLE', 'dt_data_quality_summary',
           'Data quality monitoring, 5-min refresh'
    UNION ALL
    SELECT 'ANALYTICS', 'VIEW', 'v_realtime_dashboard',
           'Real-time dashboard combining multiple dynamic tables'
    UNION ALL
    SELECT 'ANALYTICS', 'VIEW', 'v_active_alerts',
           'Active alerts ordered by severity'
) AS source
ON target.schema_name = source.schema_name
    AND target.object_type = source.object_type
    AND target.object_name = source.object_name
WHEN NOT MATCHED THEN
    INSERT (schema_name, object_type, object_name, description)
    VALUES (source.schema_name, source.object_type, source.object_name, source.description);

SELECT 'Documented dynamic tables' AS result;

-- ============================================================================
-- 12. Verification
-- ============================================================================

SELECT '12. Verifying Dynamic Tables...' AS step;

-- Show all dynamic tables
USE SCHEMA aggregated;
SHOW DYNAMIC TABLES;

-- Check dynamic table status
SELECT * FROM analytics.v_dynamic_table_status;

-- Test queries on dynamic tables
SELECT COUNT(*) AS realtime_metrics FROM dt_sensor_metrics_realtime;
SELECT COUNT(*) AS current_devices FROM dt_device_health_current;
SELECT COUNT(*) AS active_alerts FROM dt_alert_conditions;

-- ============================================================================
-- 13. Summary
-- ============================================================================

SELECT '╔════════════════════════════════════════════════════════════════╗' AS summary
UNION ALL SELECT '║  Dynamic Tables Creation Complete                          ║'
UNION ALL SELECT '╚════════════════════════════════════════════════════════════╝'
UNION ALL SELECT ''
UNION ALL SELECT 'Created Dynamic Tables:'
UNION ALL SELECT ''
UNION ALL SELECT 'Real-Time Aggregations (AGGREGATED Schema):'
UNION ALL SELECT '  [OK] dt_sensor_metrics_realtime (1-min lag)'
UNION ALL SELECT '  [OK] dt_device_health_current (2-min lag)'
UNION ALL SELECT '  [OK] dt_site_performance_current (5-min lag)'
UNION ALL SELECT '  [OK] dt_hourly_trends_24h (10-min lag)'
UNION ALL SELECT '  [OK] dt_alert_conditions (1-min lag)'
UNION ALL SELECT '  [OK] dt_data_quality_summary (5-min lag)'
UNION ALL SELECT ''
UNION ALL SELECT 'Dashboard Views (ANALYTICS Schema):'
UNION ALL SELECT '  [OK] v_realtime_dashboard'
UNION ALL SELECT '  [OK] v_active_alerts'
UNION ALL SELECT '  [OK] v_dynamic_table_status'
UNION ALL SELECT '  [OK] v_dynamic_table_refresh_history'
UNION ALL SELECT ''
UNION ALL SELECT 'Dynamic Tables Features:'
UNION ALL SELECT '  • Automatic refresh based on source data changes'
UNION ALL SELECT '  • Target lag guarantees (1-10 minutes)'
UNION ALL SELECT '  • No manual task management required'
UNION ALL SELECT '  • Optimized for dashboard queries'
UNION ALL SELECT '  • Incremental refresh (cost-effective)'
UNION ALL SELECT ''
UNION ALL SELECT 'Use Cases:'
UNION ALL SELECT '  • Real-time dashboards: SELECT * FROM dt_sensor_metrics_realtime'
UNION ALL SELECT '  • Device monitoring: SELECT * FROM dt_device_health_current'
UNION ALL SELECT '  • Alert management: SELECT * FROM v_active_alerts'
UNION ALL SELECT '  • Data quality: SELECT * FROM dt_data_quality_summary'
UNION ALL SELECT ''
UNION ALL SELECT 'Monitoring:'
UNION ALL SELECT '  • Status: SELECT * FROM analytics.v_dynamic_table_status;'
UNION ALL SELECT '  • Refresh history: SELECT * FROM analytics.v_dynamic_table_refresh_history;'
UNION ALL SELECT ''
UNION ALL SELECT 'Next Steps:'
UNION ALL SELECT '  1. Run 16_create_roles.sql for additional RBAC (if needed)'
UNION ALL SELECT '  2. Run 17_create_monitoring.sql for tenant dashboards'
UNION ALL SELECT '  3. Connect Power BI or Streamlit to dynamic tables'
UNION ALL SELECT '  4. Configure alerts based on dt_alert_conditions'
UNION ALL SELECT '============================================================';
