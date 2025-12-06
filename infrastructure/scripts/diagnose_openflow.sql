-- ============================================================================
-- SMDH Openflow Data Flow Diagnostic
-- ============================================================================
-- Purpose: Diagnose why data from Openflow is not reaching target tables
-- Usage: snowsql -f diagnose_openflow.sql --variable tenant_id='your_tenant'
-- ============================================================================

!set variable_substitution=true
SET tenant_id = '&tenant_id';
SET database_name = 'smdh_tenant_' || $tenant_id;

USE DATABASE IDENTIFIER($database_name);
USE WAREHOUSE SMDH_WH;

SELECT '╔════════════════════════════════════════════════════════════════╗' AS banner
UNION ALL SELECT '║  SMDH Openflow Data Flow Diagnostic                            ║'
UNION ALL SELECT '║  Tenant: ' || $tenant_id || '                                              ║'
UNION ALL SELECT '╚════════════════════════════════════════════════════════════════╝';

-- ============================================================================
-- 1. Check RAW.SENSOR_READINGS (Openflow Landing Table)
-- ============================================================================
SELECT '═══════════════════════════════════════════════════════════════' AS section;
SELECT '1. RAW.SENSOR_READINGS - Openflow Landing Table' AS check;
SELECT '═══════════════════════════════════════════════════════════════' AS section;

-- Count records
SELECT 'Total records in raw.sensor_readings:' AS metric, COUNT(*) AS value
FROM raw.sensor_readings;

-- Recent records
SELECT 'Records in last 24 hours:' AS metric, COUNT(*) AS value
FROM raw.sensor_readings
WHERE ingestion_timestamp >= DATEADD(hour, -24, CURRENT_TIMESTAMP());

-- Check most recent record
SELECT 'Most recent record timestamp:' AS metric,
       MAX(ingestion_timestamp) AS value
FROM raw.sensor_readings;

-- Sample recent records (show structure)
SELECT '--- Sample Recent Records (last 10) ---' AS info;
SELECT
    reading_id,
    tenant_id,
    sensor_id,
    timestamp,
    ingestion_timestamp,
    source_system,
    mqtt_topic,
    LEFT(payload::VARCHAR, 200) AS payload_preview
FROM raw.sensor_readings
ORDER BY ingestion_timestamp DESC
LIMIT 10;

-- ============================================================================
-- 2. Check PAYLOAD Structure (Critical for Openflow)
-- ============================================================================
SELECT '═══════════════════════════════════════════════════════════════' AS section;
SELECT '2. PAYLOAD Structure Analysis' AS check;
SELECT '═══════════════════════════════════════════════════════════════' AS section;

-- Check what keys exist in payload
SELECT '--- Top-Level Payload Keys (most recent 100 records) ---' AS info;
SELECT DISTINCT
    f.key AS payload_key,
    TYPEOF(f.value) AS value_type,
    COUNT(*) AS occurrences
FROM raw.sensor_readings,
LATERAL FLATTEN(input => payload, OUTER => TRUE) f
WHERE ingestion_timestamp >= DATEADD(hour, -24, CURRENT_TIMESTAMP())
GROUP BY f.key, TYPEOF(f.value)
ORDER BY occurrences DESC
LIMIT 20;

-- Check if Kinesis metadata is present
SELECT '--- Checking for Kinesis Metadata in Payload ---' AS info;
SELECT
    CASE WHEN payload:partition_key IS NOT NULL THEN 'YES' ELSE 'NO' END AS has_partition_key,
    CASE WHEN payload:sequence_number IS NOT NULL THEN 'YES' ELSE 'NO' END AS has_sequence_number,
    CASE WHEN payload:approximate_arrival_timestamp IS NOT NULL THEN 'YES' ELSE 'NO' END AS has_arrival_timestamp,
    CASE WHEN payload:data IS NOT NULL THEN 'YES' ELSE 'NO' END AS has_nested_data,
    CASE WHEN payload:deviceId IS NOT NULL THEN 'YES' ELSE 'NO' END AS has_device_id,
    CASE WHEN payload:timestamp IS NOT NULL THEN 'YES' ELSE 'NO' END AS has_timestamp,
    CASE WHEN payload:sensorType IS NOT NULL THEN 'YES' ELSE 'NO' END AS has_sensor_type,
    CASE WHEN payload:measurements IS NOT NULL THEN 'YES' ELSE 'NO' END AS has_measurements
FROM raw.sensor_readings
WHERE ingestion_timestamp >= DATEADD(hour, -24, CURRENT_TIMESTAMP())
LIMIT 1;

-- ============================================================================
-- 3. Check Stream Status
-- ============================================================================
SELECT '═══════════════════════════════════════════════════════════════' AS section;
SELECT '3. Stream Status' AS check;
SELECT '═══════════════════════════════════════════════════════════════' AS section;

SHOW STREAMS IN SCHEMA raw;

-- Check if sensor_readings_stream has data
SELECT '--- Stream Has Data Check ---' AS info;
SELECT
    'raw.sensor_readings_stream' AS stream_name,
    SYSTEM$STREAM_HAS_DATA('raw.sensor_readings_stream') AS has_data;

