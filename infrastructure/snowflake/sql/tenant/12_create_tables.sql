-- ============================================================================
-- SMDH Tenant Table Definitions
-- ============================================================================
-- Purpose: Create all data tables for tenant
-- Usage: snowsql -f tenant/12_create_tables.sql --variable tenant_id='company_a'
-- Author: SMDH Platform Team
-- Version: 1.0
-- ============================================================================
-- This script creates:
-- - RAW schema: sensor_readings, gateway_connections, device_status, uploaded_files
-- - NORMALIZED schema: sensor_metrics, device_events, site_metrics
-- - AGGREGATED schema: hourly/daily/monthly aggregations
-- - ANALYTICS schema: dashboard views and KPI tables
-- ============================================================================

-- Enable SnowSQL variable substitution 
!set variable_substitution=true

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE SMDH_WH;

-- Convert SnowSQL substitution variables to session variables
SET tenant_id = '&tenant_id';

-- Display banner
SELECT '╔════════════════════════════════════════════════════════════════╗' AS banner
UNION ALL SELECT '║  SMDH Platform - Tenant Table Creation                     ║'
UNION ALL SELECT '╚════════════════════════════════════════════════════════════╝';

-- ============================================================================
-- 1. Validate Tenant Database
-- ============================================================================

SELECT '1. Validating Tenant Database...' AS step;

SET database_name = 'smdh_tenant_' || $tenant_id;

USE DATABASE IDENTIFIER($database_name);

SELECT 'Using database: ' || $database_name AS info;

-- ============================================================================
-- 2. RAW SCHEMA: Sensor Readings Table
-- ============================================================================

SELECT '2. Creating RAW.SENSOR_READINGS Table...' AS step;

USE SCHEMA raw;

CREATE TABLE IF NOT EXISTS sensor_readings (
    -- Primary identifiers
    reading_id VARCHAR(255) DEFAULT UUID_STRING(),
    tenant_id VARCHAR(100) NOT NULL,  -- Set by ingestion pipeline, not DEFAULT (session vars not allowed)
    sensor_id VARCHAR(255) NOT NULL,
    site_id VARCHAR(100),
    device_id VARCHAR(255),

    -- Timestamps
    timestamp TIMESTAMP_NTZ NOT NULL,                 -- Sensor reading timestamp
    ingestion_timestamp TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),  -- When received by Snowflake
    iot_timestamp TIMESTAMP_NTZ,                      -- IoT Core received timestamp

    -- Data payload
    payload VARIANT NOT NULL,                         -- Raw JSON payload from sensor

    -- Message metadata
    source_system VARCHAR(100),                       -- 'mqtt', 'file_upload', 'api'
    mqtt_topic VARCHAR(500),                          -- Original MQTT topic path
    message_id VARCHAR(255),                          -- Original message ID from IoT Core

    -- Quality indicators
    is_duplicate BOOLEAN DEFAULT FALSE,
    is_valid BOOLEAN DEFAULT TRUE,
    validation_errors VARIANT,

    -- Partitioning and clustering
    PRIMARY KEY (reading_id)

    -- Note: Snowflake does not support CHECK constraints
    -- Tenant isolation enforced at application layer
)
CLUSTER BY (DATE_TRUNC('day', timestamp), sensor_id)
DATA_RETENTION_TIME_IN_DAYS = 7
COMMENT = 'Raw sensor readings from IoT devices via MQTT. Preserves original payload structure for auditability. Clustered by day and sensor for query performance.';

SELECT 'Created table: RAW.SENSOR_READINGS' AS result;

-- ============================================================================
-- 3. RAW SCHEMA: Gateway Connections Table
-- ============================================================================

SELECT '3. Creating RAW.GATEWAY_CONNECTIONS Table...' AS step;

CREATE TABLE IF NOT EXISTS gateway_connections (
    -- Primary identifiers
    connection_id VARCHAR(255) DEFAULT UUID_STRING(),
    tenant_id VARCHAR(100) NOT NULL,  -- Set by ingestion pipeline, not DEFAULT (session vars not allowed)
    gateway_id VARCHAR(255) NOT NULL,
    site_id VARCHAR(100),

    -- Connection details
    connection_time TIMESTAMP_NTZ NOT NULL,
    disconnection_time TIMESTAMP_NTZ,
    connection_duration_seconds NUMBER(20),
    status VARCHAR(50),                               -- 'connected', 'disconnected', 'error'

    -- Connection metadata
    ip_address VARCHAR(50),
    client_id VARCHAR(255),
    protocol_version VARCHAR(50),
    keep_alive_seconds NUMBER(10),

    -- Error handling
    error_code VARCHAR(50),
    error_message VARCHAR(1000),

    -- Ingestion
    ingestion_timestamp TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),

    PRIMARY KEY (connection_id)

    -- Note: Snowflake does not support CHECK constraints
    -- Tenant isolation enforced at application layer
)
CLUSTER BY (DATE_TRUNC('day', connection_time), gateway_id)
DATA_RETENTION_TIME_IN_DAYS = 7
COMMENT = 'Gateway connection tracking and diagnostics. Monitors connection lifecycle and health.';

