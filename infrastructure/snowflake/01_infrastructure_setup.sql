-- ============================================================================
-- SMDH Infrastructure Database Setup
-- ============================================================================
-- Purpose: Create shared infrastructure and metadata for SMDH platform
-- Usage: snowsql -f 01_infrastructure_setup.sql
-- Author: SMDH Platform Team
-- Version: 1.0
-- ============================================================================
-- This script creates:
-- - smdh_infrastructure database
-- - tenant_configs schema (tenant metadata)
-- - monitoring schema (platform metrics)
-- - audit schema (access tracking)
-- - Core tables for tenant registry and device tracking
-- ============================================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE SMDH_WH;

-- Display banner
SELECT '╔════════════════════════════════════════════════════════════════╗' AS banner
UNION ALL SELECT '║  SMDH Platform - Infrastructure Setup                      ║'
UNION ALL SELECT '╚════════════════════════════════════════════════════════════╝';

-- ============================================================================
-- 1. Create Infrastructure Database
-- ============================================================================

SELECT '1. Creating Infrastructure Database...' AS step;

CREATE DATABASE IF NOT EXISTS smdh_infrastructure
    DATA_RETENTION_TIME_IN_DAYS = 7
    COMMENT = 'SMDH platform infrastructure and shared resources. Contains tenant metadata, monitoring data, and audit logs.';

-- ============================================================================
-- 2. Create Schemas
-- ============================================================================

SELECT '2. Creating Infrastructure Schemas...' AS step;

USE DATABASE smdh_infrastructure;

-- Tenant configuration and metadata
CREATE SCHEMA IF NOT EXISTS tenant_configs
    DATA_RETENTION_TIME_IN_DAYS = 7
    COMMENT = 'Tenant metadata, configuration, and registry. Central source of truth for all SMDH tenants.';

-- Platform monitoring and metrics
CREATE SCHEMA IF NOT EXISTS monitoring
    DATA_RETENTION_TIME_IN_DAYS = 30
    COMMENT = 'Platform-wide monitoring, metrics, and health checks. Used for operational dashboards.';

-- Audit logs and access tracking
CREATE SCHEMA IF NOT EXISTS audit
    DATA_RETENTION_TIME_IN_DAYS = 90
    COMMENT = 'Audit logs, access tracking, and compliance records. Retained for 90 days for security compliance.';

-- ============================================================================
-- 3. Create Tenant Registry Table
-- ============================================================================

SELECT '3. Creating Tenant Registry...' AS step;

USE SCHEMA tenant_configs;

CREATE TABLE IF NOT EXISTS tenants (
    -- Primary identifiers
    tenant_id VARCHAR(100) PRIMARY KEY,
    tenant_name VARCHAR(500) NOT NULL,
    status VARCHAR(50) DEFAULT 'active',

    -- Timestamps
    created_date TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    updated_date TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    activated_date TIMESTAMP_NTZ,
    suspended_date TIMESTAMP_NTZ,
    offboarded_date TIMESTAMP_NTZ,

    -- Infrastructure details
    aws_region VARCHAR(50) NOT NULL DEFAULT 'eu-west-2',
    aws_account_id VARCHAR(50),
    iot_endpoint VARCHAR(500),
    kinesis_stream_name VARCHAR(255),

    -- AWS IoT Thing Groups (hierarchical device management)
    tenant_thing_group_name VARCHAR(255),
    tenant_thing_group_arn VARCHAR(500),

    -- Capacity configuration
    num_sites NUMBER(10),
    num_sensors NUMBER(10),
    data_retention_days NUMBER(10) DEFAULT 730,
    warehouse_size VARCHAR(50) DEFAULT 'SMALL',

    -- Business information
    contact_email VARCHAR(255),
    contact_phone VARCHAR(50),
    billing_entity VARCHAR(500),
    contract_start_date DATE,
    contract_end_date DATE,

    -- Metadata
    notes VARCHAR(5000),
    metadata VARIANT

    -- Note: Snowflake does not support CHECK constraints
    -- Valid values for status: 'provisioning', 'active', 'suspended', 'offboarded'
    -- Valid values for aws_region: 'eu-west-2', 'eu-west-1', 'us-east-1'
    -- Valid values for warehouse_size: 'XSMALL', 'SMALL', 'MEDIUM', 'LARGE', 'XLARGE'
)
COMMENT = 'Master registry of all SMDH tenants. Single source of truth for tenant configuration and status.';

