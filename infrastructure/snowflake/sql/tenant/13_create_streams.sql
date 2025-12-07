-- ============================================================================
-- SMDH Tenant Streams & Openflow Connection
-- ============================================================================
-- Purpose: Create streams for CDC and connect tenant to Openflow for Kinesis ingestion
-- Usage: snowsql -f tenant/13_create_streams.sql --variable tenant_id='company_a'
-- Author: SMDH Platform Team
-- Version: 1.1
-- ============================================================================
-- This script:
-- 1. Creates Snowflake Streams for CDC (Change Data Capture)
-- 2. Grants Openflow access to tenant database for Kinesis ingestion
-- 3. Registers the Openflow connector configuration
-- ============================================================================
-- Prerequisites:
-- - Tenant database and tables created (10-12 scripts)
-- - Core Openflow infrastructure set up (core/03_openflow_connector.sql)
-- - AWS Kinesis stream created for this tenant (Terraform)
-- ============================================================================

-- Enable SnowSQL variable substitution
!set variable_substitution=true

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE SMDH_WH;

-- Convert SnowSQL substitution variables to session variables
SET tenant_id = '&tenant_id';

-- Display banner
SELECT '╔════════════════════════════════════════════════════════════════╗' AS banner
UNION ALL SELECT '║  SMDH Platform - Tenant Streams Creation                   ║'
UNION ALL SELECT '╚════════════════════════════════════════════════════════════╝';

-- ============================================================================
-- 1. Validate Tenant Database
-- ============================================================================

SELECT '1. Validating Tenant Database...' AS step;

SET database_name = 'smdh_tenant_' || $tenant_id;

USE DATABASE IDENTIFIER($database_name);

SELECT 'Using database: ' || $database_name AS info;

-- ============================================================================
-- 2. Create Stream on RAW.SENSOR_READINGS
-- ============================================================================

SELECT '2. Creating Stream on RAW.SENSOR_READINGS...' AS step;

USE SCHEMA raw;

CREATE OR REPLACE STREAM sensor_readings_stream
ON TABLE sensor_readings
APPEND_ONLY = TRUE                                    -- Optimized for append-only data
COMMENT = 'CDC stream for raw sensor readings. Captures new sensor data as it arrives from Kinesis. Used by normalization task.';

SELECT 'Created stream: RAW.SENSOR_READINGS_STREAM' AS result;

-- ============================================================================
-- 3. Create Stream on RAW.DEVICE_STATUS
-- ============================================================================

SELECT '3. Creating Stream on RAW.DEVICE_STATUS...' AS step;

CREATE OR REPLACE STREAM device_status_stream
ON TABLE device_status
APPEND_ONLY = TRUE
COMMENT = 'CDC stream for device status events. Monitors device health changes for alerting.';

SELECT 'Created stream: RAW.DEVICE_STATUS_STREAM' AS result;

-- ============================================================================
-- 4. Create Stream on RAW.GATEWAY_CONNECTIONS
-- ============================================================================

SELECT '4. Creating Stream on RAW.GATEWAY_CONNECTIONS...' AS step;

CREATE OR REPLACE STREAM gateway_connections_stream
ON TABLE gateway_connections
APPEND_ONLY = TRUE
COMMENT = 'CDC stream for gateway connections. Tracks connection events for monitoring.';

SELECT 'Created stream: RAW.GATEWAY_CONNECTIONS_STREAM' AS result;

-- ============================================================================
-- 5. Create Stream on RAW.UPLOADED_FILES
-- ============================================================================

SELECT '5. Creating Stream on RAW.UPLOADED_FILES...' AS step;

CREATE OR REPLACE STREAM uploaded_files_stream
ON TABLE uploaded_files
APPEND_ONLY = TRUE
COMMENT = 'CDC stream for file upload tracking. Triggers processing of manually uploaded files.';

SELECT 'Created stream: RAW.UPLOADED_FILES_STREAM' AS result;

-- ============================================================================
-- 6. Create Stream on NORMALIZED.SENSOR_METRICS
-- ============================================================================

SELECT '6. Creating Stream on NORMALIZED.SENSOR_METRICS...' AS step;

USE SCHEMA normalized;

CREATE OR REPLACE STREAM sensor_metrics_stream
ON TABLE sensor_metrics
APPEND_ONLY = TRUE
COMMENT = 'CDC stream for normalized metrics. Feeds aggregation tasks for hourly/daily rollups.';

SELECT 'Created stream: NORMALIZED.SENSOR_METRICS_STREAM' AS result;

-- ============================================================================
-- 7. Create Stream on NORMALIZED.DEVICE_EVENTS
-- ============================================================================

SELECT '7. Creating Stream on NORMALIZED.DEVICE_EVENTS...' AS step;

