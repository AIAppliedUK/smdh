-- ============================================================================
-- SMDH Tenant Tasks Creation (ETL Automation)
-- ============================================================================
-- Purpose: Create automated tasks for data processing pipeline
-- Usage: snowsql -f tenant/14_create_tasks.sql -D tenant_id='company_a'
-- Author: SMDH Platform Team
-- Version: 1.0
-- ============================================================================
-- This script creates Snowflake Tasks for automated ETL:
-- - Task to normalize raw sensor readings
-- - Task to generate hourly aggregations
-- - Task to generate daily aggregations
-- - Task to process device events
-- - Task graph with dependencies
-- ============================================================================

USE ROLE ACCOUNTADMIN;

-- Display banner
SELECT '╔════════════════════════════════════════════════════════════════╗' AS banner
UNION ALL SELECT '║  SMDH Platform - Tenant Tasks Creation                     ║'
UNION ALL SELECT '╚════════════════════════════════════════════════════════════╝';

-- ============================================================================
-- 1. Validate Tenant Database
-- ============================================================================

SELECT '1. Validating Tenant Database...' AS step;

SET database_name = 'smdh_tenant_' || '&tenant_id';

USE DATABASE IDENTIFIER(&database_name);

SELECT 'Using database: ' || '&database_name' AS info;

-- ============================================================================
-- 2. Enable Task Execution for Database
-- ============================================================================

SELECT '2. Configuring Task Execution...' AS step;

-- Tasks require EXECUTE TASK privilege
GRANT EXECUTE TASK ON ACCOUNT TO ROLE ACCOUNTADMIN;

SELECT 'Task execution enabled' AS result;

-- ============================================================================
-- 3. Create Root Task: Normalize Sensor Readings
-- ============================================================================

SELECT '3. Creating Task: Normalize Sensor Readings...' AS step;

USE SCHEMA raw;

CREATE OR REPLACE TASK task_normalize_sensor_readings
    WAREHOUSE = smdh_etl_wh
    SCHEDULE = '1 MINUTE'                             -- Run every minute
    WHEN SYSTEM$STREAM_HAS_DATA('sensor_readings_stream')
    COMMENT = 'Normalizes raw sensor readings into flattened metrics table. Runs every minute when new data arrives.'
AS
INSERT INTO smdh_tenant_${tenant_id}.normalized.sensor_metrics (
    tenant_id,
    sensor_id,
    site_id,
    device_id,
    timestamp,
    metric_name,
    metric_value,
    metric_unit,
    quality_flag,
    validation_status,
    sensor_type,
    source_reading_id
)
SELECT
    tenant_id,
    sensor_id,
    site_id,
    device_id,
    timestamp,

    -- Flatten VARIANT payload to individual metrics
    metric.key::VARCHAR AS metric_name,
    metric.value::FLOAT AS metric_value,

    -- Extract unit if present in payload metadata
    COALESCE(payload:units[metric.key]::VARCHAR, 'unknown') AS metric_unit,

    -- Quality assessment
    CASE
        WHEN metric.value IS NULL THEN 'bad'
        WHEN TRY_CAST(metric.value AS FLOAT) IS NULL THEN 'bad'
        WHEN ABS(metric.value::FLOAT) > 1000000 THEN 'suspect'  -- Outlier detection
        ELSE 'good'
    END AS quality_flag,

    'auto_validated' AS validation_status,
    payload:sensor_type::VARCHAR AS sensor_type,
    reading_id AS source_reading_id

FROM sensor_readings_stream sr,
    LATERAL FLATTEN(input => sr.payload) metric
WHERE metric.key NOT IN ('timestamp', 'sensor_type', 'units', 'metadata')  -- Exclude metadata fields
    AND timestamp >= DATEADD(day, -1, CURRENT_TIMESTAMP())  -- Only recent data
    AND is_valid = TRUE;

