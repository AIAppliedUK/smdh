# SMDH Data Layer Implementation Guide

## Overview

This guide provides step-by-step instructions to implement the manufacturing analytics data layer on your existing Snowflake infrastructure. All scripts are designed to work with your multi-tenant architecture.

## Prerequisites

- ✅ Existing SMDH Snowflake infrastructure (completed)
- ✅ AWS IoT → Kinesis → Snowflake pipeline (operational)
- ✅ ACCOUNTADMIN role access for initial setup
- ✅ Snowpark Python enabled for ML procedures

## Implementation Steps

### Step 1: Create MART Schema and ML Models Schema

Run this for each tenant database:

```sql
-- ============================================================================
-- MART Schema Creation for Tenant
-- Usage: snowsql -f create_mart_schema.sql -D tenant_id='company_a'
-- ============================================================================

USE ROLE ACCOUNTADMIN;
SET database_name = 'smdh_tenant_' || '&tenant_id';
USE DATABASE IDENTIFIER($database_name);

-- Create MART schema for analytics-ready data
CREATE SCHEMA IF NOT EXISTS mart
    COMMENT = 'Analytics-ready facts and dimensions for dashboards';

-- Create ML_MODELS schema for model storage
CREATE SCHEMA IF NOT EXISTS ml_models
    COMMENT = 'Trained ML models and parameters';

-- Create REFERENCE schema for configuration data
CREATE SCHEMA IF NOT EXISTS reference
    COMMENT = 'Reference data: tariffs, thresholds, configurations';

-- Grant permissions
GRANT USAGE ON SCHEMA mart TO ROLE smdh_tenant_admin_&tenant_id;
GRANT USAGE ON SCHEMA ml_models TO ROLE smdh_tenant_admin_&tenant_id;
GRANT USAGE ON SCHEMA reference TO ROLE smdh_tenant_admin_&tenant_id;

GRANT SELECT ON ALL TABLES IN SCHEMA mart TO ROLE smdh_tenant_readonly_&tenant_id;
GRANT SELECT ON ALL TABLES IN SCHEMA reference TO ROLE smdh_tenant_readonly_&tenant_id;
```

### Step 2: Extend RAW Schema for Power Data

```sql
-- ============================================================================
-- Extend RAW Schema for Power/Current Measurements
-- ============================================================================

USE SCHEMA raw;

-- Table for clamp sensor readings
CREATE TABLE IF NOT EXISTS clamp_sensor_readings (
    reading_id VARCHAR(255) DEFAULT UUID_STRING(),
    tenant_id VARCHAR(100) NOT NULL DEFAULT '&tenant_id',
    machine_id VARCHAR(255) NOT NULL,
    sensor_id VARCHAR(255) NOT NULL,
    timestamp TIMESTAMP_NTZ NOT NULL,

    -- Three-phase current measurements
    current_phase_a FLOAT,
    current_phase_b FLOAT,
    current_phase_c FLOAT,
    current_rms FLOAT,

    -- Voltage (from machine configuration)
    voltage_nominal FLOAT,

    -- Power factor (default or measured)
    power_factor FLOAT DEFAULT 0.85,

    -- Calculated power (will be computed by pipeline)
    calculated_power_kw FLOAT,

    -- Raw payload
    raw_payload VARIANT,
    ingestion_timestamp TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),

    PRIMARY KEY (reading_id)
)
CLUSTER BY (DATE_TRUNC('day', timestamp), machine_id)
DATA_RETENTION_TIME_IN_DAYS = 30
COMMENT = 'Clamp sensor current measurements for power calculation';

-- Vibration sensor readings (Sentinel functionality)
CREATE TABLE IF NOT EXISTS vibration_readings (
    reading_id VARCHAR(255) DEFAULT UUID_STRING(),
    tenant_id VARCHAR(100) NOT NULL DEFAULT '&tenant_id',
    machine_id VARCHAR(255) NOT NULL,
    sensor_id VARCHAR(255) NOT NULL,
    timestamp TIMESTAMP_NTZ NOT NULL,

    vibration_x FLOAT,
    vibration_y FLOAT,
    vibration_z FLOAT,
    vibration_rms FLOAT,
    temperature FLOAT,

    raw_payload VARIANT,
    ingestion_timestamp TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),

    PRIMARY KEY (reading_id)
)
CLUSTER BY (DATE_TRUNC('day', timestamp), machine_id)
DATA_RETENTION_TIME_IN_DAYS = 30
COMMENT = 'Vibration and temperature for machine health monitoring';

-- Environmental readings (HAVEN functionality)
CREATE TABLE IF NOT EXISTS environmental_readings (
    reading_id VARCHAR(255) DEFAULT UUID_STRING(),
    tenant_id VARCHAR(100) NOT NULL DEFAULT '&tenant_id',
    zone_id VARCHAR(255) NOT NULL,
    sensor_id VARCHAR(255) NOT NULL,
    timestamp TIMESTAMP_NTZ NOT NULL,

    temperature FLOAT,
    humidity FLOAT,
    co2_ppm FLOAT,
    voc_index FLOAT,
    particulates_pm25 FLOAT,
    noise_db FLOAT,

    raw_payload VARIANT,
    ingestion_timestamp TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),

    PRIMARY KEY (reading_id)
)
CLUSTER BY (DATE_TRUNC('day', timestamp), zone_id)
DATA_RETENTION_TIME_IN_DAYS = 30
COMMENT = 'Environmental monitoring for workplace conditions';
```

### Step 3: Create NORMALIZED Power Metrics

```sql
-- ============================================================================
-- NORMALIZED Schema Extensions
-- ============================================================================

USE SCHEMA normalized;

-- Power metrics calculation table
CREATE TABLE IF NOT EXISTS power_metrics (
    metric_id VARCHAR(255) DEFAULT UUID_STRING(),
    tenant_id VARCHAR(100) NOT NULL DEFAULT '&tenant_id',
    machine_id VARCHAR(255) NOT NULL,
    timestamp TIMESTAMP_NTZ NOT NULL,

    -- Power calculations
    apparent_power_kva FLOAT,
    real_power_kw FLOAT,
    reactive_power_kvar FLOAT,
    power_factor FLOAT,

    -- Current/Voltage
    avg_current_amps FLOAT,
    max_current_amps FLOAT,
    voltage_volts FLOAT,

    -- Energy for interval
    interval_minutes NUMBER DEFAULT 1,
    energy_kwh FLOAT,

    -- Quality
    data_quality VARCHAR(20) DEFAULT 'good',

    normalized_timestamp TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (metric_id)
)
CLUSTER BY (DATE_TRUNC('day', timestamp), machine_id)
DATA_RETENTION_TIME_IN_DAYS = 90
COMMENT = 'Calculated power metrics from clamp sensor readings';

-- Machine events table
CREATE TABLE IF NOT EXISTS machine_events (
    event_id VARCHAR(255) DEFAULT UUID_STRING(),
    tenant_id VARCHAR(100) NOT NULL DEFAULT '&tenant_id',
    machine_id VARCHAR(255) NOT NULL,
    event_timestamp TIMESTAMP_NTZ NOT NULL,

    event_type VARCHAR(100),
    event_subtype VARCHAR(100),

    previous_state VARCHAR(50),
    current_state VARCHAR(50),

    power_at_event FLOAT,
    duration_in_state_seconds NUMBER,

    PRIMARY KEY (event_id)
)
CLUSTER BY (DATE_TRUNC('day', event_timestamp), machine_id)
DATA_RETENTION_TIME_IN_DAYS = 90
COMMENT = 'State changes and operational events';
```