SELECT 'Created table: RAW.GATEWAY_CONNECTIONS' AS result;

-- ============================================================================
-- 4. RAW SCHEMA: Device Status Table
-- ============================================================================

SELECT '4. Creating RAW.DEVICE_STATUS Table...' AS step;

CREATE TABLE IF NOT EXISTS device_status (
    -- Primary identifiers
    event_id VARCHAR(255) DEFAULT UUID_STRING(),
    tenant_id VARCHAR(100) NOT NULL,  -- Set by ingestion pipeline, not DEFAULT (session vars not allowed)
    device_id VARCHAR(255) NOT NULL,
    site_id VARCHAR(100),

    -- Timestamp
    timestamp TIMESTAMP_NTZ NOT NULL,

    -- Device health
    status VARCHAR(50),                               -- 'online', 'offline', 'error', 'maintenance'
    battery_level NUMBER(5,2),                        -- Percentage (0-100)
    signal_strength NUMBER(5,2),                      -- RSSI or percentage
    temperature NUMBER(8,2),                          -- Device internal temperature
    firmware_version VARCHAR(50),

    -- Payload
    payload VARIANT,                                  -- Additional status information

    -- Ingestion
    ingestion_timestamp TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),

    PRIMARY KEY (event_id)

    -- Note: Snowflake does not support CHECK constraints
    -- Tenant isolation enforced at application layer
)
CLUSTER BY (DATE_TRUNC('day', timestamp), device_id)
DATA_RETENTION_TIME_IN_DAYS = 7
COMMENT = 'Device health and status tracking. Monitors battery, connectivity, and operational status.';

SELECT 'Created table: RAW.DEVICE_STATUS' AS result;

-- ============================================================================
-- 5. RAW SCHEMA: Uploaded Files Table
-- ============================================================================

SELECT '5. Creating RAW.UPLOADED_FILES Table...' AS step;

CREATE TABLE IF NOT EXISTS uploaded_files (
    -- Primary identifiers
    file_id VARCHAR(255) PRIMARY KEY DEFAULT UUID_STRING(),
    tenant_id VARCHAR(100) NOT NULL,  -- Set by ingestion pipeline, not DEFAULT (session vars not allowed)

    -- File details
    file_name VARCHAR(500),
    file_type VARCHAR(100),                           -- 'csv', 'json', 'parquet', 'excel'
    file_size NUMBER(20),                             -- Bytes
    file_path VARCHAR(1000),
    stage_location VARCHAR(1000),

    -- Upload metadata
    upload_timestamp TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    uploaded_by VARCHAR(255),
    upload_source VARCHAR(100),                       -- 'streamlit_portal', 'api', 'manual'

    -- Processing status
    status VARCHAR(50) DEFAULT 'uploaded',            -- 'uploaded', 'processing', 'completed', 'failed'
    rows_processed NUMBER(20),
    rows_inserted NUMBER(20),
    rows_failed NUMBER(20),
    processing_start_time TIMESTAMP_NTZ,
    processing_end_time TIMESTAMP_NTZ,
    processing_error VARCHAR(5000)

    -- Note: Snowflake does not support CHECK constraints
    -- Valid values for status: 'uploaded', 'processing', 'completed', 'failed', 'archived'
    -- Tenant isolation enforced at application layer
)
DATA_RETENTION_TIME_IN_DAYS = 7
COMMENT = 'Manual file upload tracking. Monitors file ingestion via Streamlit portal or API.';

SELECT 'Created table: RAW.UPLOADED_FILES' AS result;

-- ============================================================================
-- 6. NORMALIZED SCHEMA: Sensor Metrics Table
-- ============================================================================

SELECT '6. Creating NORMALIZED.SENSOR_METRICS Table...' AS step;

USE SCHEMA normalized;