-- ============================================================================
-- 4. Create Tenant Users Tracking
-- ============================================================================

SELECT '4. Creating Tenant Users Table...' AS step;

CREATE TABLE IF NOT EXISTS tenant_users (
    user_id VARCHAR(255),
    tenant_id VARCHAR(100) NOT NULL,
    username VARCHAR(255) NOT NULL,
    email VARCHAR(255) NOT NULL,
    role_name VARCHAR(100) NOT NULL,

    -- Timestamps
    created_date TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    last_login TIMESTAMP_NTZ,
    last_activity TIMESTAMP_NTZ,

    -- Status
    is_active BOOLEAN DEFAULT TRUE,
    mfa_enabled BOOLEAN DEFAULT FALSE,

    -- Metadata
    user_metadata VARIANT,

    PRIMARY KEY (tenant_id, username),
    CONSTRAINT fk_tenant FOREIGN KEY (tenant_id)
        REFERENCES tenants(tenant_id) NOT ENFORCED
)
COMMENT = 'User access tracking per tenant. Tracks all users with access to tenant data.';

-- ============================================================================
-- 5. Create Device Registry
-- ============================================================================

SELECT '5. Creating Device Registry...' AS step;

CREATE TABLE IF NOT EXISTS devices (
    -- Primary identifiers
    device_id VARCHAR(255) PRIMARY KEY,
    tenant_id VARCHAR(100) NOT NULL,
    site_id VARCHAR(100),

    -- Device information
    device_type VARCHAR(100),
    device_name VARCHAR(500),
    device_model VARCHAR(255),
    firmware_version VARCHAR(50),

    -- IoT Core details
    iot_thing_name VARCHAR(255),
    iot_thing_arn VARCHAR(500),
    certificate_id VARCHAR(255),
    certificate_arn VARCHAR(500),
    certificate_expiry TIMESTAMP_NTZ,

    -- Thing Group membership (for hierarchical management)
    site_thing_group_name VARCHAR(255),
    tenant_thing_group_name VARCHAR(255),
    thing_group_memberships ARRAY,  -- Array of all thing groups this device belongs to

    -- Status tracking
    status VARCHAR(50) DEFAULT 'active',
    deployed_date TIMESTAMP_NTZ,
    last_connection TIMESTAMP_NTZ,
    last_message_timestamp TIMESTAMP_NTZ,
    connection_count NUMBER(20) DEFAULT 0,
    total_messages NUMBER(20) DEFAULT 0,

    -- Physical location
    location_name VARCHAR(500),
    latitude FLOAT,
    longitude FLOAT,

    -- Metadata
    configuration VARIANT,
    metadata VARIANT,

    CONSTRAINT fk_device_tenant FOREIGN KEY (tenant_id)
        REFERENCES tenants(tenant_id) NOT ENFORCED,
    CONSTRAINT fk_device_site FOREIGN KEY (site_id)
        REFERENCES sites(site_id) NOT ENFORCED

    -- Note: Snowflake does not support CHECK constraints
    -- Valid values for status: 'provisioning', 'active', 'maintenance', 'decommissioned'
)
COMMENT = 'Registry of all IoT devices and gateways. Tracks device lifecycle, certificates, thing groups, and connectivity.';

-- ============================================================================
-- 6. Create Site Registry
-- ============================================================================

SELECT '6. Creating Site Registry...' AS step;