### Step 4: Create MART Dimension Tables

```sql
-- ============================================================================
-- MART Dimension Tables
-- ============================================================================

USE SCHEMA mart;

-- Machine dimension with enriched metadata
CREATE TABLE IF NOT EXISTS dim_machine (
    machine_id VARCHAR(255) PRIMARY KEY,
    tenant_id VARCHAR(100) NOT NULL DEFAULT '&tenant_id',
    machine_name VARCHAR(255),
    machine_type VARCHAR(100),
    manufacturer VARCHAR(255),
    model VARCHAR(255),

    -- Location hierarchy
    site_id VARCHAR(100),
    site_name VARCHAR(255),
    line_id VARCHAR(100),
    line_name VARCHAR(255),
    area_id VARCHAR(100),
    area_name VARCHAR(255),

    -- Electrical configuration
    voltage_type VARCHAR(50) DEFAULT 'three_phase',
    nominal_voltage FLOAT DEFAULT 400,
    nominal_current FLOAT,
    nominal_power_kw FLOAT,
    default_power_factor FLOAT DEFAULT 0.85,

    -- State thresholds (will be set by ML)
    threshold_off_max_kw FLOAT,
    threshold_idle_min_kw FLOAT,
    threshold_idle_max_kw FLOAT,
    threshold_working_min_kw FLOAT,

    -- ML metadata
    gmm_model_version VARCHAR(50),
    gmm_last_trained TIMESTAMP_NTZ,
    gmm_training_days NUMBER DEFAULT 14,

    -- Status
    is_active BOOLEAN DEFAULT TRUE,
    installation_date DATE,
    created_timestamp TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    updated_timestamp TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'Machine master data with configuration and thresholds';

-- Product cluster dimension
CREATE TABLE IF NOT EXISTS dim_prod_cluster (
    cluster_id VARCHAR(255) PRIMARY KEY,
    tenant_id VARCHAR(100) NOT NULL DEFAULT '&tenant_id',
    machine_id VARCHAR(255),
    cluster_number NUMBER,

    -- Cluster characteristics
    median_duration_minutes FLOAT,
    iqr_duration_minutes FLOAT,
    min_duration_minutes FLOAT,
    max_duration_minutes FLOAT,

    avg_power_kw FLOAT,
    std_power_kw FLOAT,

    -- Product mapping (optional)
    product_id VARCHAR(255),
    product_name VARCHAR(255),
    product_sku VARCHAR(255),

    -- Statistics
    total_events NUMBER,
    first_seen_date DATE,
    last_seen_date DATE,

    -- Model metadata
    dbscan_eps FLOAT,
    dbscan_min_samples NUMBER,
    model_version VARCHAR(50),

    created_timestamp TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    last_updated TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'Production event clusters representing product types';

-- Tariff dimension
CREATE TABLE IF NOT EXISTS dim_tariff (
    tariff_id VARCHAR(255) PRIMARY KEY,
    tenant_id VARCHAR(100) NOT NULL DEFAULT '&tenant_id',
    site_id VARCHAR(100),

    tariff_name VARCHAR(255),
    supplier VARCHAR(255),

    valid_from DATE,
    valid_to DATE,

    -- Rate bands
    peak_rate_per_kwh FLOAT,
    peak_start_time TIME,
    peak_end_time TIME,

    shoulder_rate_per_kwh FLOAT,
    shoulder_start_time TIME,
    shoulder_end_time TIME,

    offpeak_rate_per_kwh FLOAT,

    standing_charge_daily FLOAT,

    currency VARCHAR(10) DEFAULT 'GBP',

    created_timestamp TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'Energy tariff configuration for cost calculation';

-- Zone dimension for environmental monitoring
CREATE TABLE IF NOT EXISTS dim_zone (
    zone_id VARCHAR(255) PRIMARY KEY,
    tenant_id VARCHAR(100) NOT NULL DEFAULT '&tenant_id',
    site_id VARCHAR(100),

    zone_name VARCHAR(255),
    zone_type VARCHAR(100),
    floor_number NUMBER,
    area_sqm FLOAT,

    -- Thresholds
    temp_min_threshold FLOAT DEFAULT 18,
    temp_max_threshold FLOAT DEFAULT 25,
    humidity_min_threshold FLOAT DEFAULT 30,
    humidity_max_threshold FLOAT DEFAULT 60,
    noise_max_threshold FLOAT DEFAULT 85,

    created_timestamp TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'Physical zones for environmental monitoring';
```

### Step 5: Create MART Fact Tables

