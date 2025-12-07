-- ============================================================================
-- SMDH Tenant Data Routing Task
-- ============================================================================
-- Purpose: Route data from Openflow landing table to typed sensor tables
-- Usage: snowsql -f tenant/14_create_routing_task.sql --variable tenant_id='test_tenant'
-- Author: SMDH Platform Team
-- Version: 1.1
-- Updated: 6 December 2025 - Fixed column mappings for Openflow landing table
-- ============================================================================
-- This script creates:
-- 1. Stream on the Openflow landing table to capture new records
-- 2. Task to route records based on message type/sensor type
-- 3. Stored procedure for manual routing (backfill)
-- ============================================================================
-- Data Flow:
--   Kinesis → Openflow → RAW."SMDH-{TENANT}-STREAM" (landing table)
--                              ↓ (Stream + Task)
--                        ├── RAW.SENSOR_READINGS (general sensor data)
--                        ├── RAW.ENVIRONMENTAL_SENSOR_READINGS
--                        ├── RAW.VIBRATION_SENSOR_READINGS
--                        ├── RAW.CLAMP_SENSOR_READINGS
--                        └── RAW.DEVICE_STATUS
-- ============================================================================

-- Enable SnowSQL variable substitution
!set variable_substitution=true

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE SMDH_WH;

-- Convert SnowSQL substitution variables to session variables
SET tenant_id = '&tenant_id';

-- Display banner
SELECT '╔════════════════════════════════════════════════════════════════╗' AS banner
UNION ALL SELECT '║  SMDH Platform - Data Routing Task Creation                  ║'
UNION ALL SELECT '╚════════════════════════════════════════════════════════════════╝';

-- ============================================================================
-- 1. Setup Database Context
-- ============================================================================

SELECT '1. Setting up database context...' AS step;

SET database_name = 'SMDH_TENANT_' || UPPER($tenant_id);
SET landing_table_name = 'SMDH-' || UPPER($tenant_id) || '-STREAM';
SET stream_name = 'OPENFLOW_LANDING_STREAM';

USE DATABASE IDENTIFIER($database_name);
USE SCHEMA RAW;

SELECT 'Database: ' || $database_name AS info;
SELECT 'Landing table: ' || $landing_table_name AS info;

-- ============================================================================
-- 2. Create Stream on Landing Table
-- ============================================================================

SELECT '2. Creating stream on Openflow landing table...' AS step;

-- Create stream to capture new records from Openflow landing table
-- Using EXECUTE IMMEDIATE because table name has special characters (hyphens)
SET create_stream_sql = 'CREATE OR REPLACE STREAM OPENFLOW_LANDING_STREAM ON TABLE "' || $landing_table_name || '" APPEND_ONLY = TRUE COMMENT = ''Stream for routing Openflow data to typed sensor tables''';
EXECUTE IMMEDIATE $create_stream_sql;

SELECT 'Created stream: ' || $stream_name AS result;

-- ============================================================================
-- 3. Create Routing Stored Procedure
-- ============================================================================

SELECT '3. Creating routing stored procedure...' AS step;

CREATE OR REPLACE PROCEDURE sp_route_sensor_data()
RETURNS STRING
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    rows_processed INTEGER := 0;
    rows_sensor_readings INTEGER := 0;
    rows_environmental INTEGER := 0;
    rows_vibration INTEGER := 0;
    rows_clamp INTEGER := 0;
    rows_device_status INTEGER := 0;