-- Log execution to monitoring table
INSERT INTO smdh_infrastructure.monitoring.task_execution_log (
    tenant_id,
    task_name,
    end_time,
    status,
    rows_processed
)
SELECT
    &tenant_id,
    'task_normalize_sensor_readings',
    CURRENT_TIMESTAMP(),
    'success',
    COUNT(*)
FROM sensor_readings_stream;

SELECT 'Created task: TASK_NORMALIZE_SENSOR_READINGS' AS result;

-- ============================================================================
-- 4. Create Task: Process Device Events
-- ============================================================================

SELECT '4. Creating Task: Process Device Events...' AS step;

CREATE OR REPLACE TASK task_process_device_status
    WAREHOUSE = smdh_etl_wh
    SCHEDULE = '2 MINUTE'                             -- Run every 2 minutes
    WHEN SYSTEM$STREAM_HAS_DATA('device_status_stream')
    COMMENT = 'Processes device status changes into normalized events for alerting.'
AS
INSERT INTO smdh_tenant_${tenant_id}.normalized.device_events (
    tenant_id,
    device_id,
    site_id,
    event_timestamp,
    event_type,
    event_category,
    severity,
    event_description,
    event_data,
    previous_state,
    new_state
)
SELECT
    ds.tenant_id,
    ds.device_id,
    ds.site_id,
    ds.timestamp AS event_timestamp,

    -- Determine event type based on status
    CASE
        WHEN ds.status = 'offline' THEN 'disconnection'
        WHEN ds.status = 'online' THEN 'connection'
        WHEN ds.status = 'error' THEN 'error'
        ELSE 'status_change'
    END AS event_type,

    'health' AS event_category,

    -- Determine severity
    CASE
        WHEN ds.status = 'error' THEN 'high'
        WHEN ds.status = 'offline' THEN 'medium'
        WHEN ds.battery_level < 20 THEN 'medium'
        WHEN ds.battery_level < 10 THEN 'high'
        ELSE 'info'
    END AS severity,

    -- Generate description
    CONCAT(
        'Device ', ds.device_id, ' status: ', ds.status,
        CASE WHEN ds.battery_level IS NOT NULL
            THEN ' (Battery: ' || ds.battery_level::VARCHAR || '%)'
            ELSE ''
        END
    ) AS event_description,

    -- Store full status payload
    OBJECT_CONSTRUCT(
        'status', ds.status,
        'battery_level', ds.battery_level,
        'signal_strength', ds.signal_strength,
        'firmware_version', ds.firmware_version,
        'temperature', ds.temperature
    ) AS event_data,

    -- Get previous state (if available)
    LAG(ds.status) OVER (PARTITION BY ds.device_id ORDER BY ds.timestamp) AS previous_state,
    ds.status AS new_state

FROM device_status_stream ds
WHERE ds.timestamp >= DATEADD(hour, -24, CURRENT_TIMESTAMP());

SELECT 'Created task: TASK_PROCESS_DEVICE_STATUS' AS result;

-- ============================================================================
-- 5. Create Task: Hourly Aggregations
-- ============================================================================

SELECT '5. Creating Task: Hourly Aggregations...' AS step;

USE SCHEMA normalized;

CREATE OR REPLACE TASK task_aggregate_hourly
    WAREHOUSE = smdh_etl_wh
    SCHEDULE = '5 MINUTE'                             -- Run every 5 minutes
    AFTER task_normalize_sensor_readings              -- Depends on normalization
    WHEN SYSTEM$STREAM_HAS_DATA('sensor_metrics_stream')
    COMMENT = 'Aggregates sensor metrics into hourly rollups. Runs after normalization completes.'