```sql
-- ============================================================================
-- MART Fact Tables
-- ============================================================================

USE SCHEMA mart;

-- Machine state fact table (main analytical table)
CREATE TABLE IF NOT EXISTS fact_machine_state (
    state_id VARCHAR(255) DEFAULT UUID_STRING(),
    tenant_id VARCHAR(100) NOT NULL DEFAULT '&tenant_id',
    machine_id VARCHAR(255) NOT NULL,

    -- Time dimensions
    timestamp_utc TIMESTAMP_NTZ NOT NULL,
    date_key DATE,
    hour_of_day NUMBER,
    shift_id VARCHAR(100),

    -- State classification
    state VARCHAR(20) NOT NULL,
    state_confidence FLOAT,

    -- Power metrics
    power_kw FLOAT,
    current_amps FLOAT,
    power_factor FLOAT,

    -- Energy and cost
    interval_minutes NUMBER DEFAULT 1,
    energy_kwh FLOAT,

    tariff_band VARCHAR(50),
    rate_per_kwh FLOAT,
    cost_gbp FLOAT,

    -- Quality
    data_quality VARCHAR(20) DEFAULT 'good',

    PRIMARY KEY (state_id),
    FOREIGN KEY (machine_id) REFERENCES dim_machine(machine_id) NOT ENFORCED
)
CLUSTER BY (date_key, machine_id)
DATA_RETENTION_TIME_IN_DAYS = 365
COMMENT = 'Machine states with power and cost at 1-minute intervals';

-- Production events fact
CREATE TABLE IF NOT EXISTS fact_production_event (
    event_id VARCHAR(255) DEFAULT UUID_STRING(),
    tenant_id VARCHAR(100) NOT NULL DEFAULT '&tenant_id',
    machine_id VARCHAR(255) NOT NULL,

    -- Event timing
    start_timestamp TIMESTAMP_NTZ NOT NULL,
    end_timestamp TIMESTAMP_NTZ NOT NULL,
    duration_minutes FLOAT,

    -- Context
    date_key DATE,
    shift_id VARCHAR(100),

    -- Metrics
    avg_power_kw FLOAT,
    max_power_kw FLOAT,
    total_energy_kwh FLOAT,

    -- State breakdown
    working_time_minutes FLOAT,
    idle_time_minutes FLOAT,

    -- Clustering
    cluster_id VARCHAR(255),
    is_outlier BOOLEAN DEFAULT FALSE,
    outlier_score FLOAT,

    -- Product inference
    inferred_product_id VARCHAR(255),
    confidence_score FLOAT,

    -- Quality flags
    is_complete BOOLEAN DEFAULT TRUE,
    has_anomaly BOOLEAN DEFAULT FALSE,

    PRIMARY KEY (event_id),
    FOREIGN KEY (machine_id) REFERENCES dim_machine(machine_id) NOT ENFORCED,
    FOREIGN KEY (cluster_id) REFERENCES dim_prod_cluster(cluster_id) NOT ENFORCED
)
CLUSTER BY (date_key, machine_id)
DATA_RETENTION_TIME_IN_DAYS = 365
COMMENT = 'Production events detected from state sequences';

-- Daily energy and cost summary
CREATE TABLE IF NOT EXISTS fact_energy_cost_daily (
    tenant_id VARCHAR(100) NOT NULL DEFAULT '&tenant_id',
    machine_id VARCHAR(255) NOT NULL,
    date_key DATE NOT NULL,

    -- Time breakdown
    total_hours FLOAT,
    off_hours FLOAT,
    idle_hours FLOAT,
    working_hours FLOAT,

    -- Energy by state
    total_energy_kwh FLOAT,
    off_energy_kwh FLOAT,
    idle_energy_kwh FLOAT,
    working_energy_kwh FLOAT,

    -- Cost by state
    total_cost_gbp FLOAT,
    off_cost_gbp FLOAT,
    idle_cost_gbp FLOAT,
    working_cost_gbp FLOAT,

    -- Efficiency metrics
    idle_percentage FLOAT,
    working_percentage FLOAT,
    idle_cost_percentage FLOAT,

    created_timestamp TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),

    PRIMARY KEY (date_key, machine_id),
    FOREIGN KEY (machine_id) REFERENCES dim_machine(machine_id) NOT ENFORCED
)
CLUSTER BY (date_key)
DATA_RETENTION_TIME_IN_DAYS = 730
COMMENT = 'Daily energy and cost rollup by machine and state';

-- Anomaly fact table
CREATE TABLE IF NOT EXISTS fact_anomaly (
    anomaly_id VARCHAR(255) DEFAULT UUID_STRING(),
    tenant_id VARCHAR(100) NOT NULL DEFAULT '&tenant_id',
    machine_id VARCHAR(255),

    detected_timestamp TIMESTAMP_NTZ NOT NULL,

    anomaly_type VARCHAR(100),
    severity VARCHAR(20),
    confidence_score FLOAT,

    expected_value FLOAT,
    actual_value FLOAT,
    deviation_percentage FLOAT,

    event_id VARCHAR(255),

    is_acknowledged BOOLEAN DEFAULT FALSE,
    resolution_notes VARCHAR(2000),

    PRIMARY KEY (anomaly_id)
)
CLUSTER BY (DATE_TRUNC('day', detected_timestamp), machine_id)
DATA_RETENTION_TIME_IN_DAYS = 365
COMMENT = 'Detected anomalies and outliers';

-- OEE calculation fact
CREATE TABLE IF NOT EXISTS fact_oee_daily (
    tenant_id VARCHAR(100) NOT NULL DEFAULT '&tenant_id',
    machine_id VARCHAR(255) NOT NULL,
    date_key DATE NOT NULL,

    -- Time components
    planned_production_time_minutes FLOAT,
    actual_runtime_minutes FLOAT,

    -- OEE Components
    availability_percentage FLOAT,
    performance_percentage FLOAT,
    quality_percentage FLOAT,
    oee_percentage FLOAT,

    -- State breakdown
    off_time_minutes FLOAT,
    idle_time_minutes FLOAT,
    working_time_minutes FLOAT,

    -- Production metrics
    production_events_count NUMBER,
    avg_event_duration_minutes FLOAT,

    created_timestamp TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),

    PRIMARY KEY (date_key, machine_id),
    FOREIGN KEY (machine_id) REFERENCES dim_machine(machine_id) NOT ENFORCED
)
CLUSTER BY (date_key)
DATA_RETENTION_TIME_IN_DAYS = 730
COMMENT = 'Daily OEE calculations';
```

### Step 6: Create ML Model Storage Tables

```sql
-- ============================================================================
-- ML Model Storage
-- ============================================================================

USE SCHEMA ml_models;

-- GMM model storage
CREATE TABLE IF NOT EXISTS gmm_models (
    model_id VARCHAR(255) DEFAULT UUID_STRING(),
    machine_id VARCHAR(255) NOT NULL,

    model_params VARIANT,
    model_binary BINARY,  -- Pickled sklearn model

    training_samples NUMBER,
    training_start_date DATE,
    training_end_date DATE,

    model_version VARCHAR(50),
    is_active BOOLEAN DEFAULT TRUE,

    created_timestamp TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),

    PRIMARY KEY (model_id)
)
COMMENT = 'Stored GMM models for state classification';

-- DBSCAN model storage
CREATE TABLE IF NOT EXISTS dbscan_models (
    model_id VARCHAR(255) DEFAULT UUID_STRING(),
    machine_id VARCHAR(255) NOT NULL,

    model_params VARIANT,

    eps FLOAT,
    min_samples NUMBER,

    clusters_found NUMBER,
    outliers_found NUMBER,

    model_version VARCHAR(50),
    is_active BOOLEAN DEFAULT TRUE,

    created_timestamp TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),

    PRIMARY KEY (model_id)
)
COMMENT = 'DBSCAN clustering parameters';

-- Model performance tracking
CREATE TABLE IF NOT EXISTS model_performance (
    performance_id VARCHAR(255) DEFAULT UUID_STRING(),
    model_id VARCHAR(255),
    model_type VARCHAR(50),
    machine_id VARCHAR(255),

    evaluation_date DATE,

    accuracy FLOAT,
    precision_score FLOAT,
    recall_score FLOAT,
    f1_score FLOAT,

    samples_evaluated NUMBER,

    created_timestamp TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),

    PRIMARY KEY (performance_id)
)
COMMENT = 'Model performance metrics';
```

### Step 7: Create Power Calculation Task