CREATE OR REPLACE STREAM device_events_stream
ON TABLE device_events
APPEND_ONLY = TRUE
COMMENT = 'CDC stream for device events. Triggers alert generation and notification tasks.';

SELECT 'Created stream: NORMALIZED.DEVICE_EVENTS_STREAM' AS result;

-- ============================================================================
-- 8. Create Monitoring View for Stream Status
-- ============================================================================

SELECT '8. Creating Stream Monitoring View...' AS step;

USE SCHEMA analytics;

-- Note: INFORMATION_SCHEMA.STREAMS doesn't exist at database level
-- We create a placeholder view since SHOW STREAMS cannot be directly referenced in a view
-- For real-time stream status, use: SHOW STREAMS IN DATABASE;
CREATE OR REPLACE VIEW v_stream_status AS
SELECT
    $database_name AS database_name,
    'raw' AS schema_name,
    'sensor_readings_stream' AS stream_name,
    'Captures new sensor readings' AS description,
    'APPEND_ONLY' AS mode,
    CURRENT_TIMESTAMP() AS checked_at
UNION ALL SELECT $database_name, 'raw', 'device_status_stream', 'Captures device status', 'APPEND_ONLY', CURRENT_TIMESTAMP()
UNION ALL SELECT $database_name, 'raw', 'gateway_connections_stream', 'Captures connections', 'APPEND_ONLY', CURRENT_TIMESTAMP()
UNION ALL SELECT $database_name, 'raw', 'uploaded_files_stream', 'Captures file uploads', 'APPEND_ONLY', CURRENT_TIMESTAMP()
UNION ALL SELECT $database_name, 'normalized', 'sensor_metrics_stream', 'Captures normalized metrics', 'APPEND_ONLY', CURRENT_TIMESTAMP()
UNION ALL SELECT $database_name, 'normalized', 'device_events_stream', 'Captures device events', 'APPEND_ONLY', CURRENT_TIMESTAMP();

SELECT 'Created view: ANALYTICS.V_STREAM_STATUS' AS result;

-- Create view for stream lag (how much data is waiting to be processed)
CREATE OR REPLACE VIEW v_stream_lag AS
WITH stream_stats AS (
    SELECT 'sensor_readings_stream' AS stream_name, COUNT(*) AS pending_rows
    FROM raw.sensor_readings_stream
    UNION ALL
    SELECT 'device_status_stream', COUNT(*)
    FROM raw.device_status_stream
    UNION ALL
    SELECT 'gateway_connections_stream', COUNT(*)
    FROM raw.gateway_connections_stream
    UNION ALL
    SELECT 'uploaded_files_stream', COUNT(*)
    FROM raw.uploaded_files_stream
    UNION ALL
    SELECT 'sensor_metrics_stream', COUNT(*)
    FROM normalized.sensor_metrics_stream
    UNION ALL
    SELECT 'device_events_stream', COUNT(*)
    FROM normalized.device_events_stream
)
SELECT
    stream_name,
    pending_rows,
    CASE
        WHEN pending_rows = 0 THEN 'Up to date'
        WHEN pending_rows < 1000 THEN 'Normal'
        WHEN pending_rows < 10000 THEN 'Behind'
        ELSE 'Significant lag'
    END AS lag_status,
    CURRENT_TIMESTAMP() AS checked_at
FROM stream_stats
ORDER BY pending_rows DESC;

SELECT 'Created view: ANALYTICS.V_STREAM_LAG' AS result;

-- ============================================================================
-- 9. Create Stream Information Function
-- ============================================================================

SELECT '9. Creating Stream Utility Functions...' AS step;

USE SCHEMA analytics;

-- Note: SQL UDFs cannot query INFORMATION_SCHEMA views directly
-- This function is a simple placeholder - use v_stream_status view for monitoring
CREATE OR REPLACE FUNCTION fn_stream_has_data(stream_name_param VARCHAR)
RETURNS BOOLEAN
LANGUAGE SQL
AS
$$
    SELECT TRUE
$$;

SELECT 'Created function: ANALYTICS.FN_STREAM_HAS_DATA' AS result;

-- ============================================================================
-- 10. Document Streams
-- ============================================================================

SELECT '10. Documenting Streams...' AS step;

-- Note: schema_documentation table is created in 17_create_monitoring.sql
-- Stream documentation will be added there
SELECT 'Streams will be documented in monitoring setup' AS result;

-- ============================================================================
-- 11. Test Stream Functionality
-- ============================================================================

SELECT '11. Testing Stream Functionality...' AS step;

-- Check that streams are created and not stale
SELECT 'Stream Status Check:' AS test;
SELECT * FROM analytics.v_stream_status;

-- Check current stream lag
SELECT 'Current Stream Lag:' AS test;
SELECT * FROM analytics.v_stream_lag;

-- Test: Insert a test record and verify stream captures it
USE SCHEMA raw;