AS
MERGE INTO smdh_tenant_${tenant_id}.aggregated.sensor_metrics_hourly AS target
USING (
    SELECT
        tenant_id,
        sensor_id,
        site_id,
        metric_name,
        DATE_TRUNC('hour', timestamp) AS hour_timestamp,
        AVG(metric_value) AS avg_value,
        MIN(metric_value) AS min_value,
        MAX(metric_value) AS max_value,
        SUM(metric_value) AS sum_value,
        STDDEV(metric_value) AS stddev_value,
        COUNT(*) AS count_readings,
        SUM(CASE WHEN quality_flag = 'good' THEN 1 ELSE 0 END) AS good_readings,
        SUM(CASE WHEN quality_flag = 'suspect' THEN 1 ELSE 0 END) AS suspect_readings,
        SUM(CASE WHEN quality_flag = 'bad' THEN 1 ELSE 0 END) AS bad_readings,
        (SUM(CASE WHEN quality_flag = 'good' THEN 1 ELSE 0 END)::FLOAT / COUNT(*)) * 100 AS data_quality_score
    FROM sensor_metrics_stream
    WHERE timestamp >= DATEADD(hour, -2, CURRENT_TIMESTAMP())  -- Only recent data
    GROUP BY tenant_id, sensor_id, site_id, metric_name, hour_timestamp
) AS source
ON target.hour_timestamp = source.hour_timestamp
    AND target.sensor_id = source.sensor_id
    AND target.metric_name = source.metric_name
WHEN MATCHED THEN
    UPDATE SET
        avg_value = source.avg_value,
        min_value = source.min_value,
        max_value = source.max_value,
        sum_value = source.sum_value,
        stddev_value = source.stddev_value,
        count_readings = source.count_readings,
        good_readings = source.good_readings,
        suspect_readings = source.suspect_readings,
        bad_readings = source.bad_readings,
        data_quality_score = source.data_quality_score,
        calculated_timestamp = CURRENT_TIMESTAMP()
WHEN NOT MATCHED THEN
    INSERT (
        tenant_id, sensor_id, site_id, metric_name, hour_timestamp,
        avg_value, min_value, max_value, sum_value, stddev_value,
        count_readings, good_readings, suspect_readings, bad_readings,
        data_quality_score, calculated_timestamp
    )
    VALUES (
        source.tenant_id, source.sensor_id, source.site_id, source.metric_name, source.hour_timestamp,
        source.avg_value, source.min_value, source.max_value, source.sum_value, source.stddev_value,
        source.count_readings, source.good_readings, source.suspect_readings, source.bad_readings,
        source.data_quality_score, CURRENT_TIMESTAMP()
    );

SELECT 'Created task: TASK_AGGREGATE_HOURLY' AS result;

-- ============================================================================
-- 6. Create Task: Daily Aggregations
-- ============================================================================

SELECT '6. Creating Task: Daily Aggregations...' AS step;

CREATE OR REPLACE TASK task_aggregate_daily
    WAREHOUSE = smdh_etl_wh
    SCHEDULE = 'USING CRON 0 1 * * * UTC'            -- Run at 01:00 UTC daily
    COMMENT = 'Aggregates sensor metrics into daily rollups. Runs once per day after midnight.'
AS
MERGE INTO smdh_tenant_${tenant_id}.aggregated.sensor_metrics_daily AS target
USING (
    SELECT
        tenant_id,
        sensor_id,
        site_id,
        metric_name,
        DATE_TRUNC('day', timestamp)::DATE AS day_date,
        AVG(metric_value) AS avg_value,
        MIN(metric_value) AS min_value,
        MAX(metric_value) AS max_value,
        SUM(metric_value) AS sum_value,
        STDDEV(metric_value) AS stddev_value,
        COUNT(*) AS count_readings,
        MIN(timestamp) AS first_reading_time,
        MAX(timestamp) AS last_reading_time,
        SUM(CASE WHEN quality_flag = 'good' THEN 1 ELSE 0 END) AS good_readings,
        SUM(CASE WHEN quality_flag = 'suspect' THEN 1 ELSE 0 END) AS suspect_readings,
        SUM(CASE WHEN quality_flag = 'bad' THEN 1 ELSE 0 END) AS bad_readings,
        (24 - COUNT(DISTINCT DATE_TRUNC('hour', timestamp))) AS missing_hours,
        (COUNT(DISTINCT DATE_TRUNC('hour', timestamp))::FLOAT / 24) * 100 AS data_completeness_score
    FROM smdh_tenant_${tenant_id}.normalized.sensor_metrics
    WHERE DATE_TRUNC('day', timestamp)::DATE = DATEADD(day, -1, CURRENT_DATE())  -- Previous day
    GROUP BY tenant_id, sensor_id, site_id, metric_name, day_date
) AS source
ON target.day_date = source.day_date
    AND target.sensor_id = source.sensor_id
    AND target.metric_name = source.metric_name