```sql
-- ============================================================================
-- Task: Calculate Power from Current Readings
-- ============================================================================

USE SCHEMA normalized;

CREATE OR REPLACE TASK task_calculate_power
    WAREHOUSE = smdh_streaming_wh
    SCHEDULE = '1 MINUTE'
AS
INSERT INTO power_metrics (
    tenant_id,
    machine_id,
    timestamp,
    real_power_kw,
    apparent_power_kva,
    power_factor,
    avg_current_amps,
    max_current_amps,
    voltage_volts,
    interval_minutes,
    energy_kwh
)
WITH new_readings AS (
    SELECT
        c.tenant_id,
        c.machine_id,
        c.timestamp,
        c.current_phase_a,
        c.current_phase_b,
        c.current_phase_c,
        c.current_rms,
        c.power_factor,
        m.voltage_type,
        COALESCE(c.voltage_nominal, m.nominal_voltage, 400) as voltage,
        COALESCE(c.power_factor, m.default_power_factor, 0.85) as pf
    FROM raw.clamp_sensor_readings c
    JOIN mart.dim_machine m ON c.machine_id = m.machine_id
    WHERE c.ingestion_timestamp >= DATEADD(minute, -2, CURRENT_TIMESTAMP())
        AND c.ingestion_timestamp > (
            SELECT COALESCE(MAX(normalized_timestamp), '2000-01-01')
            FROM power_metrics
            WHERE machine_id = c.machine_id
        )
)
SELECT
    tenant_id,
    machine_id,
    timestamp,
    -- Real power calculation
    CASE
        WHEN voltage_type = 'three_phase' THEN
            SQRT(3) * voltage * COALESCE(current_rms,
                (current_phase_a + current_phase_b + current_phase_c) / 3)
                * pf / 1000  -- Convert to kW
        ELSE
            voltage * current_rms * pf / 1000
    END as real_power_kw,
    -- Apparent power
    CASE
        WHEN voltage_type = 'three_phase' THEN
            SQRT(3) * voltage * COALESCE(current_rms,
                (current_phase_a + current_phase_b + current_phase_c) / 3) / 1000
        ELSE
            voltage * current_rms / 1000
    END as apparent_power_kva,
    pf as power_factor,
    COALESCE(current_rms, (current_phase_a + current_phase_b + current_phase_c) / 3) as avg_current_amps,
    GREATEST(current_phase_a, current_phase_b, current_phase_c, current_rms) as max_current_amps,
    voltage as voltage_volts,
    1 as interval_minutes,
    -- Energy = Power * Time (in hours)
    CASE
        WHEN voltage_type = 'three_phase' THEN
            SQRT(3) * voltage * COALESCE(current_rms,
                (current_phase_a + current_phase_b + current_phase_c) / 3)
                * pf / 1000 * (1/60)  -- 1 minute in hours
        ELSE
            voltage * current_rms * pf / 1000 * (1/60)
    END as energy_kwh
FROM new_readings;

-- Start the task
ALTER TASK task_calculate_power RESUME;
```

### Step 8: Create State Classification Procedure

```sql
-- ============================================================================
-- Stored Procedure: GMM State Classification
-- ============================================================================

USE SCHEMA ml_models;

CREATE OR REPLACE PROCEDURE sp_train_gmm_classifier(
    machine_id VARCHAR,
    training_days NUMBER DEFAULT 14
)
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.8'
PACKAGES = ('snowflake-snowpark-python', 'scikit-learn==1.3.0', 'numpy', 'pandas')
HANDLER = 'train_gmm'
AS
$$
from sklearn.mixture import GaussianMixture
import pandas as pd
import numpy as np
import json
from datetime import datetime

def train_gmm(session, machine_id: str, training_days: int) -> str:
    """
    Train GMM for state classification following paper methodology
    """

    # Fetch training data
    query = f"""
    SELECT
        timestamp,
        real_power_kw as power
    FROM normalized.power_metrics
    WHERE machine_id = '{machine_id}'
        AND timestamp >= DATEADD(day, -{training_days}, CURRENT_TIMESTAMP())
        AND real_power_kw IS NOT NULL
    ORDER BY timestamp
    """

    df = session.sql(query).to_pandas()

    if len(df) < 1000:
        return json.dumps({"status": "error", "message": "Insufficient data"})

    # Prepare data
    X = df['power'].values.reshape(-1, 1)

    # Train GMM with 5 initial components
    gmm = GaussianMixture(
        n_components=5,
        covariance_type='full',
        n_init=10,
        random_state=42
    )
    gmm.fit(X)

    # Get component statistics
    components = []
    for i in range(5):
        mask = gmm.predict(X) == i
        if mask.sum() > 0:
            component_data = X[mask]
            components.append({
                'mean': float(gmm.means_[i][0]),
                'std': float(np.sqrt(gmm.covariances_[i][0][0])),
                'weight': float(gmm.weights_[i]),
                'support': int(mask.sum())
            })

    # Sort by mean power
    components.sort(key=lambda x: x['mean'])

    # Determine thresholds
    if len(components) >= 3:
        # OFF: lowest power component + margin
        off_threshold = components[0]['mean'] + 2 * components[0]['std']

        # WORKING: highest significant component
        working_idx = -1
        for i in range(len(components)-1, -1, -1):
            if components[i]['weight'] > 0.1:  # At least 10% support
                working_idx = i
                break

        if working_idx > 0:
            working_threshold = (components[working_idx]['mean'] +
                                components[working_idx-1]['mean']) / 2
        else:
            working_threshold = components[-1]['mean'] - components[-1]['std']

        # Update machine thresholds
        session.sql(f"""
            UPDATE mart.dim_machine
            SET threshold_off_max_kw = {off_threshold},
                threshold_idle_min_kw = {off_threshold},
                threshold_idle_max_kw = {working_threshold},
                threshold_working_min_kw = {working_threshold},
                gmm_model_version = '1.0',
                gmm_last_trained = CURRENT_TIMESTAMP(),
                updated_timestamp = CURRENT_TIMESTAMP()
            WHERE machine_id = '{machine_id}'
        """).collect()

        # Store model parameters
        model_params = {
            'components': components,
            'thresholds': {
                'off_max': off_threshold,
                'idle_range': [off_threshold, working_threshold],
                'working_min': working_threshold
            }
        }

        session.sql(f"""
            INSERT INTO gmm_models (
                machine_id,
                model_params,
                training_samples,
                model_version
            ) VALUES (
                '{machine_id}',
                PARSE_JSON('{json.dumps(model_params)}'),
                {len(df)},
                '1.0'
            )
        """).collect()

        return json.dumps({"status": "success", "thresholds": model_params['thresholds']})

    return json.dumps({"status": "error", "message": "Could not determine thresholds"})
$$;
```

### Step 9: Create State Assignment Task