CREATE TABLE IF NOT EXISTS sites (
    site_id VARCHAR(100) PRIMARY KEY,
    tenant_id VARCHAR(100) NOT NULL,

    -- Site information
    site_name VARCHAR(500) NOT NULL,
    site_type VARCHAR(100),

    -- AWS IoT Thing Group for site (all devices at this site)
    site_thing_group_name VARCHAR(255),
    site_thing_group_arn VARCHAR(500),

    -- Location
    address VARCHAR(1000),
    city VARCHAR(255),
    country VARCHAR(100),
    postal_code VARCHAR(50),
    latitude FLOAT,
    longitude FLOAT,
    timezone VARCHAR(100),

    -- Status
    status VARCHAR(50) DEFAULT 'active',
    created_date TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    activated_date TIMESTAMP_NTZ,

    -- Device counts (synced from AWS IoT)
    total_devices NUMBER(10) DEFAULT 0,
    active_devices NUMBER(10) DEFAULT 0,
    last_device_sync TIMESTAMP_NTZ,

    -- Metadata
    site_metadata VARIANT,

    CONSTRAINT fk_site_tenant FOREIGN KEY (tenant_id)
        REFERENCES tenants(tenant_id) NOT ENFORCED

    -- Note: Snowflake does not support CHECK constraints
    -- Valid values for status: 'provisioning', 'active', 'suspended', 'decommissioned'
)
COMMENT = 'Registry of manufacturing sites per tenant. Tracks site locations, thing groups, and device counts.';

-- ============================================================================
-- 7. Create Data Ingestion Tracking
-- ============================================================================

SELECT '7. Creating Ingestion Metrics Table...' AS step;

USE SCHEMA monitoring;

CREATE TABLE IF NOT EXISTS ingestion_metrics (
    metric_id VARCHAR(255) DEFAULT UUID_STRING(),
    tenant_id VARCHAR(100) NOT NULL,
    timestamp TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),

    -- Ingestion metrics
    messages_received NUMBER(20) DEFAULT 0,
    messages_processed NUMBER(20) DEFAULT 0,
    messages_failed NUMBER(20) DEFAULT 0,
    bytes_ingested NUMBER(20) DEFAULT 0,

    -- Latency metrics (milliseconds)
    avg_latency_ms FLOAT,
    p95_latency_ms FLOAT,
    p99_latency_ms FLOAT,

    -- Source breakdown
    mqtt_messages NUMBER(20) DEFAULT 0,
    file_uploads NUMBER(20) DEFAULT 0,
    api_requests NUMBER(20) DEFAULT 0,

    PRIMARY KEY (tenant_id, timestamp)
)
CLUSTER BY (DATE_TRUNC('day', timestamp), tenant_id)
COMMENT = 'Platform ingestion metrics per tenant. Captured every 5 minutes for monitoring dashboards.';

-- ============================================================================
-- 8. Create Task Execution Log
-- ============================================================================

SELECT '8. Creating Task Execution Log...' AS step;

CREATE TABLE IF NOT EXISTS task_execution_log (
    execution_id VARCHAR(255) DEFAULT UUID_STRING(),
    tenant_id VARCHAR(100) NOT NULL,
    task_name VARCHAR(500) NOT NULL,

    -- Execution details
    start_time TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    end_time TIMESTAMP_NTZ,
    duration_seconds FLOAT,
    status VARCHAR(50),

    -- Execution statistics
    rows_processed NUMBER(20),
    rows_inserted NUMBER(20),
    rows_updated NUMBER(20),
    rows_deleted NUMBER(20),
    error_count NUMBER(10),

    -- Error details
    error_message VARCHAR(5000),
    error_stack_trace VARCHAR(16777216),

    -- Metadata
    execution_metadata VARIANT,

    PRIMARY KEY (execution_id)
)
CLUSTER BY (DATE_TRUNC('day', start_time), tenant_id)
COMMENT = 'Log of all task executions across tenants. Used for debugging and performance monitoring.';

-- ============================================================================
-- 9. Create Alert Log
-- ============================================================================

SELECT '9. Creating Alert Log...' AS step;