WHEN MATCHED THEN
    UPDATE SET
        avg_value = source.avg_value,
        min_value = source.min_value,
        max_value = source.max_value,
        sum_value = source.sum_value,
        stddev_value = source.stddev_value,
        count_readings = source.count_readings,
        first_reading_time = source.first_reading_time,
        last_reading_time = source.last_reading_time,
        good_readings = source.good_readings,
        suspect_readings = source.suspect_readings,
        bad_readings = source.bad_readings,
        missing_hours = source.missing_hours,
        data_completeness_score = source.data_completeness_score,
        calculated_timestamp = CURRENT_TIMESTAMP()
WHEN NOT MATCHED THEN
    INSERT (
        tenant_id, sensor_id, site_id, metric_name, day_date,
        avg_value, min_value, max_value, sum_value, stddev_value,
        count_readings, first_reading_time, last_reading_time,
        good_readings, suspect_readings, bad_readings,
        missing_hours, data_completeness_score, calculated_timestamp
    )
    VALUES (
        source.tenant_id, source.sensor_id, source.site_id, source.metric_name, source.day_date,
        source.avg_value, source.min_value, source.max_value, source.sum_value, source.stddev_value,
        source.count_readings, source.first_reading_time, source.last_reading_time,
        source.good_readings, source.suspect_readings, source.bad_readings,
        source.missing_hours, source.data_completeness_score, CURRENT_TIMESTAMP()
    );

SELECT 'Created task: TASK_AGGREGATE_DAILY' AS result;

-- ============================================================================
-- 7. Create Task: Update Device Registry
-- ============================================================================

SELECT '7. Creating Task: Update Device Registry...' AS step;

USE SCHEMA raw;

CREATE OR REPLACE TASK task_update_device_registry
    WAREHOUSE = smdh_monitoring_wh                    -- Use small monitoring warehouse
    SCHEDULE = '10 MINUTE'                            -- Run every 10 minutes
    COMMENT = 'Updates device connection timestamps and message counts in infrastructure registry.'
AS
MERGE INTO smdh_infrastructure.tenant_configs.devices AS target
USING (
    SELECT
        &tenant_id AS tenant_id,
        sensor_id AS device_id,
        MAX(timestamp) AS last_message_timestamp,
        COUNT(*) AS message_count
    FROM smdh_tenant_${tenant_id}.raw.sensor_readings
    WHERE ingestion_timestamp >= DATEADD(minute, -15, CURRENT_TIMESTAMP())
    GROUP BY sensor_id
) AS source
ON target.tenant_id = source.tenant_id
    AND target.device_id = source.device_id
WHEN MATCHED THEN
    UPDATE SET
        last_message_timestamp = source.last_message_timestamp,
        total_messages = target.total_messages + source.message_count;

SELECT 'Created task: TASK_UPDATE_DEVICE_REGISTRY' AS result;

-- ============================================================================
-- 8. Create Task Monitoring View
-- ============================================================================

SELECT '8. Creating Task Monitoring Views...' AS step;

USE SCHEMA analytics;

CREATE OR REPLACE VIEW v_task_status AS
SELECT
    name AS task_name,
    database_name,
    schema_name,
    warehouse AS warehouse_name,
    schedule AS task_schedule,
    state AS task_state,
    condition AS task_condition,
    created_on,
    comment AS description