CREATE TABLE IF NOT EXISTS sensor_metrics (
    -- Primary identifiers
    metric_id VARCHAR(255) DEFAULT UUID_STRING(),
    tenant_id VARCHAR(100) NOT NULL,  -- Set by ingestion pipeline, not DEFAULT (session vars not allowed)
    sensor_id VARCHAR(255) NOT NULL,
    site_id VARCHAR(100),
    device_id VARCHAR(255),

    -- Timestamp
    timestamp TIMESTAMP_NTZ NOT NULL,

    -- Metric details
    metric_name VARCHAR(255) NOT NULL,                -- 'temperature', 'humidity', 'pressure', etc.
    metric_value FLOAT,
    metric_unit VARCHAR(50),                          -- 'celsius', 'percent', 'pascal', etc.

    -- Quality and validation
    quality_flag VARCHAR(50) DEFAULT 'good',          -- 'good', 'suspect', 'bad'
    validation_status VARCHAR(50),                    -- 'passed', 'failed', 'not_checked'
    validation_rules_applied VARIANT,

    -- Enrichment
    sensor_type VARCHAR(100),
    sensor_location VARCHAR(500),
    additional_attributes VARIANT,

    -- Timestamps
    normalized_timestamp TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    source_reading_id VARCHAR(255),                   -- Reference to raw.sensor_readings

    PRIMARY KEY (metric_id)

    -- Note: Snowflake does not support CHECK constraints
    -- Valid values for quality_flag: 'good', 'suspect', 'bad', 'unknown'
    -- Tenant isolation enforced at application layer
)
CLUSTER BY (DATE_TRUNC('day', timestamp), sensor_id, metric_name)
DATA_RETENTION_TIME_IN_DAYS = 7
COMMENT = 'Normalized and validated sensor metrics. Flattened from raw payload with validation applied. One row per metric per reading.';

SELECT 'Created table: NORMALIZED.SENSOR_METRICS' AS result;

-- ============================================================================
-- 7. NORMALIZED SCHEMA: Device Events Table
-- ============================================================================

SELECT '7. Creating NORMALIZED.DEVICE_EVENTS Table...' AS step;

CREATE TABLE IF NOT EXISTS device_events (
    -- Primary identifiers
    event_id VARCHAR(255) DEFAULT UUID_STRING(),
    tenant_id VARCHAR(100) NOT NULL,  -- Set by ingestion pipeline, not DEFAULT (session vars not allowed)
    device_id VARCHAR(255) NOT NULL,
    site_id VARCHAR(100),

    -- Event details
    event_timestamp TIMESTAMP_NTZ NOT NULL,
    event_type VARCHAR(100) NOT NULL,                 -- 'connection', 'disconnection', 'error', 'alert', 'maintenance'
    event_category VARCHAR(100),                      -- 'connectivity', 'health', 'data_quality', 'operational'
    severity VARCHAR(50),                             -- 'critical', 'high', 'medium', 'low', 'info'

    -- Event data
    event_description VARCHAR(1000),
    event_data VARIANT,

    -- Context
    previous_state VARCHAR(100),
    new_state VARCHAR(100),

    -- Processing
    processed_timestamp TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),

    PRIMARY KEY (event_id)

    -- Note: Snowflake does not support CHECK constraints
    -- Valid values for severity: 'critical', 'high', 'medium', 'low', 'info'
    -- Tenant isolation enforced at application layer
)
CLUSTER BY (DATE_TRUNC('day', event_timestamp), device_id)
DATA_RETENTION_TIME_IN_DAYS = 30
COMMENT = 'Normalized device events for alerting and monitoring. Tracks state changes, errors, and operational events.';

SELECT 'Created table: NORMALIZED.DEVICE_EVENTS' AS result;

-- ============================================================================
-- 8. NORMALIZED SCHEMA: Site Metrics Table
-- ============================================================================

SELECT '8. Creating NORMALIZED.SITE_METRICS Table...' AS step;

CREATE TABLE IF NOT EXISTS site_metrics (
    -- Primary identifiers
    metric_id VARCHAR(255) DEFAULT UUID_STRING(),
    tenant_id VARCHAR(100) NOT NULL,  -- Set by ingestion pipeline, not DEFAULT (session vars not allowed)
    site_id VARCHAR(100) NOT NULL,

    -- Timestamp
    timestamp TIMESTAMP_NTZ NOT NULL,

    -- Site-level metrics
    metric_name VARCHAR(255) NOT NULL,
    metric_value FLOAT,
    metric_unit VARCHAR(50),
    metric_category VARCHAR(100),                     -- 'energy', 'production', 'quality', 'environment'

    -- Aggregation context
    aggregation_level VARCHAR(50),                    -- 'site', 'building', 'line', 'machine'
    aggregation_period VARCHAR(50),                   -- 'instant', '1min', '5min', '15min', '1hour'

    -- Quality
    data_quality_score FLOAT,
    sample_count NUMBER(20),

    -- Processing
    calculated_timestamp TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),

    PRIMARY KEY (metric_id)

    -- Note: Snowflake does not support CHECK constraints
    -- Tenant isolation enforced at application layer
)
CLUSTER BY (DATE_TRUNC('day', timestamp), site_id, metric_name)
DATA_RETENTION_TIME_IN_DAYS = 30
COMMENT = 'Site-level aggregated metrics. Rolls up sensor data to site level for dashboard consumption.';

SELECT 'Created table: NORMALIZED.SITE_METRICS' AS result;

-- ============================================================================
-- 9. AGGREGATED SCHEMA: Hourly Sensor Aggregates
-- ============================================================================

SELECT '9. Creating AGGREGATED.SENSOR_METRICS_HOURLY Table...' AS step;

USE SCHEMA aggregated;