CREATE TABLE IF NOT EXISTS alerts (
    alert_id VARCHAR(255) DEFAULT UUID_STRING(),
    tenant_id VARCHAR(100),
    alert_timestamp TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),

    -- Alert details
    alert_type VARCHAR(100) NOT NULL,
    severity VARCHAR(50) NOT NULL,
    title VARCHAR(500) NOT NULL,
    description VARCHAR(5000),

    -- Source
    source_component VARCHAR(255),
    source_metric VARCHAR(255),

    -- Status
    status VARCHAR(50) DEFAULT 'open',
    acknowledged_by VARCHAR(255),
    acknowledged_at TIMESTAMP_NTZ,
    resolved_by VARCHAR(255),
    resolved_at TIMESTAMP_NTZ,

    -- Metadata
    alert_metadata VARIANT,

    PRIMARY KEY (alert_id)

    -- Note: Snowflake does not support CHECK constraints
    -- Valid values for severity: 'critical', 'high', 'medium', 'low', 'info'
    -- Valid values for status: 'open', 'acknowledged', 'resolved', 'false_positive'
)
CLUSTER BY (DATE_TRUNC('day', alert_timestamp), severity)
COMMENT = 'Log of all platform alerts and incidents. Tracks alert lifecycle from detection to resolution.';

-- ============================================================================
-- 10. Create Audit Log Tables
-- ============================================================================

SELECT '10. Creating Audit Log Tables...' AS step;

USE SCHEMA audit;

-- User access audit log
CREATE TABLE IF NOT EXISTS user_access_log (
    log_id VARCHAR(255) DEFAULT UUID_STRING(),
    tenant_id VARCHAR(100),
    username VARCHAR(255) NOT NULL,

    -- Access details
    access_timestamp TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    action VARCHAR(255) NOT NULL,
    resource_type VARCHAR(100),
    resource_id VARCHAR(500),

    -- Context
    ip_address VARCHAR(50),
    user_agent VARCHAR(1000),
    session_id VARCHAR(255),

    -- Result
    status VARCHAR(50),
    error_message VARCHAR(5000),

    PRIMARY KEY (log_id)
)
CLUSTER BY (DATE_TRUNC('day', access_timestamp), tenant_id)
COMMENT = 'Audit log of all user access to tenant data. Retained for 90 days for compliance.';

-- Data modification audit log
CREATE TABLE IF NOT EXISTS data_modification_log (
    log_id VARCHAR(255) DEFAULT UUID_STRING(),
    tenant_id VARCHAR(100) NOT NULL,

    -- Modification details
    modification_timestamp TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    database_name VARCHAR(255),
    schema_name VARCHAR(255),
    table_name VARCHAR(255),
    operation VARCHAR(50),

    -- Changes
    rows_affected NUMBER(20),
    modified_by VARCHAR(255),
    query_id VARCHAR(255),

    -- Context
    modification_metadata VARIANT,

    PRIMARY KEY (log_id)

    -- Note: Snowflake does not support CHECK constraints
    -- Valid values for operation: 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'MERGE'
)
CLUSTER BY (DATE_TRUNC('day', modification_timestamp), tenant_id)
COMMENT = 'Audit log of all data modifications. Tracks who changed what data and when.';

-- ============================================================================
-- 11. Create Infrastructure Admin Role
-- ============================================================================

SELECT '11. Creating Infrastructure Admin Role...' AS step;

USE ROLE ACCOUNTADMIN;

CREATE ROLE IF NOT EXISTS smdh_infrastructure_admin
    COMMENT = 'Admin role for SMDH platform management. Has full access to infrastructure database.';

-- Grant privileges on infrastructure database
GRANT ALL ON DATABASE smdh_infrastructure TO ROLE smdh_infrastructure_admin;
GRANT ALL ON ALL SCHEMAS IN DATABASE smdh_infrastructure TO ROLE smdh_infrastructure_admin;
GRANT ALL ON ALL TABLES IN DATABASE smdh_infrastructure TO ROLE smdh_infrastructure_admin;
GRANT ALL ON FUTURE TABLES IN DATABASE smdh_infrastructure TO ROLE smdh_infrastructure_admin;
GRANT ALL ON FUTURE VIEWS IN DATABASE smdh_infrastructure TO ROLE smdh_infrastructure_admin;

-- Grant role to SYSADMIN (follows Snowflake role hierarchy best practice)
GRANT ROLE smdh_infrastructure_admin TO ROLE SYSADMIN;

-- ============================================================================
-- 12. Create Read-Only Monitoring Role
-- ============================================================================