BEGIN
    -- IMPORTANT: Streams can only be consumed once per transaction.
    -- First, materialize stream data into a temp table for multi-target routing.
    CREATE OR REPLACE TEMPORARY TABLE _routing_batch AS
    SELECT * FROM OPENFLOW_LANDING_STREAM;

    -- Route ALL records to SENSOR_READINGS (master table with full payload)
    -- This ensures no data is lost regardless of sensor type
    INSERT INTO sensor_readings (
        tenant_id,
        sensor_id,
        site_id,
        device_id,
        timestamp,
        ingestion_timestamp,
        iot_timestamp,
        payload,
        source_system,
        message_id
    )
    SELECT
        TENANT_ID,
        COALESCE(DEVICEEUI, 'unknown') AS sensor_id,
        SITE_ID,
        DEVICE_ID,
        COALESCE(
            TRY_TO_TIMESTAMP_NTZ(TIME),
            CURRENT_TIMESTAMP()
        ) AS timestamp,
        CURRENT_TIMESTAMP() AS ingestion_timestamp,
        -- IOT_TIMESTAMP is milliseconds epoch - use TO_TIMESTAMP with scale 3
        CASE WHEN IOT_TIMESTAMP IS NOT NULL
             THEN TO_TIMESTAMP_NTZ(IOT_TIMESTAMP, 3)
             ELSE NULL END AS iot_timestamp,
        OBJECT_CONSTRUCT(
            'applicationId', APPLICATIONID,
            'deviceEUI', DEVICEEUI,
            'deviceName', DEVICENAME,
            'fPort', FPORT,
            'fCntUp', FCNTUP,
            'adr', ADR,
            'confirmedUplink', CONFIRMEDUPLINK,
            'data', DATA,
            'rx', RX
        ) AS payload,
        'openflow_kinesis' AS source_system,
        KINESISMETADATA:sequenceNumber::VARCHAR AS message_id
    FROM _routing_batch
    WHERE TENANT_ID IS NOT NULL;

    rows_sensor_readings := SQLROWCOUNT;

    -- Route to ENVIRONMENTAL_SENSOR_READINGS
    -- Schema: READING_ID(auto), TENANT_ID, ZONE_ID, SENSOR_ID, SITE_ID, TIMESTAMP,
    --         INGESTION_TIMESTAMP(auto), TEMPERATURE, HUMIDITY, CO2_PPM, VOC_INDEX,
    --         PARTICULATES_PM25, NOISE_DB, LIGHT_LUX, PRESSURE_HPA, RAW_PAYLOAD
    INSERT INTO environmental_sensor_readings (
        TENANT_ID, ZONE_ID, SENSOR_ID, SITE_ID, TIMESTAMP,
        TEMPERATURE, HUMIDITY, CO2_PPM, VOC_INDEX,
        PARTICULATES_PM25, NOISE_DB, LIGHT_LUX, PRESSURE_HPA, RAW_PAYLOAD
    )
    SELECT
        TENANT_ID,
        'ZONE_FLOOR_001' AS zone_id,  -- Default zone if not in data
        COALESCE(DEVICEEUI, 'unknown') AS sensor_id,
        SITE_ID,
        COALESCE(
            TRY_TO_TIMESTAMP_NTZ(TIME),
            CURRENT_TIMESTAMP()
        ) AS timestamp,
        DATA:temperature::FLOAT AS temperature,
        DATA:humidity::FLOAT AS humidity,
        DATA:co2::FLOAT AS co2_ppm,
        DATA:tvoc::NUMBER AS voc_index,
        DATA:pm25::FLOAT AS particulates_pm25,
        DATA:noise::FLOAT AS noise_db,
        DATA:light::FLOAT AS light_lux,
        DATA:pressure::FLOAT AS pressure_hpa,
        OBJECT_CONSTRUCT(*) AS raw_payload
    FROM _routing_batch
    WHERE DATA:temperature IS NOT NULL
      AND (DEVICENAME LIKE ANY ('%AM308%', '%EM300%', '%Environmental%', '%TH%', '%Temp%')
           OR DATA:sensorType IS NULL);

    rows_environmental := SQLROWCOUNT;

    -- Route to VIBRATION_SENSOR_READINGS
    -- Schema: READING_ID(auto), TENANT_ID, MACHINE_ID, SENSOR_ID, SITE_ID, TIMESTAMP,
    --         INGESTION_TIMESTAMP(auto), VIBRATION_X/Y/Z, VIBRATION_RMS, TEMPERATURE,
    --         DOMINANT_FREQUENCY, RAW_PAYLOAD
    INSERT INTO vibration_sensor_readings (
        TENANT_ID, MACHINE_ID, SENSOR_ID, SITE_ID, TIMESTAMP,
        VIBRATION_X, VIBRATION_Y, VIBRATION_Z, VIBRATION_RMS,
        TEMPERATURE, DOMINANT_FREQUENCY, RAW_PAYLOAD
    )
    SELECT
        TENANT_ID,
        COALESCE(REGEXP_SUBSTR(DEVICENAME, 'Vibration-(.+)', 1, 1, 'e'), 'UNKNOWN') AS machine_id,
        COALESCE(DEVICEEUI, 'unknown') AS sensor_id,
        SITE_ID,
        COALESCE(
            TRY_TO_TIMESTAMP_NTZ(TIME),
            CURRENT_TIMESTAMP()
        ) AS timestamp,
        DATA:vibration_x::FLOAT AS vibration_x,
        DATA:vibration_y::FLOAT AS vibration_y,
        DATA:vibration_z::FLOAT AS vibration_z,
        DATA:vibration_rms::FLOAT AS vibration_rms,
        DATA:temperature::FLOAT AS temperature,
        DATA:dominant_frequency::FLOAT AS dominant_frequency,
        OBJECT_CONSTRUCT(*) AS raw_payload
    FROM _routing_batch
    WHERE DATA:sensorType::VARCHAR = 'vibration'
       OR DEVICENAME LIKE '%Vibration%';

    rows_vibration := SQLROWCOUNT;

    -- Route to CLAMP_SENSOR_READINGS
    -- Schema: READING_ID(auto), TENANT_ID, MACHINE_ID, SENSOR_ID, SITE_ID, TIMESTAMP,
    --         INGESTION_TIMESTAMP(auto), CURRENT_PHASE_A/B/C, CURRENT_RMS,
    --         VOLTAGE_PHASE_A/B/C, POWER_FACTOR, FREQUENCY, RAW_PAYLOAD
    INSERT INTO clamp_sensor_readings (
        TENANT_ID, MACHINE_ID, SENSOR_ID, SITE_ID, TIMESTAMP,
        CURRENT_PHASE_A, CURRENT_PHASE_B, CURRENT_PHASE_C, CURRENT_RMS,
        POWER_FACTOR, FREQUENCY, RAW_PAYLOAD
    )
    SELECT
        TENANT_ID,
        COALESCE(REGEXP_SUBSTR(DEVICENAME, 'CT-Clamp-(.+)', 1, 1, 'e'), 'UNKNOWN') AS machine_id,
        COALESCE(DEVICEEUI, 'unknown') AS sensor_id,
        SITE_ID,
        COALESCE(
            TRY_TO_TIMESTAMP_NTZ(TIME),
            CURRENT_TIMESTAMP()
        ) AS timestamp,
        DATA:current_phase_a::FLOAT AS current_phase_a,
        DATA:current_phase_b::FLOAT AS current_phase_b,
        DATA:current_phase_c::FLOAT AS current_phase_c,
        DATA:current_rms::FLOAT AS current_rms,
        DATA:power_factor::FLOAT AS power_factor,
        DATA:frequency::FLOAT AS frequency,
        OBJECT_CONSTRUCT(*) AS raw_payload
    FROM _routing_batch
    WHERE DATA:sensorType::VARCHAR = 'clamp_current'
       OR DEVICENAME LIKE '%CT-Clamp%';

    rows_clamp := SQLROWCOUNT;

    -- Route to DEVICE_STATUS
    -- Schema: EVENT_ID(auto), TENANT_ID, DEVICE_ID, SITE_ID, TIMESTAMP,
    --         STATUS, BATTERY_LEVEL, SIGNAL_STRENGTH, TEMPERATURE,
    --         FIRMWARE_VERSION, PAYLOAD, INGESTION_TIMESTAMP(auto)
    INSERT INTO device_status (
        TENANT_ID, DEVICE_ID, SITE_ID, TIMESTAMP,
        STATUS, BATTERY_LEVEL, SIGNAL_STRENGTH, FIRMWARE_VERSION, PAYLOAD
    )
    SELECT
        TENANT_ID,
        COALESCE(DEVICEEUI, DEVICE_ID, 'unknown') AS device_id,
        SITE_ID,
        COALESCE(
            TRY_TO_TIMESTAMP_NTZ(TIME),
            CURRENT_TIMESTAMP()
        ) AS timestamp,
        CASE
            WHEN DATA:status::VARCHAR IS NOT NULL THEN DATA:status::VARCHAR
            WHEN DATA:battery::NUMBER > 20 THEN 'online'
            WHEN DATA:battery::NUMBER > 0 THEN 'low_battery'
            ELSE 'unknown'
        END AS status,
        DATA:battery::FLOAT AS battery_level,
        COALESCE(DATA:rssi::FLOAT, RX:rssi::FLOAT) AS signal_strength,
        DATA:firmware::VARCHAR AS firmware_version,
        OBJECT_CONSTRUCT(*) AS payload
    FROM _routing_batch
    WHERE DATA:sensorType::VARCHAR = 'device_status'
       OR DEVICENAME LIKE '%Status%';

    rows_device_status := SQLROWCOUNT;

    -- Clean up temp table
    DROP TABLE IF EXISTS _routing_batch;

    rows_processed := rows_sensor_readings;

    RETURN 'Routed ' || rows_processed || ' total rows: ' ||
           rows_sensor_readings || ' to sensor_readings, ' ||
           rows_environmental || ' to environmental, ' ||
           rows_vibration || ' to vibration, ' ||
           rows_clamp || ' to clamp, ' ||
           rows_device_status || ' to device_status';