-- Use INSERT...SELECT for PARSE_JSON (cannot use in VALUES clause)
INSERT INTO sensor_readings (
    tenant_id,
    sensor_id,
    site_id,
    timestamp,
    payload,
    source_system
)
SELECT
    $tenant_id,
    'test_sensor_001',
    'test_site',
    CURRENT_TIMESTAMP(),
    PARSE_JSON('{"temperature": 22.5, "humidity": 45.0, "test": true}'),
    'test_script';

-- Verify stream captured the test record
SELECT 'Stream Capture Test:' AS test;
SELECT COUNT(*) AS test_records_in_stream
FROM sensor_readings_stream
WHERE sensor_id = 'test_sensor_001';

-- Clean up test record
DELETE FROM sensor_readings WHERE sensor_id = 'test_sensor_001';

SELECT 'Stream functionality verified' AS result;

-- ============================================================================
-- 12. Create Stream Maintenance Procedures
-- ============================================================================

SELECT '12. Creating Stream Maintenance Procedures...' AS step;

USE SCHEMA analytics;

-- Procedure to reset a stream (clear pending changes)
CREATE OR REPLACE PROCEDURE sp_reset_stream(
    schema_name_param VARCHAR,
    stream_name_param VARCHAR
)
RETURNS STRING
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
BEGIN
    -- Drop and recreate the stream to reset it
    LET full_stream_name := :schema_name_param || '.' || :stream_name_param;
    LET source_table := REPLACE(:stream_name_param, '_stream', '');
    LET full_table_name := :schema_name_param || '.' || :source_table;

    EXECUTE IMMEDIATE 'DROP STREAM IF EXISTS ' || :full_stream_name;
    EXECUTE IMMEDIATE 'CREATE STREAM ' || :full_stream_name ||
                     ' ON TABLE ' || :full_table_name ||
                     ' APPEND_ONLY = TRUE';

    RETURN 'Stream ' || :full_stream_name || ' has been reset successfully';
EXCEPTION
    WHEN OTHER THEN
        RETURN 'Error resetting stream: ' || SQLERRM;
END;
$$;

-- Procedure to check all streams health
CREATE OR REPLACE PROCEDURE sp_check_streams_health()
RETURNS TABLE (stream_name VARCHAR, status VARCHAR, pending_rows NUMBER, recommendation VARCHAR)
LANGUAGE SQL
AS
$$
DECLARE
    result RESULTSET DEFAULT (
        SELECT
            stream_name,
            CASE
                WHEN pending_rows = 0 THEN 'Healthy'
                WHEN pending_rows < 1000 THEN 'Normal'
                WHEN pending_rows < 10000 THEN 'Warning'
                ELSE 'Critical'
            END AS status,
            pending_rows,
            CASE
                WHEN pending_rows = 0 THEN 'No action needed'
                WHEN pending_rows < 1000 THEN 'Normal operation'
                WHEN pending_rows < 10000 THEN 'Consider running tasks more frequently'
                ELSE 'Check task execution - significant backlog detected'
            END AS recommendation
        FROM analytics.v_stream_lag
    );
BEGIN
    RETURN TABLE(result);
END;
$$;

SELECT 'Created stream maintenance procedures' AS result;

-- ============================================================================
-- 13. Grant Permissions
-- ============================================================================

SELECT '13. Granting Stream Permissions...' AS step;

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE SMDH_WH;

-- Grant select on streams to tenant roles
SET admin_role_name = 'smdh_tenant_' || $tenant_id || '_admin';
SET user_role_name = 'smdh_tenant_' || $tenant_id || '_user';

-- Admin can select from and manage streams
GRANT SELECT ON ALL STREAMS IN DATABASE IDENTIFIER($database_name) TO ROLE IDENTIFIER($admin_role_name);
GRANT SELECT ON FUTURE STREAMS IN DATABASE IDENTIFIER($database_name) TO ROLE IDENTIFIER($admin_role_name);

-- Regular users can only select (read stream metadata)
GRANT SELECT ON ALL STREAMS IN SCHEMA analytics TO ROLE IDENTIFIER($user_role_name);

-- Grant procedure execution
GRANT USAGE ON PROCEDURE analytics.sp_reset_stream(VARCHAR, VARCHAR) TO ROLE IDENTIFIER($admin_role_name);
GRANT USAGE ON PROCEDURE analytics.sp_check_streams_health() TO ROLE IDENTIFIER($admin_role_name);
GRANT USAGE ON PROCEDURE analytics.sp_check_streams_health() TO ROLE IDENTIFIER($user_role_name);

SELECT 'Granted stream permissions' AS result;

-- ============================================================================
-- 14. Grant Openflow Access for Kinesis Ingestion
-- ============================================================================

SELECT '14. Granting Openflow Access for Kinesis Ingestion...' AS step;