```sql
-- ============================================================================
-- Task: Assign Machine States
-- ============================================================================

USE SCHEMA mart;

CREATE OR REPLACE TASK task_assign_machine_states
    WAREHOUSE = smdh_etl_wh
    SCHEDULE = '1 MINUTE'
    AFTER task_calculate_power
AS
INSERT INTO fact_machine_state (
    tenant_id,
    machine_id,
    timestamp_utc,
    date_key,
    hour_of_day,
    state,
    state_confidence,
    power_kw,
    current_amps,
    power_factor,
    interval_minutes,
    energy_kwh
)
WITH power_data AS (
    SELECT
        p.tenant_id,
        p.machine_id,
        p.timestamp as timestamp_utc,
        DATE_TRUNC('day', p.timestamp) as date_key,
        HOUR(p.timestamp) as hour_of_day,
        p.real_power_kw as power_kw,
        p.avg_current_amps as current_amps,
        p.power_factor,
        p.interval_minutes,
        p.energy_kwh,
        m.threshold_off_max_kw,
        m.threshold_idle_max_kw,
        m.threshold_working_min_kw
    FROM normalized.power_metrics p
    JOIN mart.dim_machine m ON p.machine_id = m.machine_id
    WHERE p.normalized_timestamp >= DATEADD(minute, -2, CURRENT_TIMESTAMP())
        AND NOT EXISTS (
            SELECT 1 FROM fact_machine_state s
            WHERE s.machine_id = p.machine_id
                AND s.timestamp_utc = p.timestamp
        )
)
SELECT
    tenant_id,
    machine_id,
    timestamp_utc,
    date_key,
    hour_of_day,
    -- State classification based on thresholds
    CASE
        WHEN power_kw <= threshold_off_max_kw THEN 'OFF'
        WHEN power_kw >= threshold_working_min_kw THEN 'WORKING'
        ELSE 'IDLE'
    END as state,
    -- Confidence based on distance from thresholds
    CASE
        WHEN power_kw <= threshold_off_max_kw THEN
            GREATEST(0, 1 - (power_kw / NULLIF(threshold_off_max_kw, 0)))
        WHEN power_kw >= threshold_working_min_kw THEN
            LEAST(1, (power_kw - threshold_working_min_kw) / NULLIF(power_kw, 0))
        ELSE
            0.5  -- Idle state has medium confidence
    END as state_confidence,
    power_kw,
    current_amps,
    power_factor,
    interval_minutes,
    energy_kwh
FROM power_data;

-- Start the task
ALTER TASK task_assign_machine_states RESUME;
```

### Step 10: Create Production Event Detection Task

```sql
-- ============================================================================
-- Task: Detect Production Events
-- ============================================================================

USE SCHEMA mart;

CREATE OR REPLACE TASK task_detect_production_events
    WAREHOUSE = smdh_etl_wh
    SCHEDULE = '5 MINUTE'
AS
WITH state_runs AS (
    -- Find contiguous working periods
    SELECT
        machine_id,
        timestamp_utc,
        state,
        date_key,
        power_kw,
        energy_kwh,
        -- Identify run groups using gaps
        SUM(CASE WHEN state != LAG(state) OVER (PARTITION BY machine_id ORDER BY timestamp_utc)
                 THEN 1 ELSE 0 END) OVER (PARTITION BY machine_id ORDER BY timestamp_utc) as run_group
    FROM fact_machine_state
    WHERE timestamp_utc >= DATEADD(hour, -2, CURRENT_TIMESTAMP())
),
working_periods AS (
    -- Aggregate working runs
    SELECT
        machine_id,
        run_group,
        MIN(timestamp_utc) as start_time,
        MAX(timestamp_utc) as end_time,
        MIN(date_key) as date_key,
        AVG(power_kw) as avg_power,
        SUM(energy_kwh) as total_energy,
        COUNT(*) as data_points
    FROM state_runs
    WHERE state = 'WORKING'
    GROUP BY machine_id, run_group
    HAVING TIMESTAMPDIFF(minute, MIN(timestamp_utc), MAX(timestamp_utc)) >= 2  -- Min 2 minutes
)
INSERT INTO fact_production_event (
    tenant_id,
    machine_id,
    start_timestamp,
    end_timestamp,
    duration_minutes,
    date_key,
    avg_power_kw,
    total_energy_kwh,
    working_time_minutes
)
SELECT
    m.tenant_id,
    wp.machine_id,
    wp.start_time,
    wp.end_time,
    TIMESTAMPDIFF(minute, wp.start_time, wp.end_time) as duration_minutes,
    wp.date_key,
    wp.avg_power,
    wp.total_energy,
    wp.data_points as working_time_minutes
FROM working_periods wp
JOIN mart.dim_machine m ON wp.machine_id = m.machine_id
WHERE NOT EXISTS (
    SELECT 1 FROM fact_production_event e
    WHERE e.machine_id = wp.machine_id
        AND e.start_timestamp = wp.start_time
);

-- Start the task
ALTER TASK task_detect_production_events RESUME;
```

### Step 11: Create Energy Cost Calculation Task

```sql
-- ============================================================================
-- Task: Calculate Energy Costs
-- ============================================================================

USE SCHEMA mart;

-- First, insert sample tariff data
INSERT INTO dim_tariff (
    tariff_id,
    tenant_id,
    site_id,
    tariff_name,
    supplier,
    valid_from,
    valid_to,
    peak_rate_per_kwh,
    peak_start_time,
    peak_end_time,
    shoulder_rate_per_kwh,
    shoulder_start_time,
    shoulder_end_time,
    offpeak_rate_per_kwh,
    standing_charge_daily,
    currency
) VALUES (
    'DEFAULT_TARIFF',
    '&tenant_id',
    NULL,
    'Standard Business Tariff',
    'Default Supplier',
    '2024-01-01',
    '2024-12-31',
    0.35,  -- Peak rate
    '07:00:00',
    '19:00:00',
    0.25,  -- Shoulder rate
    '19:00:00',
    '23:00:00',
    0.15,  -- Off-peak rate
    5.00,  -- Standing charge
    'GBP'
);

-- Update fact_machine_state with costs
CREATE OR REPLACE TASK task_calculate_energy_costs
    WAREHOUSE = smdh_etl_wh
    SCHEDULE = '5 MINUTE'
AS
UPDATE fact_machine_state fs
SET
    tariff_band = CASE
        WHEN TIME(fs.timestamp_utc) BETWEEN t.peak_start_time AND t.peak_end_time
            AND DAYOFWEEK(fs.timestamp_utc) BETWEEN 1 AND 5 THEN 'peak'
        WHEN TIME(fs.timestamp_utc) BETWEEN t.shoulder_start_time AND t.shoulder_end_time THEN 'shoulder'
        ELSE 'offpeak'
    END,
    rate_per_kwh = CASE
        WHEN TIME(fs.timestamp_utc) BETWEEN t.peak_start_time AND t.peak_end_time
            AND DAYOFWEEK(fs.timestamp_utc) BETWEEN 1 AND 5 THEN t.peak_rate_per_kwh
        WHEN TIME(fs.timestamp_utc) BETWEEN t.shoulder_start_time AND t.shoulder_end_time THEN t.shoulder_rate_per_kwh
        ELSE t.offpeak_rate_per_kwh
    END,
    cost_gbp = fs.energy_kwh * CASE
        WHEN TIME(fs.timestamp_utc) BETWEEN t.peak_start_time AND t.peak_end_time
            AND DAYOFWEEK(fs.timestamp_utc) BETWEEN 1 AND 5 THEN t.peak_rate_per_kwh
        WHEN TIME(fs.timestamp_utc) BETWEEN t.shoulder_start_time AND t.shoulder_end_time THEN t.shoulder_rate_per_kwh
        ELSE t.offpeak_rate_per_kwh
    END
FROM mart.dim_tariff t
WHERE fs.timestamp_utc >= DATEADD(minute, -10, CURRENT_TIMESTAMP())
    AND fs.cost_gbp IS NULL
    AND t.tariff_id = 'DEFAULT_TARIFF';

-- Daily aggregation task
CREATE OR REPLACE TASK task_aggregate_energy_costs_daily
    WAREHOUSE = smdh_etl_wh
    SCHEDULE = 'USING CRON 0 1 * * * UTC'  -- Daily at 1 AM UTC
AS
INSERT INTO fact_energy_cost_daily (
    tenant_id,
    machine_id,
    date_key,
    total_hours,
    off_hours,
    idle_hours,
    working_hours,
    total_energy_kwh,
    off_energy_kwh,
    idle_energy_kwh,
    working_energy_kwh,
    total_cost_gbp,
    off_cost_gbp,
    idle_cost_gbp,
    working_cost_gbp,
    idle_percentage,
    working_percentage,
    idle_cost_percentage
)
SELECT
    tenant_id,
    machine_id,
    date_key,
    COUNT(DISTINCT timestamp_utc) / 60.0 as total_hours,
    SUM(CASE WHEN state = 'OFF' THEN interval_minutes ELSE 0 END) / 60.0 as off_hours,
    SUM(CASE WHEN state = 'IDLE' THEN interval_minutes ELSE 0 END) / 60.0 as idle_hours,
    SUM(CASE WHEN state = 'WORKING' THEN interval_minutes ELSE 0 END) / 60.0 as working_hours,
    SUM(energy_kwh) as total_energy_kwh,
    SUM(CASE WHEN state = 'OFF' THEN energy_kwh ELSE 0 END) as off_energy_kwh,
    SUM(CASE WHEN state = 'IDLE' THEN energy_kwh ELSE 0 END) as idle_energy_kwh,
    SUM(CASE WHEN state = 'WORKING' THEN energy_kwh ELSE 0 END) as working_energy_kwh,
    SUM(cost_gbp) as total_cost_gbp,
    SUM(CASE WHEN state = 'OFF' THEN cost_gbp ELSE 0 END) as off_cost_gbp,
    SUM(CASE WHEN state = 'IDLE' THEN cost_gbp ELSE 0 END) as idle_cost_gbp,
    SUM(CASE WHEN state = 'WORKING' THEN cost_gbp ELSE 0 END) as working_cost_gbp,
    SUM(CASE WHEN state = 'IDLE' THEN interval_minutes ELSE 0 END) /
        NULLIF(SUM(interval_minutes), 0) * 100 as idle_percentage,
    SUM(CASE WHEN state = 'WORKING' THEN interval_minutes ELSE 0 END) /
        NULLIF(SUM(interval_minutes), 0) * 100 as working_percentage,
    SUM(CASE WHEN state = 'IDLE' THEN cost_gbp ELSE 0 END) /
        NULLIF(SUM(cost_gbp), 0) * 100 as idle_cost_percentage
FROM fact_machine_state
WHERE date_key = DATEADD(day, -1, CURRENT_DATE())
GROUP BY tenant_id, machine_id, date_key;

-- Start the tasks
ALTER TASK task_calculate_energy_costs RESUME;
ALTER TASK task_aggregate_energy_costs_daily RESUME;
```