CREATE TABLE IF NOT EXISTS sensor_metrics_hourly (
    -- Primary identifiers
    tenant_id VARCHAR(100) NOT NULL,  -- Set by ingestion pipeline, not DEFAULT (session vars not allowed)
    sensor_id VARCHAR(255) NOT NULL,
    site_id VARCHAR(100),
    metric_name VARCHAR(255) NOT NULL,

    -- Time bucket
    hour_timestamp TIMESTAMP_NTZ NOT NULL,            -- Truncated to hour

    -- Aggregated values
    avg_value FLOAT,
    min_value FLOAT,
    max_value FLOAT,
    sum_value FLOAT,
    stddev_value FLOAT,
    count_readings NUMBER(20),

    -- Quality metrics
    good_readings NUMBER(20),
    suspect_readings NUMBER(20),
    bad_readings NUMBER(20),
    data_quality_score FLOAT,

    -- Processing
    calculated_timestamp TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),

    PRIMARY KEY (hour_timestamp, sensor_id, metric_name)

    -- Note: Snowflake does not support CHECK constraints
    -- Tenant isolation enforced at application layer
)
CLUSTER BY (DATE_TRUNC('day', hour_timestamp), sensor_id)
DATA_RETENTION_TIME_IN_DAYS = 90
COMMENT = 'Hourly aggregated sensor metrics. Pre-computed statistics for dashboard performance. Retained for 90 days (Standard edition limit).';

SELECT 'Created table: AGGREGATED.SENSOR_METRICS_HOURLY' AS result;

-- ============================================================================
-- 10. AGGREGATED SCHEMA: Daily Sensor Aggregates
-- ============================================================================

SELECT '10. Creating AGGREGATED.SENSOR_METRICS_DAILY Table...' AS step;

CREATE TABLE IF NOT EXISTS sensor_metrics_daily (
    -- Primary identifiers
    tenant_id VARCHAR(100) NOT NULL,  -- Set by ingestion pipeline, not DEFAULT (session vars not allowed)
    sensor_id VARCHAR(255) NOT NULL,
    site_id VARCHAR(100),
    metric_name VARCHAR(255) NOT NULL,

    -- Time bucket
    day_date DATE NOT NULL,

    -- Aggregated values
    avg_value FLOAT,
    min_value FLOAT,
    max_value FLOAT,
    sum_value FLOAT,
    stddev_value FLOAT,
    count_readings NUMBER(20),

    -- Time-based statistics
    first_reading_time TIMESTAMP_NTZ,
    last_reading_time TIMESTAMP_NTZ,
    uptime_percentage FLOAT,

    -- Quality metrics
    good_readings NUMBER(20),
    suspect_readings NUMBER(20),
    bad_readings NUMBER(20),
    missing_hours NUMBER(5),                          -- Expected 24, actual may be less
    data_completeness_score FLOAT,

    -- Processing
    calculated_timestamp TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),

    PRIMARY KEY (day_date, sensor_id, metric_name)

    -- Note: Snowflake does not support CHECK constraints
    -- Tenant isolation enforced at application layer
)
CLUSTER BY (day_date, sensor_id)
DATA_RETENTION_TIME_IN_DAYS = 90
COMMENT = 'Daily aggregated sensor metrics. Historical trends and reporting. Retained for 90 days (Standard edition limit).';

SELECT 'Created table: AGGREGATED.SENSOR_METRICS_DAILY' AS result;

-- ============================================================================
-- 11. AGGREGATED SCHEMA: Site Performance Metrics
-- ============================================================================

SELECT '11. Creating AGGREGATED.SITE_PERFORMANCE_DAILY Table...' AS step;

CREATE TABLE IF NOT EXISTS site_performance_daily (
    -- Primary identifiers
    tenant_id VARCHAR(100) NOT NULL,  -- Set by ingestion pipeline, not DEFAULT (session vars not allowed)
    site_id VARCHAR(100) NOT NULL,
    day_date DATE NOT NULL,

    -- Operational metrics
    total_sensors NUMBER(10),
    active_sensors NUMBER(10),
    sensor_uptime_percentage FLOAT,

    -- Data volume
    total_readings NUMBER(20),
    total_bytes_ingested NUMBER(20),

    -- Quality
    avg_data_quality_score FLOAT,
    error_count NUMBER(20),
    alert_count NUMBER(20),

    -- Device connectivity
    avg_connected_devices FLOAT,
    connection_errors NUMBER(20),

    -- Processing
    calculated_timestamp TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),

    PRIMARY KEY (day_date, site_id)

    -- Note: Snowflake does not support CHECK constraints
    -- Tenant isolation enforced at application layer
)
CLUSTER BY (day_date)
DATA_RETENTION_TIME_IN_DAYS = 90
COMMENT = 'Daily site operational performance metrics. KPIs for site health monitoring. Retained for 90 days (Standard edition limit).';

SELECT 'Created table: AGGREGATED.SITE_PERFORMANCE_DAILY' AS result;