SELECT '12. Creating Monitoring Role...' AS step;

CREATE ROLE IF NOT EXISTS smdh_monitoring
    COMMENT = 'Read-only role for monitoring and observability tools.';

-- Grant read access to monitoring schema
GRANT USAGE ON DATABASE smdh_infrastructure TO ROLE smdh_monitoring;
GRANT USAGE ON SCHEMA smdh_infrastructure.monitoring TO ROLE smdh_monitoring;
GRANT USAGE ON SCHEMA smdh_infrastructure.tenant_configs TO ROLE smdh_monitoring;
GRANT SELECT ON ALL TABLES IN SCHEMA smdh_infrastructure.monitoring TO ROLE smdh_monitoring;
GRANT SELECT ON FUTURE TABLES IN SCHEMA smdh_infrastructure.monitoring TO ROLE smdh_monitoring;
GRANT SELECT ON ALL VIEWS IN SCHEMA smdh_infrastructure.monitoring TO ROLE smdh_monitoring;
GRANT SELECT ON FUTURE VIEWS IN SCHEMA smdh_infrastructure.monitoring TO ROLE smdh_monitoring;

-- Grant tenant metadata read access (for dashboards)
GRANT SELECT ON smdh_infrastructure.tenant_configs.tenants TO ROLE smdh_monitoring;
GRANT SELECT ON smdh_infrastructure.tenant_configs.devices TO ROLE smdh_monitoring;
GRANT SELECT ON smdh_infrastructure.tenant_configs.sites TO ROLE smdh_monitoring;

GRANT ROLE smdh_monitoring TO ROLE SYSADMIN;

-- ============================================================================
-- 13. Create Initial Monitoring Views
-- ============================================================================

SELECT '13. Creating Monitoring Views...' AS step;

USE SCHEMA monitoring;

-- Active tenants view
CREATE OR REPLACE VIEW v_active_tenants AS
SELECT
    tenant_id,
    tenant_name,
    status,
    num_sites,
    num_sensors,
    aws_region,
    created_date,
    activated_date,
    contact_email
FROM smdh_infrastructure.tenant_configs.tenants
WHERE status = 'active'
ORDER BY tenant_name;

GRANT SELECT ON v_active_tenants TO ROLE smdh_monitoring;

-- Device connectivity summary
CREATE OR REPLACE VIEW v_device_connectivity AS
SELECT
    d.tenant_id,
    t.tenant_name,
    COUNT(*) AS total_devices,
    SUM(CASE WHEN d.status = 'active' THEN 1 ELSE 0 END) AS active_devices,
    SUM(CASE WHEN d.last_connection > DATEADD(hour, -1, CURRENT_TIMESTAMP()) THEN 1 ELSE 0 END) AS recently_connected,
    MAX(d.last_connection) AS last_device_connection,
    SUM(d.total_messages) AS total_messages
FROM smdh_infrastructure.tenant_configs.devices d
JOIN smdh_infrastructure.tenant_configs.tenants t ON d.tenant_id = t.tenant_id
GROUP BY d.tenant_id, t.tenant_name
ORDER BY t.tenant_name;

GRANT SELECT ON v_device_connectivity TO ROLE smdh_monitoring;

-- Site-level device summary (leverages thing groups)
CREATE OR REPLACE VIEW v_site_device_summary AS
SELECT
    s.tenant_id,
    t.tenant_name,
    s.site_id,
    s.site_name,
    s.site_thing_group_name,
    s.site_thing_group_arn,
    COUNT(d.device_id) AS total_devices,
    SUM(CASE WHEN d.status = 'active' THEN 1 ELSE 0 END) AS active_devices,
    SUM(CASE WHEN d.last_connection > DATEADD(hour, -1, CURRENT_TIMESTAMP()) THEN 1 ELSE 0 END) AS recently_connected,
    SUM(CASE WHEN d.last_connection < DATEADD(day, -1, CURRENT_TIMESTAMP()) OR d.last_connection IS NULL THEN 1 ELSE 0 END) AS disconnected_devices,
    MAX(d.last_connection) AS last_device_connection,
    SUM(d.total_messages) AS total_messages_from_site,
    s.status AS site_status,
    s.city,
    s.country