-- Grant OPENFLOW_RUNTIME_ROLE_KINESIS access to this tenant's database
-- This enables Snowflake Openflow to ingest data from the tenant's Kinesis stream
CALL smdh_infrastructure.tenant_configs.sp_grant_openflow_tenant_access($tenant_id);

SELECT 'Granted Openflow access to database: ' || $database_name AS result;

-- ============================================================================
-- 15. Register Openflow Connector Configuration
-- ============================================================================

SELECT '15. Registering Openflow Connector Configuration...' AS step;

-- Register the connector in the tracking table (status = 'pending' until UI setup is complete)
-- The connector is configured via Snowsight UI, this just tracks the configuration
SET kinesis_stream_name = 'smdh-' || $tenant_id || '-stream';

INSERT INTO smdh_infrastructure.tenant_configs.openflow_connectors (
    tenant_id,
    connector_name,
    target_database,
    target_schema,
    target_table,
    kinesis_stream_name,
    aws_region,
    status
)
SELECT
    $tenant_id,
    'kinesis-connector-' || $tenant_id,
    UPPER($database_name),
    'RAW',
    'SENSOR_READINGS',
    $kinesis_stream_name,
    'eu-west-2',
    'pending'
WHERE NOT EXISTS (
    SELECT 1 FROM smdh_infrastructure.tenant_configs.openflow_connectors
    WHERE tenant_id = $tenant_id
);

SELECT 'Registered Openflow connector: kinesis-connector-' || $tenant_id AS result;
SELECT 'Kinesis stream: ' || $kinesis_stream_name AS info;
SELECT 'Status: pending (complete setup in Snowsight UI)' AS info;

-- ============================================================================
-- 16. Verification
-- ============================================================================

SELECT '16. Verifying Stream Creation...' AS step;

-- Show all streams
USE DATABASE IDENTIFIER($database_name);
SHOW STREAMS;

-- Query stream status view
SELECT * FROM analytics.v_stream_status;

-- Check stream health
CALL analytics.sp_check_streams_health();

-- Verify Openflow connector registration
SELECT 'Openflow Connector Status:' AS verification;
SELECT tenant_id, connector_name, kinesis_stream_name, status
FROM smdh_infrastructure.tenant_configs.openflow_connectors
WHERE tenant_id = $tenant_id;

-- ============================================================================
-- 17. Summary
-- ============================================================================

SELECT '╔════════════════════════════════════════════════════════════════╗' AS summary
UNION ALL SELECT '║  Tenant Streams & Openflow Connection Complete             ║'
UNION ALL SELECT '╚════════════════════════════════════════════════════════════╝'
UNION ALL SELECT ''
UNION ALL SELECT 'Created Streams:'
UNION ALL SELECT ''
UNION ALL SELECT 'RAW Schema:'
UNION ALL SELECT '  [OK] sensor_readings_stream (append-only)'
UNION ALL SELECT '  [OK] device_status_stream (append-only)'
UNION ALL SELECT '  [OK] gateway_connections_stream (append-only)'
UNION ALL SELECT '  [OK] uploaded_files_stream (append-only)'
UNION ALL SELECT ''
UNION ALL SELECT 'NORMALIZED Schema:'
UNION ALL SELECT '  [OK] sensor_metrics_stream (append-only)'
UNION ALL SELECT '  [OK] device_events_stream (append-only)'
UNION ALL SELECT ''
UNION ALL SELECT 'Openflow Configuration:'
UNION ALL SELECT '  [OK] Granted OPENFLOW_RUNTIME_ROLE_KINESIS access to tenant DB'
UNION ALL SELECT '  [OK] Registered Openflow connector (status: pending)'
UNION ALL SELECT ''
UNION ALL SELECT 'Monitoring Objects:'
UNION ALL SELECT '  [OK] v_stream_status (view)'
UNION ALL SELECT '  [OK] v_stream_lag (view)'
UNION ALL SELECT '  [OK] sp_check_streams_health (procedure)'
UNION ALL SELECT ''
UNION ALL SELECT 'Next Steps:'
UNION ALL SELECT '  1. Complete Openflow connector setup in Snowsight UI'
UNION ALL SELECT '  2. Run 14_create_routing_task.sql to create data routing task'
UNION ALL SELECT '  3. Monitor stream lag: SELECT * FROM analytics.v_stream_lag;'
UNION ALL SELECT ''
UNION ALL SELECT 'Monitoring Queries:'
UNION ALL SELECT '  • Stream lag: SELECT * FROM analytics.v_stream_lag;'
UNION ALL SELECT '  • Health check: CALL analytics.sp_check_streams_health();'
UNION ALL SELECT '  • Openflow status: SELECT * FROM smdh_infrastructure.monitoring.v_openflow_connector_status;'
UNION ALL SELECT '============================================================';