-- ============================================================================
-- 12. ANALYTICS SCHEMA: Current Sensor Status View
-- ============================================================================

SELECT '12. Creating ANALYTICS Views...' AS step;

USE SCHEMA analytics;

-- Sensor status view based on local raw data (no external dependencies)
CREATE OR REPLACE VIEW v_current_sensor_status AS
WITH latest_readings AS (
    SELECT
        sensor_id,
        site_id,
        device_id,
        MAX(timestamp) AS last_reading_time
    FROM raw.sensor_readings
    WHERE timestamp >= DATEADD(day, -1, CURRENT_TIMESTAMP())
    GROUP BY sensor_id, site_id, device_id
),
latest_device_status AS (
    SELECT
        device_id,
        firmware_version,
        status AS device_status,
        MAX(timestamp) AS last_status_time
    FROM raw.device_status
    WHERE timestamp >= DATEADD(day, -7, CURRENT_TIMESTAMP())
    GROUP BY device_id, firmware_version, status
)
SELECT
    lr.sensor_id,
    lr.device_id,
    lr.site_id,
    lr.last_reading_time,
    DATEDIFF(minute, lr.last_reading_time, CURRENT_TIMESTAMP()) AS minutes_since_last_reading,
    CASE
        WHEN lr.last_reading_time IS NULL THEN 'No Data'
        WHEN DATEDIFF(minute, lr.last_reading_time, CURRENT_TIMESTAMP()) <= 5 THEN 'Online'
        WHEN DATEDIFF(minute, lr.last_reading_time, CURRENT_TIMESTAMP()) <= 60 THEN 'Warning'
        ELSE 'Offline'
    END AS status,
    lds.last_status_time AS last_device_status_time,
    lds.firmware_version
FROM latest_readings lr
LEFT JOIN latest_device_status lds ON lr.device_id = lds.device_id
ORDER BY status DESC, minutes_since_last_reading DESC;

SELECT 'Created view: ANALYTICS.V_CURRENT_SENSOR_STATUS' AS result;

-- Note: schema_documentation table is created in 17_create_monitoring.sql
-- Documentation will be added there instead

-- ============================================================================
-- 13. RAW SCHEMA: Clamp Sensor Readings (Power Monitoring)
-- ============================================================================

SELECT '13. Creating RAW.CLAMP_SENSOR_READINGS Table...' AS step;

USE SCHEMA raw;

CREATE TABLE IF NOT EXISTS clamp_sensor_readings (
    -- Primary identifiers
    reading_id VARCHAR(255) PRIMARY KEY DEFAULT UUID_STRING(),
    tenant_id VARCHAR(100) NOT NULL,
    machine_id VARCHAR(255) NOT NULL,
    sensor_id VARCHAR(255) NOT NULL,
    site_id VARCHAR(100),

    -- Timestamp
    timestamp TIMESTAMP_NTZ NOT NULL,
    ingestion_timestamp TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),

    -- Three-phase current readings (Amps)
    current_phase_a FLOAT,
    current_phase_b FLOAT,
    current_phase_c FLOAT,
    current_rms FLOAT NOT NULL,                       -- RMS current for power calculation

    -- Three-phase voltage readings (Volts)
    voltage_phase_a FLOAT,
    voltage_phase_b FLOAT,
    voltage_phase_c FLOAT,

    -- Power quality
    power_factor FLOAT,                               -- 0-1 scale
    frequency FLOAT,                                  -- Hz (50/60)

    -- Raw payload for additional data
    raw_payload VARIANT,

    -- Quality indicators
    is_valid BOOLEAN DEFAULT TRUE,
    validation_errors VARIANT
)
CLUSTER BY (DATE_TRUNC('day', timestamp), machine_id)
DATA_RETENTION_TIME_IN_DAYS = 7
COMMENT = 'Raw clamp sensor readings for power monitoring. Three-phase current and voltage measurements from industrial machinery.';

SELECT 'Created table: RAW.CLAMP_SENSOR_READINGS' AS result;

-- ============================================================================
-- 14. NORMALIZED SCHEMA: Power Metrics
-- ============================================================================

SELECT '14. Creating NORMALIZED.POWER_METRICS Table...' AS step;

USE SCHEMA normalized;