FROM smdh_infrastructure.tenant_configs.sites s
JOIN smdh_infrastructure.tenant_configs.tenants t ON s.tenant_id = t.tenant_id
LEFT JOIN smdh_infrastructure.tenant_configs.devices d ON s.site_id = d.site_id
GROUP BY s.tenant_id, t.tenant_name, s.site_id, s.site_name, s.site_thing_group_name,
         s.site_thing_group_arn, s.status, s.city, s.country
ORDER BY t.tenant_name, s.site_name;

GRANT SELECT ON v_site_device_summary TO ROLE smdh_monitoring;

-- Thing group hierarchy view
CREATE OR REPLACE VIEW v_thing_group_hierarchy AS
SELECT
    t.tenant_id,
    t.tenant_name,
    t.tenant_thing_group_name AS tenant_group,
    COUNT(DISTINCT s.site_id) AS num_sites,
    COUNT(DISTINCT d.device_id) AS total_devices,
    SUM(CASE WHEN d.status = 'active' THEN 1 ELSE 0 END) AS active_devices,
    SUM(CASE WHEN d.last_connection > DATEADD(hour, -1, CURRENT_TIMESTAMP()) THEN 1 ELSE 0 END) AS connected_devices,
    MAX(d.last_connection) AS last_device_activity,
    SUM(d.total_messages) AS total_platform_messages
FROM smdh_infrastructure.tenant_configs.tenants t
LEFT JOIN smdh_infrastructure.tenant_configs.sites s ON t.tenant_id = s.tenant_id
LEFT JOIN smdh_infrastructure.tenant_configs.devices d ON s.site_id = d.site_id
GROUP BY t.tenant_id, t.tenant_name, t.tenant_thing_group_name
ORDER BY t.tenant_name;

GRANT SELECT ON v_thing_group_hierarchy TO ROLE smdh_monitoring;

-- Disconnected devices alert view (mirrors AWS IoT dynamic group)
CREATE OR REPLACE VIEW v_disconnected_devices AS
SELECT
    d.device_id,
    d.tenant_id,
    t.tenant_name,
    d.site_id,
    s.site_name,
    d.device_name,
    d.iot_thing_name,
    d.site_thing_group_name,
    d.last_connection,
    DATEDIFF(hour, d.last_connection, CURRENT_TIMESTAMP()) AS hours_since_last_connection,
    d.status,
    d.certificate_expiry
FROM smdh_infrastructure.tenant_configs.devices d
JOIN smdh_infrastructure.tenant_configs.tenants t ON d.tenant_id = t.tenant_id
LEFT JOIN smdh_infrastructure.tenant_configs.sites s ON d.site_id = s.site_id
WHERE (d.last_connection < DATEADD(day, -1, CURRENT_TIMESTAMP()) OR d.last_connection IS NULL)
  AND d.status = 'active'
ORDER BY d.last_connection ASC NULLS FIRST;

GRANT SELECT ON v_disconnected_devices TO ROLE smdh_monitoring;

-- Certificate expiry monitoring
CREATE OR REPLACE VIEW v_certificate_expiry_alerts AS
SELECT
    d.device_id,
    d.tenant_id,
    t.tenant_name,
    d.site_id,
    s.site_name,
    d.device_name,
    d.iot_thing_name,
    d.certificate_id,
    d.certificate_expiry,
    DATEDIFF(day, CURRENT_TIMESTAMP(), d.certificate_expiry) AS days_until_expiry,
    CASE
        WHEN DATEDIFF(day, CURRENT_TIMESTAMP(), d.certificate_expiry) < 7 THEN 'critical'
        WHEN DATEDIFF(day, CURRENT_TIMESTAMP(), d.certificate_expiry) < 30 THEN 'warning'
        ELSE 'ok'
    END AS expiry_status
FROM smdh_infrastructure.tenant_configs.devices d
JOIN smdh_infrastructure.tenant_configs.tenants t ON d.tenant_id = t.tenant_id
LEFT JOIN smdh_infrastructure.tenant_configs.sites s ON d.site_id = s.site_id
WHERE d.certificate_expiry IS NOT NULL
  AND d.certificate_expiry < DATEADD(day, 30, CURRENT_TIMESTAMP())
  AND d.status IN ('active', 'maintenance')