FROM smdh_tenant_${tenant_id}.INFORMATION_SCHEMA.TASKS
ORDER BY created_on DESC;

-- Create view for task execution history
CREATE OR REPLACE VIEW v_task_history AS
SELECT
    name AS task_name,
    database_name || '.' || schema_name || '.' || name AS full_task_name,
    state,
    scheduled_time,
    query_start_time,
    completed_time,
    DATEDIFF(second, query_start_time, completed_time) AS execution_seconds,
    error_code,
    error_message
FROM SNOWFLAKE.ACCOUNT_USAGE.TASK_HISTORY
WHERE database_name = 'smdh_tenant_' || '&tenant_id'
    AND scheduled_time >= DATEADD(day, -7, CURRENT_TIMESTAMP())
ORDER BY scheduled_time DESC;

SELECT 'Created task monitoring views' AS result;

-- ============================================================================
-- 9. Create Task Management Procedures
-- ============================================================================

SELECT '9. Creating Task Management Procedures...' AS step;

-- Procedure to resume all tasks
CREATE OR REPLACE PROCEDURE sp_resume_all_tasks()
RETURNS STRING
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
BEGIN
    ALTER TASK smdh_tenant_${tenant_id}.raw.task_normalize_sensor_readings RESUME;
    ALTER TASK smdh_tenant_${tenant_id}.raw.task_process_device_status RESUME;
    ALTER TASK smdh_tenant_${tenant_id}.normalized.task_aggregate_hourly RESUME;
    ALTER TASK smdh_tenant_${tenant_id}.normalized.task_aggregate_daily RESUME;
    ALTER TASK smdh_tenant_${tenant_id}.raw.task_update_device_registry RESUME;

    RETURN 'All tasks resumed successfully';
EXCEPTION
    WHEN OTHER THEN
        RETURN 'Error resuming tasks: ' || SQLERRM;
END;
$$;

-- Procedure to suspend all tasks
CREATE OR REPLACE PROCEDURE sp_suspend_all_tasks()
RETURNS STRING
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
BEGIN
    -- Suspend in reverse dependency order
    ALTER TASK smdh_tenant_${tenant_id}.normalized.task_aggregate_hourly SUSPEND;
    ALTER TASK smdh_tenant_${tenant_id}.normalized.task_aggregate_daily SUSPEND;
    ALTER TASK smdh_tenant_${tenant_id}.raw.task_normalize_sensor_readings SUSPEND;
    ALTER TASK smdh_tenant_${tenant_id}.raw.task_process_device_status SUSPEND;
    ALTER TASK smdh_tenant_${tenant_id}.raw.task_update_device_registry SUSPEND;

    RETURN 'All tasks suspended successfully';
EXCEPTION
    WHEN OTHER THEN
        RETURN 'Error suspending tasks: ' || SQLERRM;
END;
$$;

SELECT 'Created task management procedures' AS result;

-- ============================================================================
-- 10. Resume All Tasks (Start the Pipeline)
-- ============================================================================

SELECT '10. Starting Task Pipeline...' AS step;

-- Resume tasks in dependency order (root tasks first)
ALTER TASK task_normalize_sensor_readings RESUME;
ALTER TASK task_process_device_status RESUME;
ALTER TASK task_update_device_registry RESUME;
ALTER TASK task_aggregate_hourly RESUME;
ALTER TASK task_aggregate_daily RESUME;

SELECT 'All tasks started successfully' AS result;

-- ============================================================================
-- 11. Grant Task Permissions
-- ============================================================================

SELECT '11. Granting Task Permissions...' AS step;

USE ROLE ACCOUNTADMIN;

SET admin_role_name = 'smdh_tenant_' || '&tenant_id' || '_admin';