CREATE TABLE IF NOT EXISTS power_metrics (
    -- Primary identifiers
    metric_id VARCHAR(255) PRIMARY KEY DEFAULT UUID_STRING(),
    tenant_id VARCHAR(100) NOT NULL,
    machine_id VARCHAR(255) NOT NULL,
    site_id VARCHAR(100),

    -- Timestamp
    timestamp TIMESTAMP_NTZ NOT NULL,
    calculated_timestamp TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),

    -- Power measurements (kW/kVA/kVAR)
    apparent_power_kva FLOAT,                         -- Total apparent power
    real_power_kw FLOAT NOT NULL,                     -- Active power
    reactive_power_kvar FLOAT,                        -- Reactive power

    -- Power quality
    power_factor FLOAT,

    -- Energy consumption
    energy_kwh FLOAT,                                 -- Energy for this interval

    -- Current metrics
    avg_current_amps FLOAT,
    max_current_amps FLOAT,

    -- Voltage metrics
    avg_voltage_volts FLOAT,

    -- Harmonics
    thd_current FLOAT,                                -- Total Harmonic Distortion - current
    thd_voltage FLOAT,                                -- Total Harmonic Distortion - voltage

    -- Source reference
    source_reading_id VARCHAR(255)                    -- Reference to raw.clamp_sensor_readings
)
CLUSTER BY (DATE_TRUNC('day', timestamp), machine_id)
DATA_RETENTION_TIME_IN_DAYS = 30
COMMENT = 'Calculated power metrics from clamp sensor readings. Includes real/reactive/apparent power and energy consumption.';

SELECT 'Created table: NORMALIZED.POWER_METRICS' AS result;

-- ============================================================================
-- 15. MART SCHEMA: Machine State Fact Table
-- ============================================================================

SELECT '15. Creating MART.FACT_MACHINE_STATE Table...' AS step;

USE SCHEMA mart;

CREATE TABLE IF NOT EXISTS fact_machine_state (
    -- Primary identifiers
    state_id VARCHAR(255) PRIMARY KEY DEFAULT UUID_STRING(),
    tenant_id VARCHAR(100) NOT NULL,
    machine_id VARCHAR(255) NOT NULL,
    site_id VARCHAR(100),

    -- Time dimensions
    timestamp_utc TIMESTAMP_NTZ NOT NULL,
    date_key DATE NOT NULL,
    hour_of_day NUMBER(2) NOT NULL,

    -- State classification
    state VARCHAR(50) NOT NULL,                       -- OFF, IDLE, WORKING, ERROR
    state_confidence FLOAT,                           -- 0-1 confidence score

    -- Power metrics at this state
    power_kw FLOAT,
    current_amps FLOAT,
    power_factor FLOAT,

    -- Time tracking
    interval_minutes NUMBER(10) DEFAULT 1,

    -- Energy and cost
    energy_kwh FLOAT,
    tariff_band VARCHAR(50),                          -- peak, offpeak, shoulder
    rate_per_kwh FLOAT,
    cost_gbp FLOAT,

    -- Quality
    data_quality VARCHAR(50) DEFAULT 'good'           -- good, suspect, interpolated
)
CLUSTER BY (date_key, machine_id)
DATA_RETENTION_TIME_IN_DAYS = 90
COMMENT = 'Machine state classifications with power and cost metrics. Core fact table for production monitoring dashboards.';

SELECT 'Created table: MART.FACT_MACHINE_STATE' AS result;

-- ============================================================================
-- 16. MART SCHEMA: Production Event Fact Table
-- ============================================================================

SELECT '16. Creating MART.FACT_PRODUCTION_EVENT Table...' AS step;

CREATE TABLE IF NOT EXISTS fact_production_event (
    -- Primary identifiers
    event_id VARCHAR(255) PRIMARY KEY DEFAULT UUID_STRING(),
    tenant_id VARCHAR(100) NOT NULL,
    machine_id VARCHAR(255) NOT NULL,
    site_id VARCHAR(100),

    -- Time boundaries
    start_timestamp TIMESTAMP_NTZ NOT NULL,
    end_timestamp TIMESTAMP_NTZ,
    duration_minutes FLOAT,

    -- Time dimensions
    date_key DATE NOT NULL,
    shift_id VARCHAR(100),
    operator_id VARCHAR(100),

    -- Power statistics during event
    avg_power_kw FLOAT,
    max_power_kw FLOAT,
    total_energy_kwh FLOAT,

    -- Production time breakdown
    working_time_minutes FLOAT,
    idle_time_minutes FLOAT,
    state_transitions NUMBER(10),

    -- Clustering/classification
    cluster_id VARCHAR(100),
    is_outlier BOOLEAN DEFAULT FALSE,
    outlier_score FLOAT,

    -- Product inference
    inferred_product_id VARCHAR(100),
    confidence_score FLOAT,

    -- Event status
    is_complete BOOLEAN DEFAULT FALSE,
    has_anomaly BOOLEAN DEFAULT FALSE,
    anomaly_type VARCHAR(100)
)
CLUSTER BY (date_key, machine_id)
DATA_RETENTION_TIME_IN_DAYS = 90
COMMENT = 'Production events detected from machine state changes. Used for OEE calculations and production tracking.';

SELECT 'Created table: MART.FACT_PRODUCTION_EVENT' AS result;

-- ============================================================================
-- 17. MART SCHEMA: Daily Energy Cost Fact Table
-- ============================================================================

SELECT '17. Creating MART.FACT_ENERGY_COST_DAILY Table...' AS step;