END;
$$;

SELECT 'Created procedure: sp_route_sensor_data' AS result;

-- ============================================================================
-- 4. Create Scheduled Task
-- ============================================================================

SELECT '4. Creating scheduled routing task...' AS step;

-- Task runs every minute to route new data
CREATE OR REPLACE TASK task_route_sensor_data
    WAREHOUSE = SMDH_WH
    SCHEDULE = '1 MINUTE'
    COMMENT = 'Routes data from Openflow landing table to typed sensor tables'
    WHEN SYSTEM$STREAM_HAS_DATA('OPENFLOW_LANDING_STREAM')
AS
    CALL sp_route_sensor_data();

SELECT 'Created task: task_route_sensor_data' AS result;

-- ============================================================================
-- 5. Create Backfill Procedure
-- ============================================================================

SELECT '5. Creating backfill procedure...' AS step;

-- Procedure to backfill existing data from landing table to ALL typed tables
CREATE OR REPLACE PROCEDURE sp_backfill_from_landing()
RETURNS STRING
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    rows_sensor_readings INTEGER := 0;
    rows_environmental INTEGER := 0;
    rows_vibration INTEGER := 0;
    rows_clamp INTEGER := 0;
    rows_device_status INTEGER := 0;
    landing_table VARCHAR;
BEGIN
    -- Get landing table name
    landing_table := 'SMDH-' || UPPER(CURRENT_DATABASE()) || '-STREAM';
    landing_table := REPLACE(landing_table, 'SMDH_TENANT_', '');

    -- Materialize landing table data into temp table for multi-target routing
    EXECUTE IMMEDIATE 'CREATE OR REPLACE TEMPORARY TABLE _backfill_batch AS SELECT * FROM "' || landing_table || '" WHERE TENANT_ID IS NOT NULL';

    -- Route ALL records to SENSOR_READINGS (master table)
    INSERT INTO sensor_readings (tenant_id, sensor_id, site_id, device_id, timestamp,
        ingestion_timestamp, iot_timestamp, payload, source_system, message_id)
    SELECT
        TENANT_ID,
        COALESCE(DEVICEEUI, 'unknown') AS sensor_id,
        SITE_ID,
        DEVICE_ID,
        COALESCE(TRY_TO_TIMESTAMP_NTZ(TIME), CURRENT_TIMESTAMP()) AS timestamp,
        CURRENT_TIMESTAMP() AS ingestion_timestamp,
        CASE WHEN IOT_TIMESTAMP IS NOT NULL THEN TO_TIMESTAMP_NTZ(IOT_TIMESTAMP, 3) ELSE NULL END AS iot_timestamp,
        OBJECT_CONSTRUCT('applicationId', APPLICATIONID, 'deviceEUI', DEVICEEUI, 'deviceName', DEVICENAME, 'fPort', FPORT, 'data', DATA, 'rx', RX) AS payload,
        'openflow_kinesis_backfill' AS source_system,
        KINESISMETADATA:sequenceNumber::VARCHAR AS message_id
    FROM _backfill_batch;
    rows_sensor_readings := SQLROWCOUNT;

    -- Route to ENVIRONMENTAL_SENSOR_READINGS
    INSERT INTO environmental_sensor_readings (TENANT_ID, ZONE_ID, SENSOR_ID, SITE_ID, TIMESTAMP,
        TEMPERATURE, HUMIDITY, CO2_PPM, VOC_INDEX, PARTICULATES_PM25, NOISE_DB, LIGHT_LUX, PRESSURE_HPA, RAW_PAYLOAD)
    SELECT
        TENANT_ID, 'ZONE_FLOOR_001' AS zone_id, COALESCE(DEVICEEUI, 'unknown') AS sensor_id, SITE_ID,
        COALESCE(TRY_TO_TIMESTAMP_NTZ(TIME), CURRENT_TIMESTAMP()) AS timestamp,
        DATA:temperature::FLOAT, DATA:humidity::FLOAT, DATA:co2::FLOAT, DATA:tvoc::NUMBER,
        DATA:pm25::FLOAT, DATA:noise::FLOAT, DATA:light::FLOAT, DATA:pressure::FLOAT,
        OBJECT_CONSTRUCT(*) AS raw_payload
    FROM _backfill_batch
    WHERE DATA:temperature IS NOT NULL
      AND (DEVICENAME LIKE ANY ('%AM308%', '%EM300%', '%Environmental%', '%TH%', '%Temp%') OR DATA:sensorType IS NULL);
    rows_environmental := SQLROWCOUNT;

    -- Route to VIBRATION_SENSOR_READINGS
    INSERT INTO vibration_sensor_readings (TENANT_ID, MACHINE_ID, SENSOR_ID, SITE_ID, TIMESTAMP,
        VIBRATION_X, VIBRATION_Y, VIBRATION_Z, VIBRATION_RMS, TEMPERATURE, DOMINANT_FREQUENCY, RAW_PAYLOAD)
    SELECT
        TENANT_ID, COALESCE(REGEXP_SUBSTR(DEVICENAME, 'Vibration-(.+)', 1, 1, 'e'), 'UNKNOWN') AS machine_id,
        COALESCE(DEVICEEUI, 'unknown') AS sensor_id, SITE_ID,
        COALESCE(TRY_TO_TIMESTAMP_NTZ(TIME), CURRENT_TIMESTAMP()) AS timestamp,
        DATA:vibration_x::FLOAT, DATA:vibration_y::FLOAT, DATA:vibration_z::FLOAT,
        DATA:vibration_rms::FLOAT, DATA:temperature::FLOAT, DATA:dominant_frequency::FLOAT,
        OBJECT_CONSTRUCT(*) AS raw_payload
    FROM _backfill_batch
    WHERE DATA:sensorType::VARCHAR = 'vibration' OR DEVICENAME LIKE '%Vibration%';
    rows_vibration := SQLROWCOUNT;

    -- Route to CLAMP_SENSOR_READINGS
    INSERT INTO clamp_sensor_readings (TENANT_ID, MACHINE_ID, SENSOR_ID, SITE_ID, TIMESTAMP,
        CURRENT_PHASE_A, CURRENT_PHASE_B, CURRENT_PHASE_C, CURRENT_RMS, POWER_FACTOR, FREQUENCY, RAW_PAYLOAD)
    SELECT
        TENANT_ID, COALESCE(REGEXP_SUBSTR(DEVICENAME, 'CT-Clamp-(.+)', 1, 1, 'e'), 'UNKNOWN') AS machine_id,
        COALESCE(DEVICEEUI, 'unknown') AS sensor_id, SITE_ID,
        COALESCE(TRY_TO_TIMESTAMP_NTZ(TIME), CURRENT_TIMESTAMP()) AS timestamp,
        DATA:current_phase_a::FLOAT, DATA:current_phase_b::FLOAT, DATA:current_phase_c::FLOAT,
        DATA:current_rms::FLOAT, DATA:power_factor::FLOAT, DATA:frequency::FLOAT,
        OBJECT_CONSTRUCT(*) AS raw_payload
    FROM _backfill_batch
    WHERE DATA:sensorType::VARCHAR = 'clamp_current' OR DEVICENAME LIKE '%CT-Clamp%';
    rows_clamp := SQLROWCOUNT;

    -- Route to DEVICE_STATUS
    INSERT INTO device_status (TENANT_ID, DEVICE_ID, SITE_ID, TIMESTAMP,
        STATUS, BATTERY_LEVEL, SIGNAL_STRENGTH, FIRMWARE_VERSION, PAYLOAD)
    SELECT
        TENANT_ID, COALESCE(DEVICEEUI, DEVICE_ID, 'unknown') AS device_id, SITE_ID,
        COALESCE(TRY_TO_TIMESTAMP_NTZ(TIME), CURRENT_TIMESTAMP()) AS timestamp,
        CASE WHEN DATA:status::VARCHAR IS NOT NULL THEN DATA:status::VARCHAR
             WHEN DATA:battery::NUMBER > 20 THEN 'online'
             WHEN DATA:battery::NUMBER > 0 THEN 'low_battery'
             ELSE 'unknown' END AS status,
        DATA:battery::FLOAT, COALESCE(DATA:rssi::FLOAT, RX:rssi::FLOAT),
        DATA:firmware::VARCHAR, OBJECT_CONSTRUCT(*) AS payload
    FROM _backfill_batch
    WHERE DATA:sensorType::VARCHAR = 'device_status' OR DEVICENAME LIKE '%Status%';
    rows_device_status := SQLROWCOUNT;

    -- Clean up temp table
    DROP TABLE IF EXISTS _backfill_batch;

    RETURN 'Backfilled ' || rows_sensor_readings || ' to sensor_readings, ' ||
           rows_environmental || ' to environmental, ' ||
           rows_vibration || ' to vibration, ' ||
           rows_clamp || ' to clamp, ' ||
           rows_device_status || ' to device_status';