-- Grant task monitoring to admin role
GRANT MONITOR ON ALL TASKS IN DATABASE IDENTIFIER(&database_name) TO ROLE IDENTIFIER(&admin_role_name);
GRANT OPERATE ON ALL TASKS IN DATABASE IDENTIFIER(&database_name) TO ROLE IDENTIFIER(&admin_role_name);

-- Grant procedure execution
GRANT USAGE ON PROCEDURE smdh_tenant_${tenant_id}.analytics.sp_resume_all_tasks() TO ROLE IDENTIFIER(&admin_role_name);
GRANT USAGE ON PROCEDURE smdh_tenant_${tenant_id}.analytics.sp_suspend_all_tasks() TO ROLE IDENTIFIER(&admin_role_name);

SELECT 'Granted task permissions' AS result;

-- ============================================================================
-- 12. Verification
-- ============================================================================

SELECT '12. Verifying Task Creation...' AS step;

-- Show all tasks
USE DATABASE IDENTIFIER(&database_name);
SHOW TASKS;

-- Check task status
SELECT * FROM analytics.v_task_status;

-- Check recent task history (if any)
SELECT * FROM analytics.v_task_history LIMIT 10;

-- ============================================================================
-- 13. Summary
-- ============================================================================

SELECT '╔════════════════════════════════════════════════════════════════╗' AS summary
UNION ALL SELECT '║  Tenant Tasks Creation Complete                            ║'
UNION ALL SELECT '╚════════════════════════════════════════════════════════════╝'
UNION ALL SELECT ''
UNION ALL SELECT 'Created Tasks:'
UNION ALL SELECT ''
UNION ALL SELECT 'Data Processing Pipeline:'
UNION ALL SELECT '  ✓ task_normalize_sensor_readings (1 min, stream-triggered)'
UNION ALL SELECT '  ✓ task_process_device_status (2 min, stream-triggered)'
UNION ALL SELECT '  ✓ task_aggregate_hourly (5 min, after normalization)'
UNION ALL SELECT '  ✓ task_aggregate_daily (daily at 01:00 UTC)'
UNION ALL SELECT '  ✓ task_update_device_registry (10 min)'
UNION ALL SELECT ''
UNION ALL SELECT 'Task Features:'
UNION ALL SELECT '  • Stream-driven execution (only runs when data available)'
UNION ALL SELECT '  • Task dependencies (hourly agg depends on normalization)'
UNION ALL SELECT '  • Auto-scaling warehouses'
UNION ALL SELECT '  • Error handling and logging'
UNION ALL SELECT '  • Incremental processing via streams'
UNION ALL SELECT ''
UNION ALL SELECT 'Management Objects:'
UNION ALL SELECT '  ✓ v_task_status (view)'
UNION ALL SELECT '  ✓ v_task_history (view)'
UNION ALL SELECT '  ✓ sp_resume_all_tasks (procedure)'
UNION ALL SELECT '  ✓ sp_suspend_all_tasks (procedure)'
UNION ALL SELECT ''
UNION ALL SELECT 'Task Status: All tasks RESUMED and running'
UNION ALL SELECT ''
UNION ALL SELECT 'Monitoring:'
UNION ALL SELECT '  • Task status: SELECT * FROM analytics.v_task_status;'
UNION ALL SELECT '  • Task history: SELECT * FROM analytics.v_task_history;'
UNION ALL SELECT '  • Suspend all: CALL analytics.sp_suspend_all_tasks();'
UNION ALL SELECT '  • Resume all: CALL analytics.sp_resume_all_tasks();'
UNION ALL SELECT ''
UNION ALL SELECT 'Next Steps:'
UNION ALL SELECT '  1. Run 15_create_dynamic_tables.sql for real-time aggregations'
UNION ALL SELECT '  2. Monitor task execution in analytics.v_task_history'
UNION ALL SELECT '  3. Test data flow by sending MQTT message to IoT Core'
UNION ALL SELECT '  4. Verify data appears in aggregated tables within minutes'
UNION ALL SELECT '============================================================';