CREATE TABLE IF NOT EXISTS fact_energy_cost_daily (
    -- Primary identifiers (composite key)
    tenant_id VARCHAR(100) NOT NULL,
    machine_id VARCHAR(255) NOT NULL,
    date_key DATE NOT NULL,
    site_id VARCHAR(100),

    -- Operating hours by state
    total_hours FLOAT,
    off_hours FLOAT,
    idle_hours FLOAT,
    working_hours FLOAT,

    -- Energy consumption by state (kWh)
    total_energy_kwh FLOAT,
    off_energy_kwh FLOAT,
    idle_energy_kwh FLOAT,
    working_energy_kwh FLOAT,

    -- Cost by state (GBP)
    total_cost_gbp FLOAT,
    off_cost_gbp FLOAT,
    idle_cost_gbp FLOAT,
    working_cost_gbp FLOAT,

    -- Cost by tariff band
    peak_energy_kwh FLOAT,
    peak_cost_gbp FLOAT,
    shoulder_energy_kwh FLOAT,
    shoulder_cost_gbp FLOAT,
    offpeak_energy_kwh FLOAT,
    offpeak_cost_gbp FLOAT,

    -- Efficiency metrics
    idle_percentage FLOAT,
    working_percentage FLOAT,
    cost_per_working_hour FLOAT,

    -- Metadata
    calculated_timestamp TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),

    PRIMARY KEY (tenant_id, machine_id, date_key)
)
CLUSTER BY (date_key)
DATA_RETENTION_TIME_IN_DAYS = 90
COMMENT = 'Daily aggregated energy costs by machine. Breaks down consumption and costs by state and tariff band.';

SELECT 'Created table: MART.FACT_ENERGY_COST_DAILY' AS result;

-- ============================================================================
-- 18. RAW SCHEMA: Vibration Sensor Readings
-- ============================================================================

SELECT '18. Creating RAW.VIBRATION_SENSOR_READINGS Table...' AS step;

USE SCHEMA raw;

CREATE TABLE IF NOT EXISTS vibration_sensor_readings (
    -- Primary identifiers
    reading_id VARCHAR(255) PRIMARY KEY DEFAULT UUID_STRING(),
    tenant_id VARCHAR(100) NOT NULL,
    machine_id VARCHAR(255) NOT NULL,
    sensor_id VARCHAR(255) NOT NULL,
    site_id VARCHAR(100),

    -- Timestamp
    timestamp TIMESTAMP_NTZ NOT NULL,
    ingestion_timestamp TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),

    -- Vibration measurements (mm/s or g)
    vibration_x FLOAT,
    vibration_y FLOAT,
    vibration_z FLOAT,
    vibration_rms FLOAT NOT NULL,

    -- Temperature (sensor often includes temp)
    temperature FLOAT,

    -- Frequency analysis
    dominant_frequency FLOAT,                         -- Hz
    sampling_rate NUMBER(10),                         -- Hz

    -- Raw payload for additional data
    raw_payload VARIANT,

    -- Quality indicators
    is_valid BOOLEAN DEFAULT TRUE,
    validation_errors VARIANT,

    -- Metadata
    firmware_version VARCHAR(50),
    signal_quality NUMBER(3)
)
CLUSTER BY (DATE_TRUNC('day', timestamp), machine_id)
DATA_RETENTION_TIME_IN_DAYS = 7
COMMENT = 'Raw vibration sensor readings for machine health monitoring. Includes 3-axis vibration, temperature, and frequency analysis.';

SELECT 'Created table: RAW.VIBRATION_SENSOR_READINGS' AS result;

-- ============================================================================
-- 19. RAW SCHEMA: Environmental Sensor Readings
-- ============================================================================

SELECT '19. Creating RAW.ENVIRONMENTAL_SENSOR_READINGS Table...' AS step;

CREATE TABLE IF NOT EXISTS environmental_sensor_readings (
    -- Primary identifiers
    reading_id VARCHAR(255) PRIMARY KEY DEFAULT UUID_STRING(),
    tenant_id VARCHAR(100) NOT NULL,
    zone_id VARCHAR(255) NOT NULL,                    -- Environmental zone (not machine)
    sensor_id VARCHAR(255) NOT NULL,
    site_id VARCHAR(100),

    -- Timestamp
    timestamp TIMESTAMP_NTZ NOT NULL,
    ingestion_timestamp TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),

    -- Temperature and humidity
    temperature FLOAT,                                -- Celsius
    humidity FLOAT,                                   -- Percentage
    dew_point FLOAT,                                  -- Celsius (calculated)

    -- Air quality
    co2_ppm FLOAT,                                    -- Parts per million
    voc_index NUMBER(10),                             -- Volatile Organic Compounds index
    particulates_pm25 FLOAT,                          -- µg/m³
    particulates_pm10 FLOAT,                          -- µg/m³

    -- Ambient conditions
    noise_db FLOAT,                                   -- Decibels
    light_lux FLOAT,                                  -- Lux
    pressure_hpa FLOAT,                               -- Hectopascals

    -- Raw payload for additional data
    raw_payload VARIANT,

    -- Quality indicators
    is_valid BOOLEAN DEFAULT TRUE,
    validation_errors VARIANT,

    -- Metadata
    firmware_version VARCHAR(50),
    calibration_date DATE
)
CLUSTER BY (DATE_TRUNC('day', timestamp), zone_id)
DATA_RETENTION_TIME_IN_DAYS = 7
COMMENT = 'Raw environmental sensor readings for factory floor monitoring. Includes temperature, humidity, air quality, noise, and light.';