### Step 12: Create Dashboard Views

```sql
-- ============================================================================
-- Analytics Views for Streamlit Dashboards
-- ============================================================================

USE SCHEMA analytics;

-- View 1: Fleet Utilization Summary
CREATE OR REPLACE VIEW v_fleet_utilization AS
SELECT
    m.machine_name,
    m.line_name,
    m.site_name,
    fs.date_key,
    SUM(CASE WHEN fs.state = 'OFF' THEN fs.interval_minutes ELSE 0 END) / 60.0 as off_hours,
    SUM(CASE WHEN fs.state = 'IDLE' THEN fs.interval_minutes ELSE 0 END) / 60.0 as idle_hours,
    SUM(CASE WHEN fs.state = 'WORKING' THEN fs.interval_minutes ELSE 0 END) / 60.0 as working_hours,
    -- Percentages
    SUM(CASE WHEN fs.state = 'OFF' THEN fs.interval_minutes ELSE 0 END) /
        NULLIF(SUM(fs.interval_minutes), 0) * 100 as off_percentage,
    SUM(CASE WHEN fs.state = 'IDLE' THEN fs.interval_minutes ELSE 0 END) /
        NULLIF(SUM(fs.interval_minutes), 0) * 100 as idle_percentage,
    SUM(CASE WHEN fs.state = 'WORKING' THEN fs.interval_minutes ELSE 0 END) /
        NULLIF(SUM(fs.interval_minutes), 0) * 100 as working_percentage,
    -- Energy and cost
    SUM(CASE WHEN fs.state = 'IDLE' THEN fs.energy_kwh ELSE 0 END) as idle_energy_kwh,
    SUM(CASE WHEN fs.state = 'IDLE' THEN fs.cost_gbp ELSE 0 END) as idle_cost_gbp
FROM mart.fact_machine_state fs
JOIN mart.dim_machine m ON fs.machine_id = m.machine_id
WHERE m.is_active = TRUE
GROUP BY 1,2,3,4
COMMENT = 'Fleet utilization metrics for dashboard';

-- View 2: Machine Timeline Detail
CREATE OR REPLACE VIEW v_machine_timeline AS
SELECT
    m.machine_name,
    fs.timestamp_utc,
    fs.state,
    fs.power_kw,
    fs.energy_kwh,
    fs.cost_gbp,
    fs.tariff_band,
    LAG(fs.state) OVER (PARTITION BY fs.machine_id ORDER BY fs.timestamp_utc) as prev_state,
    LEAD(fs.state) OVER (PARTITION BY fs.machine_id ORDER BY fs.timestamp_utc) as next_state
FROM mart.fact_machine_state fs
JOIN mart.dim_machine m ON fs.machine_id = m.machine_id
COMMENT = 'Detailed timeline view for individual machines';

-- View 3: Production Events Summary
CREATE OR REPLACE VIEW v_production_events AS
SELECT
    m.machine_name,
    m.line_name,
    pe.start_timestamp,
    pe.end_timestamp,
    pe.duration_minutes,
    pe.avg_power_kw,
    pe.total_energy_kwh,
    pc.cluster_number,
    pc.product_name,
    pc.median_duration_minutes as typical_duration,
    pe.is_outlier,
    CASE
        WHEN pe.is_outlier THEN 'Anomaly'
        WHEN pc.product_name IS NOT NULL THEN pc.product_name
        ELSE CONCAT('Type ', pc.cluster_number)
    END as event_type
FROM mart.fact_production_event pe
JOIN mart.dim_machine m ON pe.machine_id = m.machine_id
LEFT JOIN mart.dim_prod_cluster pc ON pe.cluster_id = pc.cluster_id
COMMENT = 'Production events with clustering';

-- View 4: Energy Cost Analysis
CREATE OR REPLACE VIEW v_energy_cost_analysis AS
SELECT
    m.machine_name,
    m.line_name,
    ec.date_key,
    ec.total_energy_kwh,
    ec.idle_energy_kwh,
    ec.working_energy_kwh,
    ec.total_cost_gbp,
    ec.idle_cost_gbp,
    ec.working_cost_gbp,
    ec.idle_percentage,
    ec.working_percentage,
    ec.idle_cost_percentage,
    ec.idle_cost_gbp / NULLIF(ec.idle_hours, 0) as idle_cost_per_hour,
    ec.working_cost_gbp / NULLIF(ec.working_hours, 0) as working_cost_per_hour
FROM mart.fact_energy_cost_daily ec
JOIN mart.dim_machine m ON ec.machine_id = m.machine_id
COMMENT = 'Energy and cost analysis by machine and state';

-- View 5: Anomaly Dashboard
CREATE OR REPLACE VIEW v_anomalies AS
SELECT
    a.detected_timestamp,
    m.machine_name,
    m.line_name,
    a.anomaly_type,
    a.severity,
    a.expected_value,
    a.actual_value,
    a.deviation_percentage,
    a.is_acknowledged,
    pe.duration_minutes as event_duration,
    pe.avg_power_kw as event_power
FROM mart.fact_anomaly a
LEFT JOIN mart.dim_machine m ON a.machine_id = m.machine_id
LEFT JOIN mart.fact_production_event pe ON a.event_id = pe.event_id
COMMENT = 'Anomaly detection results';

-- View 6: OEE Dashboard
CREATE OR REPLACE VIEW v_oee_summary AS
SELECT
    m.machine_name,
    m.line_name,
    o.date_key,
    o.availability_percentage,
    o.performance_percentage,
    o.quality_percentage,
    o.oee_percentage,
    o.working_time_minutes / 60.0 as working_hours,
    o.idle_time_minutes / 60.0 as idle_hours,
    o.production_events_count,
    o.avg_event_duration_minutes
FROM mart.fact_oee_daily o
JOIN mart.dim_machine m ON o.machine_id = m.machine_id
COMMENT = 'OEE metrics summary';

-- View 7: Real-time Machine Status
CREATE OR REPLACE VIEW v_current_machine_status AS
WITH latest_state AS (
    SELECT
        machine_id,
        MAX(timestamp_utc) as last_update
    FROM mart.fact_machine_state
    WHERE timestamp_utc >= DATEADD(minute, -5, CURRENT_TIMESTAMP())
    GROUP BY machine_id
)
SELECT
    m.machine_name,
    m.line_name,
    m.site_name,
    fs.state as current_state,
    fs.power_kw as current_power_kw,
    fs.timestamp_utc as last_update,
    TIMESTAMPDIFF(minute, fs.timestamp_utc, CURRENT_TIMESTAMP()) as minutes_since_update,
    CASE
        WHEN TIMESTAMPDIFF(minute, fs.timestamp_utc, CURRENT_TIMESTAMP()) > 5 THEN 'OFFLINE'
        ELSE fs.state
    END as status
FROM latest_state ls
JOIN mart.fact_machine_state fs ON ls.machine_id = fs.machine_id
    AND ls.last_update = fs.timestamp_utc
JOIN mart.dim_machine m ON fs.machine_id = m.machine_id
WHERE m.is_active = TRUE
COMMENT = 'Current machine status for real-time monitoring';

-- Grant permissions to read views
GRANT SELECT ON ALL VIEWS IN SCHEMA analytics TO ROLE smdh_tenant_readonly_&tenant_id;
GRANT SELECT ON ALL VIEWS IN SCHEMA analytics TO ROLE smdh_tenant_analyst_&tenant_id;
```