ORDER BY d.certificate_expiry ASC;

GRANT SELECT ON v_certificate_expiry_alerts TO ROLE smdh_monitoring;

-- ============================================================================
-- 14. Verification
-- ============================================================================

SELECT '14. Verifying Infrastructure Setup...' AS step;

-- Verify databases
SELECT 'Databases created:' AS verification;
SHOW DATABASES LIKE 'smdh_infrastructure';

-- Verify schemas
SELECT 'Schemas created:' AS verification;
USE DATABASE smdh_infrastructure;
SHOW SCHEMAS;

-- Verify tables
SELECT 'Tables in tenant_configs:' AS verification;
USE SCHEMA tenant_configs;
SHOW TABLES;

SELECT 'Tables in monitoring:' AS verification;
USE SCHEMA monitoring;
SHOW TABLES;

SELECT 'Tables in audit:' AS verification;
USE SCHEMA audit;
SHOW TABLES;

-- Verify roles
SELECT 'Roles created:' AS verification;
SHOW ROLES LIKE 'smdh_%';

-- ============================================================================
-- 15. Summary
-- ============================================================================

SELECT '╔════════════════════════════════════════════════════════════════╗' AS summary
UNION ALL SELECT '║  SMDH Infrastructure Setup Complete                        ║'
UNION ALL SELECT '╚════════════════════════════════════════════════════════════╝'
UNION ALL SELECT ''
UNION ALL SELECT 'Created Resources:'
UNION ALL SELECT '  ✓ Database: smdh_infrastructure'
UNION ALL SELECT '  ✓ Schemas: tenant_configs, monitoring, audit'
UNION ALL SELECT '  ✓ Tables:'
UNION ALL SELECT '      • tenants (with thing group tracking)'
UNION ALL SELECT '      • sites (with site thing group tracking)'
UNION ALL SELECT '      • devices (with thing group memberships)'
UNION ALL SELECT '      • tenant_users, ingestion_metrics, task_execution_log, alerts'
UNION ALL SELECT '      • user_access_log, data_modification_log'
UNION ALL SELECT '  ✓ Roles: smdh_infrastructure_admin, smdh_monitoring'
UNION ALL SELECT '  ✓ Monitoring Views:'
UNION ALL SELECT '      • v_active_tenants - Active tenant summary'
UNION ALL SELECT '      • v_device_connectivity - Device connectivity overview'
UNION ALL SELECT '      • v_site_device_summary - Site-level metrics (uses thing groups)'
UNION ALL SELECT '      • v_thing_group_hierarchy - Thing group structure and stats'
UNION ALL SELECT '      • v_disconnected_devices - Devices needing attention'
UNION ALL SELECT '      • v_certificate_expiry_alerts - Certificate expiry warnings'
UNION ALL SELECT ''
UNION ALL SELECT 'AWS IoT Integration:'
UNION ALL SELECT '  • Thing Groups: Tracked at tenant and site levels'
UNION ALL SELECT '  • Dynamic Sync: Use scripts/sync_aws_iot_metadata.sh to sync AWS state'
UNION ALL SELECT ''
UNION ALL SELECT 'Next Steps:'
UNION ALL SELECT '  1. Run 02_shared_resources.sql to create warehouses'
UNION ALL SELECT '  2. Run 03_openflow_connector.sql to configure Kinesis integration'
UNION ALL SELECT '  3. Deploy AWS infrastructure with Terraform'
UNION ALL SELECT '  4. Run scripts/sync_aws_iot_metadata.sh to populate thing groups'
UNION ALL SELECT '  5. Use tenant/*.sql scripts to onboard your first tenant'
UNION ALL SELECT ''
UNION ALL SELECT 'Documentation: See infrastructure/snowflake/README.md'
UNION ALL SELECT '                and infrastructure/terraform/THING_GROUPS_GUIDE.md'
UNION ALL SELECT '============================================================';