SELECT 'Created table: RAW.ENVIRONMENTAL_SENSOR_READINGS' AS result;

-- ============================================================================
-- 20. Verification
-- ============================================================================

SELECT '20. Verifying Table Creation...' AS step;

-- Show tables in each schema
USE SCHEMA raw;
SHOW TABLES;

USE SCHEMA normalized;
SHOW TABLES;

USE SCHEMA aggregated;
SHOW TABLES;

USE SCHEMA analytics;
SHOW TABLES;
SHOW VIEWS;

USE SCHEMA mart;
SHOW TABLES;

-- Note: v_tenant_objects view is created in 17_create_monitoring.sql
-- Table size query will be available after monitoring setup

-- ============================================================================
-- 19. Summary
-- ============================================================================

SELECT '╔════════════════════════════════════════════════════════════════╗' AS summary
UNION ALL SELECT '║  Tenant Table Creation Complete                            ║'
UNION ALL SELECT '╚════════════════════════════════════════════════════════════╝'
UNION ALL SELECT ''
UNION ALL SELECT 'Created Tables by Schema:'
UNION ALL SELECT ''
UNION ALL SELECT 'RAW Schema (Data Ingestion):'
UNION ALL SELECT '  [OK] sensor_readings (7-day retention) - Generic sensor data'
UNION ALL SELECT '  [OK] gateway_connections (7-day retention)'
UNION ALL SELECT '  [OK] device_status (7-day retention)'
UNION ALL SELECT '  [OK] uploaded_files (7-day retention)'
UNION ALL SELECT '  [OK] clamp_sensor_readings (7-day retention) - Power monitoring'
UNION ALL SELECT '  [OK] vibration_sensor_readings (7-day retention) - Machine health'
UNION ALL SELECT '  [OK] environmental_sensor_readings (7-day retention) - Factory floor'
UNION ALL SELECT ''
UNION ALL SELECT 'NORMALIZED Schema (Validated Data):'
UNION ALL SELECT '  [OK] sensor_metrics (7-day retention)'
UNION ALL SELECT '  [OK] device_events (30-day retention)'
UNION ALL SELECT '  [OK] site_metrics (30-day retention)'
UNION ALL SELECT '  [OK] power_metrics (30-day retention) - Power calculations'
UNION ALL SELECT ''
UNION ALL SELECT 'AGGREGATED Schema (Pre-computed Metrics):'
UNION ALL SELECT '  [OK] sensor_metrics_hourly (90-day retention)'
UNION ALL SELECT '  [OK] sensor_metrics_daily (90-day retention)'
UNION ALL SELECT '  [OK] site_performance_daily (90-day retention)'
UNION ALL SELECT ''
UNION ALL SELECT 'ANALYTICS Schema (Views):'
UNION ALL SELECT '  [OK] v_current_sensor_status'
UNION ALL SELECT ''
UNION ALL SELECT 'MART Schema (Business Facts):'
UNION ALL SELECT '  [OK] fact_machine_state (90-day retention) - State classification'
UNION ALL SELECT '  [OK] fact_production_event (90-day retention) - Production events'
UNION ALL SELECT '  [OK] fact_energy_cost_daily (90-day retention) - Daily costs'
UNION ALL SELECT ''
UNION ALL SELECT 'Features:'
UNION ALL SELECT '  • All tables clustered for query performance'
UNION ALL SELECT '  • Time Travel enabled (7-90 days depending on schema)'
UNION ALL SELECT '  • Tenant isolation enforced at application layer'
UNION ALL SELECT '  • UUID primary keys for distributed systems'
UNION ALL SELECT '  • VARIANT columns for semi-structured data'
UNION ALL SELECT ''
UNION ALL SELECT 'Next Steps:'
UNION ALL SELECT '  1. Run 13_create_streams.sql to enable CDC'
UNION ALL SELECT '  2. Run 14_create_tasks.sql to configure ETL pipeline'
UNION ALL SELECT '  3. Run 15_create_dynamic_tables.sql for real-time aggregations'
UNION ALL SELECT '  4. Test data ingestion from Kinesis'
UNION ALL SELECT ''
UNION ALL SELECT 'Test Query:'
UNION ALL SELECT '  SELECT * FROM analytics.v_tenant_objects;'
UNION ALL SELECT '============================================================';