## Streamlit Integration

### Connection Configuration

Create a `.streamlit/secrets.toml` file:

```toml
[snowflake]
account = "your-account"
user = "streamlit_user"
password = "secure_password"
warehouse = "smdh_analytics_wh"
database = "smdh_tenant_company_a"
schema = "analytics"
role = "smdh_tenant_analyst_company_a"
```

### Sample Dashboard Code

```python
# app.py - Fleet Utilization Dashboard

import streamlit as st
import pandas as pd
import plotly.express as px
from datetime import datetime, timedelta
import snowflake.connector

# Page config
st.set_page_config(
    page_title="SMDH Fleet Utilization",
    page_icon="🏭",
    layout="wide"
)

# Initialize connection
@st.cache_resource
def init_connection():
    return snowflake.connector.connect(
        **st.secrets["snowflake"]
    )

conn = init_connection()

# Query data
@st.cache_data(ttl=60)
def get_fleet_utilization(start_date, end_date):
    query = """
    SELECT * FROM v_fleet_utilization
    WHERE date_key BETWEEN %s AND %s
    ORDER BY idle_percentage DESC
    """
    df = pd.read_sql(query, conn, params=[start_date, end_date])
    return df

# Dashboard layout
st.title("🏭 Fleet Utilization Dashboard")

# Filters
col1, col2 = st.columns(2)
with col1:
    start_date = st.date_input(
        "Start Date",
        datetime.now() - timedelta(days=7)
    )
with col2:
    end_date = st.date_input(
        "End Date",
        datetime.now()
    )

# Fetch data
df = get_fleet_utilization(start_date, end_date)

# KPI Metrics
col1, col2, col3, col4 = st.columns(4)
with col1:
    avg_utilization = df['working_percentage'].mean()
    st.metric("Avg Utilization", f"{avg_utilization:.1f}%")
with col2:
    total_idle_cost = df['idle_cost_gbp'].sum()
    st.metric("Idle Cost", f"£{total_idle_cost:,.0f}")
with col3:
    total_idle_energy = df['idle_energy_kwh'].sum()
    st.metric("Idle Energy", f"{total_idle_energy:,.0f} kWh")
with col4:
    machines_count = df['machine_name'].nunique()
    st.metric("Machines", machines_count)

# Utilization chart
st.subheader("Machine Utilization Breakdown")

# Prepare data for stacked bar
utilization_data = df.groupby('machine_name').agg({
    'off_percentage': 'mean',
    'idle_percentage': 'mean',
    'working_percentage': 'mean'
}).reset_index()

# Create stacked bar chart
fig = px.bar(
    utilization_data,
    x='machine_name',
    y=['off_percentage', 'idle_percentage', 'working_percentage'],
    title='Utilization by Machine',
    labels={'value': 'Percentage (%)', 'variable': 'State'},
    color_discrete_map={
        'off_percentage': '#d62728',
        'idle_percentage': '#ff7f0e',
        'working_percentage': '#2ca02c'
    }
)
fig.update_layout(barmode='stack', xaxis_tickangle=-45)
st.plotly_chart(fig, use_container_width=True)

# Idle cost ranking
st.subheader("Idle Cost Ranking")

idle_cost_df = df.groupby('machine_name').agg({
    'idle_hours': 'sum',
    'idle_energy_kwh': 'sum',
    'idle_cost_gbp': 'sum'
}).sort_values('idle_cost_gbp', ascending=False).head(10)

st.dataframe(
    idle_cost_df.style.format({
        'idle_hours': '{:.1f}',
        'idle_energy_kwh': '{:.1f}',
        'idle_cost_gbp': '£{:.2f}'
    }),
    use_container_width=True
)

# Timeline view for selected machine
st.subheader("Machine Timeline")

selected_machine = st.selectbox(
    "Select Machine",
    df['machine_name'].unique()
)

if selected_machine:
    timeline_query = """
    SELECT * FROM v_machine_timeline
    WHERE machine_name = %s
        AND DATE(timestamp_utc) = %s
    ORDER BY timestamp_utc
    """

    timeline_df = pd.read_sql(
        timeline_query,
        conn,
        params=[selected_machine, end_date]
    )

    if not timeline_df.empty:
        # Create timeline visualization
        fig = px.scatter(
            timeline_df,
            x='timestamp_utc',
            y='power_kw',
            color='state',
            title=f'Power Profile - {selected_machine}',
            color_discrete_map={
                'OFF': '#d62728',
                'IDLE': '#ff7f0e',
                'WORKING': '#2ca02c'
            }
        )
        st.plotly_chart(fig, use_container_width=True)
```