-- ============================================================================
-- 4. Check Task Status
-- ============================================================================
SELECT '═══════════════════════════════════════════════════════════════' AS section;
SELECT '4. Task Status' AS check;
SELECT '═══════════════════════════════════════════════════════════════' AS section;

SHOW TASKS IN SCHEMA raw;

-- Check task history (recent runs)
SELECT '--- Recent Task Executions ---' AS info;
SELECT
    name AS task_name,
    state,
    scheduled_time,
    completed_time,
    error_code,
    error_message
FROM TABLE(information_schema.task_history(
    scheduled_time_range_start => DATEADD(hour, -24, CURRENT_TIMESTAMP()),
    result_limit => 20
))
ORDER BY scheduled_time DESC;

-- ============================================================================
-- 5. Check Downstream Tables
-- ============================================================================
SELECT '═══════════════════════════════════════════════════════════════' AS section;
SELECT '5. Downstream Table Record Counts' AS check;
SELECT '═══════════════════════════════════════════════════════════════' AS section;

SELECT 'raw.sensor_readings' AS table_name, COUNT(*) AS record_count FROM raw.sensor_readings
UNION ALL
SELECT 'raw.clamp_sensor_readings', COUNT(*) FROM raw.clamp_sensor_readings
UNION ALL
SELECT 'raw.vibration_sensor_readings', COUNT(*) FROM raw.vibration_sensor_readings
UNION ALL
SELECT 'raw.environmental_sensor_readings', COUNT(*) FROM raw.environmental_sensor_readings
UNION ALL
SELECT 'normalized.sensor_metrics', COUNT(*) FROM normalized.sensor_metrics
UNION ALL
SELECT 'normalized.power_metrics', COUNT(*) FROM normalized.power_metrics
UNION ALL
SELECT 'mart.fact_machine_state', COUNT(*) FROM mart.fact_machine_state;

-- ============================================================================
-- 6. Check Openflow Connector Status (Infrastructure DB)
-- ============================================================================
SELECT '═══════════════════════════════════════════════════════════════' AS section;
SELECT '6. Openflow Connector Status (requires SMDH_INFRASTRUCTURE)' AS check;
SELECT '═══════════════════════════════════════════════════════════════' AS section;

-- Note: Run this separately if you have access to SMDH_INFRASTRUCTURE
SELECT '--- Run this in Snowsight to check Openflow status: ---' AS note;
SELECT 'SELECT * FROM TABLE(INFORMATION_SCHEMA.OPENFLOW_INGESTION_HISTORY()) ORDER BY start_time DESC LIMIT 10;' AS query;

-- ============================================================================
-- 7. Diagnose Column Mapping Issues
-- ============================================================================
SELECT '═══════════════════════════════════════════════════════════════' AS section;
SELECT '7. Column Mapping Analysis' AS check;
SELECT '═══════════════════════════════════════════════════════════════' AS section;

-- Check for NULL required columns (indicates mapping failure)
SELECT
    'Records with NULL sensor_id' AS issue,
    COUNT(*) AS count
FROM raw.sensor_readings
WHERE sensor_id IS NULL
UNION ALL
SELECT
    'Records with NULL timestamp',
    COUNT(*)
FROM raw.sensor_readings
WHERE timestamp IS NULL
UNION ALL
SELECT
    'Records with NULL payload',
    COUNT(*)
FROM raw.sensor_readings
WHERE payload IS NULL;

-- Check source_system distribution
SELECT
    source_system,
    COUNT(*) AS record_count,
    MIN(ingestion_timestamp) AS first_seen,
    MAX(ingestion_timestamp) AS last_seen
FROM raw.sensor_readings
GROUP BY source_system;

-- ============================================================================
-- 8. Summary and Recommendations
-- ============================================================================
SELECT '═══════════════════════════════════════════════════════════════' AS section;
SELECT '8. DIAGNOSTIC SUMMARY' AS check;
SELECT '═══════════════════════════════════════════════════════════════' AS section;

SELECT '
POTENTIAL ISSUES TO CHECK:

1. If raw.sensor_readings is EMPTY:
   - Openflow connector may not be running
   - Check Openflow connector status in Snowsight
   - Verify Kinesis stream has data (AWS Console)

2. If raw.sensor_readings has data but downstream tables empty:
   - Stream may not be detecting changes
   - Tasks may be suspended or failing
   - Check task history for errors

3. If payload structure is wrong:
   - Openflow writes entire Kinesis record as payload
   - May need to extract fields: payload:deviceId, payload:timestamp
   - Consider adding a landing table with simpler structure

4. If NULL columns in sensor_readings:
   - Openflow column mapping may be incorrect
   - Table schema expects parsed fields, but Openflow writes raw

RECOMMENDED NEXT STEPS:
   - Run: SELECT * FROM TABLE(INFORMATION_SCHEMA.OPENFLOW_INGESTION_HISTORY());
   - Check Kinesis stream in AWS Console
   - Review Openflow connector configuration in Snowsight
' AS recommendations;