END;
$$;

SELECT 'Created procedure: sp_backfill_from_landing' AS result;

-- ============================================================================
-- 6. Grant Permissions
-- ============================================================================

SELECT '6. Granting permissions...' AS step;

SET admin_role = 'SMDH_TENANT_' || UPPER($tenant_id) || '_ADMIN';

-- Grant execute on procedures
GRANT USAGE ON PROCEDURE sp_route_sensor_data() TO ROLE IDENTIFIER($admin_role);
GRANT USAGE ON PROCEDURE sp_backfill_from_landing() TO ROLE IDENTIFIER($admin_role);

-- Grant operate on task
GRANT OPERATE ON TASK task_route_sensor_data TO ROLE IDENTIFIER($admin_role);
GRANT MONITOR ON TASK task_route_sensor_data TO ROLE IDENTIFIER($admin_role);

SELECT 'Permissions granted' AS result;

-- ============================================================================
-- 7. Resume Task
-- ============================================================================

SELECT '7. Resuming routing task...' AS step;

ALTER TASK task_route_sensor_data RESUME;

SELECT 'Task resumed and active' AS result;

-- ============================================================================
-- 8. Backfill Existing Data
-- ============================================================================

SELECT '8. Backfilling existing data from landing table...' AS step;

CALL sp_backfill_from_landing();