## Validation & Testing

### Step 1: Validate Schema Creation

```sql
-- Check all schemas created
SELECT SCHEMA_NAME
FROM INFORMATION_SCHEMA.SCHEMATA
WHERE CATALOG_NAME = 'SMDH_TENANT_COMPANY_A'
    AND SCHEMA_NAME IN ('MART', 'ML_MODELS', 'REFERENCE')
ORDER BY SCHEMA_NAME;

-- Check MART tables
SELECT TABLE_NAME, ROW_COUNT
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_CATALOG = 'SMDH_TENANT_COMPANY_A'
    AND TABLE_SCHEMA = 'MART'
ORDER BY TABLE_NAME;
```

### Step 2: Generate Test Data

```sql
-- Insert test machine
INSERT INTO mart.dim_machine (
    machine_id,
    tenant_id,
    machine_name,
    machine_type,
    site_id,
    site_name,
    line_id,
    line_name,
    voltage_type,
    nominal_voltage,
    nominal_power_kw,
    default_power_factor
) VALUES (
    'MACHINE_001',
    'company_a',
    'CNC Machine 1',
    'CNC',
    'SITE_001',
    'Main Factory',
    'LINE_001',
    'Production Line 1',
    'three_phase',
    400,
    15,
    0.85
);

-- Generate synthetic power data
INSERT INTO raw.clamp_sensor_readings (
    machine_id,
    sensor_id,
    timestamp,
    current_phase_a,
    current_phase_b,
    current_phase_c,
    current_rms,
    voltage_nominal,
    power_factor
)
SELECT
    'MACHINE_001',
    'SENSOR_001',
    DATEADD(minute, -seq4(), CURRENT_TIMESTAMP()),
    -- Simulate varying current based on time
    CASE
        WHEN MOD(seq4(), 60) < 10 THEN UNIFORM(1, 3, RANDOM())  -- OFF
        WHEN MOD(seq4(), 60) < 30 THEN UNIFORM(5, 8, RANDOM())  -- IDLE
        ELSE UNIFORM(15, 25, RANDOM())  -- WORKING
    END as current_a,
    CASE
        WHEN MOD(seq4(), 60) < 10 THEN UNIFORM(1, 3, RANDOM())
        WHEN MOD(seq4(), 60) < 30 THEN UNIFORM(5, 8, RANDOM())
        ELSE UNIFORM(15, 25, RANDOM())
    END as current_b,
    CASE
        WHEN MOD(seq4(), 60) < 10 THEN UNIFORM(1, 3, RANDOM())
        WHEN MOD(seq4(), 60) < 30 THEN UNIFORM(5, 8, RANDOM())
        ELSE UNIFORM(15, 25, RANDOM())
    END as current_c,
    NULL as current_rms,
    400,
    0.85
FROM TABLE(GENERATOR(ROWCOUNT => 1440))  -- 24 hours of data
;
```

### Step 3: Train GMM Model

```sql
-- Train the model
CALL ml_models.sp_train_gmm_classifier('MACHINE_001', 1);

-- Check thresholds
SELECT
    machine_id,
    threshold_off_max_kw,
    threshold_idle_max_kw,
    threshold_working_min_kw,
    gmm_last_trained
FROM mart.dim_machine
WHERE machine_id = 'MACHINE_001';
```

### Step 4: Verify Pipeline

```sql
-- Check power calculations
SELECT COUNT(*) as power_records
FROM normalized.power_metrics
WHERE machine_id = 'MACHINE_001';

-- Check state assignments
SELECT
    state,
    COUNT(*) as count,
    AVG(power_kw) as avg_power
FROM mart.fact_machine_state
WHERE machine_id = 'MACHINE_001'
GROUP BY state;

-- Check production events
SELECT COUNT(*) as events_detected
FROM mart.fact_production_event
WHERE machine_id = 'MACHINE_001';
```

## Monitoring & Operations

### Daily Health Check

```sql
CREATE OR REPLACE PROCEDURE analytics.sp_daily_health_check()
RETURNS TABLE (
    check_name VARCHAR,
    status VARCHAR,
    details VARIANT
)
LANGUAGE SQL
AS
$$
DECLARE
    res RESULTSET;
BEGIN
    -- Check 1: Data ingestion
    res := (
        SELECT
            'Data Ingestion' as check_name,
            CASE
                WHEN COUNT(*) > 0 THEN 'PASS'
                ELSE 'FAIL'
            END as status,
            OBJECT_CONSTRUCT(
                'records_last_hour', COUNT(*),
                'latest_timestamp', MAX(ingestion_timestamp)
            ) as details
        FROM raw.clamp_sensor_readings
        WHERE ingestion_timestamp >= DATEADD(hour, -1, CURRENT_TIMESTAMP())
    );

    RETURN TABLE(res);
END;
$$;
```

## Troubleshooting Guide

### Issue: No states being classified

```sql
-- Check if thresholds are set
SELECT machine_id, threshold_off_max_kw, threshold_idle_max_kw, threshold_working_min_kw
FROM mart.dim_machine;

-- If NULL, retrain the model
CALL ml_models.sp_train_gmm_classifier('MACHINE_ID', 7);
```

### Issue: High idle costs

```sql
-- Analyze idle patterns
SELECT
    DATE_TRUNC('hour', timestamp_utc) as hour,
    SUM(CASE WHEN state = 'IDLE' THEN interval_minutes ELSE 0 END) as idle_minutes,
    SUM(CASE WHEN state = 'IDLE' THEN cost_gbp ELSE 0 END) as idle_cost
FROM mart.fact_machine_state
WHERE machine_id = 'MACHINE_ID'
    AND date_key >= DATEADD(day, -7, CURRENT_DATE())
GROUP BY 1
ORDER BY idle_cost DESC;
```

## Next Steps

1. **Deploy to production** - Run scripts in production tenant
2. **Configure Streamlit** - Deploy dashboards to Streamlit Cloud
3. **Set up monitoring** - Enable alerts for pipeline failures
4. **Train users** - Provide dashboard training
5. **Optimize performance** - Monitor query performance and adjust

## Support

For issues or questions:
- Review logs: `SELECT * FROM task_history WHERE state = 'FAILED'`
- Check documentation: [Snowflake Docs](https://docs.snowflake.com)
- Contact: platform-team@smdh.com