-- ============================================================================
-- 9. Verification
-- ============================================================================

SELECT '9. Verifying setup...' AS step;

-- Show stream
SHOW STREAMS LIKE 'OPENFLOW%';

-- Show task
SHOW TASKS LIKE 'TASK_ROUTE%';

-- Check task state
SELECT name, state, schedule, condition
FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY())
WHERE name = 'TASK_ROUTE_SENSOR_DATA'
ORDER BY scheduled_time DESC
LIMIT 5;

-- Check record counts
SELECT 'Landing table' AS source, COUNT(*) AS record_count
FROM IDENTIFIER('"' || $landing_table_name || '"')
UNION ALL
SELECT 'sensor_readings', COUNT(*) FROM sensor_readings
UNION ALL
SELECT 'environmental_sensor_readings', COUNT(*) FROM environmental_sensor_readings
UNION ALL
SELECT 'device_status', COUNT(*) FROM device_status;

-- ============================================================================
-- 10. Summary
-- ============================================================================

SELECT '╔════════════════════════════════════════════════════════════════╗' AS summary
UNION ALL SELECT '║  Data Routing Task Setup Complete                             ║'
UNION ALL SELECT '╚════════════════════════════════════════════════════════════════╝'
UNION ALL SELECT ''
UNION ALL SELECT 'Created Objects:'
UNION ALL SELECT '  [OK] Stream: OPENFLOW_LANDING_STREAM'
UNION ALL SELECT '  [OK] Task: task_route_sensor_data (runs every minute)'
UNION ALL SELECT '  [OK] Procedure: sp_route_sensor_data'
UNION ALL SELECT '  [OK] Procedure: sp_backfill_from_landing'
UNION ALL SELECT ''
UNION ALL SELECT 'Data Flow:'
UNION ALL SELECT '  Openflow Landing Table → Stream → Task → Typed Tables'
UNION ALL SELECT ''
UNION ALL SELECT 'Routing Rules:'
UNION ALL SELECT '  • LoRaWAN sensor data → SENSOR_READINGS'
UNION ALL SELECT '  • AM308/EM300/Temp sensors → ENVIRONMENTAL_SENSOR_READINGS'
UNION ALL SELECT '  • Battery/RSSI data → DEVICE_STATUS'
UNION ALL SELECT ''
UNION ALL SELECT 'Monitoring:'
UNION ALL SELECT '  • SELECT * FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY())'
UNION ALL SELECT '  • SELECT SYSTEM$STREAM_HAS_DATA(''OPENFLOW_LANDING_STREAM'')'
UNION ALL SELECT ''
UNION ALL SELECT 'Manual Operations:'
UNION ALL SELECT '  • CALL sp_route_sensor_data();  -- Manual route'
UNION ALL SELECT '  • CALL sp_backfill_from_landing();  -- Backfill historical'
UNION ALL SELECT '  • ALTER TASK task_route_sensor_data SUSPEND;  -- Pause'
UNION ALL SELECT '  • ALTER TASK task_route_sensor_data RESUME;   -- Resume';
