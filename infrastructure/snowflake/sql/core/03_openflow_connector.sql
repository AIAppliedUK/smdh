-- ============================================================================
-- SMDH Snowflake Openflow Setup (Kinesis Integration)
-- ============================================================================
-- Purpose: Configure Snowflake Openflow for native Kinesis Data Stream ingestion
-- Usage: snowsql -f 03_openflow_connector.sql
-- Author: SMDH Platform Team
-- Version: 2.0
-- ============================================================================
-- Prerequisites:
-- 1. ACCOUNTADMIN role access
-- 2. SMDH_WH warehouse created (from 02_shared_resources.sql)
-- 3. smdh_infrastructure database created (from 01_infrastructure_setup.sql)
-- ============================================================================
-- This script creates:
-- - OPENFLOW_ADMIN role with required privileges
-- - SMDH_OPENFLOW database, schema, and image repository
-- - Network rules for AWS Kinesis/DynamoDB access
-- - External access integration for Openflow
-- - Runtime roles for Kinesis connector
-- - Tracking table for Openflow connectors
-- ============================================================================
-- IMPORTANT: After running this script, complete these UI steps in Snowsight:
-- 1. Navigate to Data > Openflow
-- 2. Create a new Deployment
-- 3. Create a Runtime using OPENFLOW_RUNTIME_ROLE_KINESIS
-- 4. Add the Kinesis connector and configure stream parameters
-- See: docs/deployment/Tenant_Onboarding_Guide.md
-- ============================================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE SMDH_WH;

-- Display banner
SELECT '╔════════════════════════════════════════════════════════════════╗' AS banner
UNION ALL SELECT '║  SMDH Platform - Openflow Kinesis Connector Setup (v2.0)    ║'
UNION ALL SELECT '╚════════════════════════════════════════════════════════════════╝';

-- ============================================================================
-- 1. Create Openflow Admin Role
-- ============================================================================

SELECT '1. Creating Openflow Admin Role...' AS step;

-- Create the main Openflow admin role
CREATE ROLE IF NOT EXISTS OPENFLOW_ADMIN
    COMMENT = 'Administrator role for Snowflake Openflow deployments and runtimes';

-- Grant ability to create roles (needed for runtime roles)
GRANT CREATE ROLE ON ACCOUNT TO ROLE OPENFLOW_ADMIN;

-- Grant Openflow-specific privileges
GRANT CREATE OPENFLOW DATA PLANE INTEGRATION ON ACCOUNT TO ROLE OPENFLOW_ADMIN;
GRANT CREATE OPENFLOW RUNTIME INTEGRATION ON ACCOUNT TO ROLE OPENFLOW_ADMIN;

-- Grant warehouse access
GRANT USAGE ON WAREHOUSE SMDH_WH TO ROLE OPENFLOW_ADMIN;

-- Grant to current user (adjust as needed)
-- Note: Replace with appropriate user or role hierarchy
GRANT ROLE OPENFLOW_ADMIN TO ROLE ACCOUNTADMIN;

SELECT 'Created role: OPENFLOW_ADMIN' AS status;

-- ============================================================================
-- 2. Create Openflow Database and Image Repository
-- ============================================================================

SELECT '2. Creating Openflow Database and Image Repository...' AS step;

-- Create Openflow database (required for image repository)
CREATE DATABASE IF NOT EXISTS SMDH_OPENFLOW
    DATA_RETENTION_TIME_IN_DAYS = 7
    COMMENT = 'Snowflake Openflow configuration and image repository';

USE DATABASE SMDH_OPENFLOW;

-- Create schema
CREATE SCHEMA IF NOT EXISTS OPENFLOW
    COMMENT = 'Openflow image repository and configuration';

USE SCHEMA OPENFLOW;

-- Create image repository (required for Snowflake Deployments)
CREATE IMAGE REPOSITORY IF NOT EXISTS OPENFLOW
    COMMENT = 'Container image repository for Openflow connectors';

-- Grant public access to image repository (required for Openflow)
GRANT USAGE ON DATABASE SMDH_OPENFLOW TO ROLE PUBLIC;
GRANT USAGE ON SCHEMA SMDH_OPENFLOW.OPENFLOW TO ROLE PUBLIC;
GRANT READ ON IMAGE REPOSITORY SMDH_OPENFLOW.OPENFLOW.OPENFLOW TO ROLE PUBLIC;

SELECT 'Created database: SMDH_OPENFLOW with image repository' AS status;

-- ============================================================================
-- 3. Create Network Rules for AWS Access
-- ============================================================================

SELECT '3. Creating Network Rules for AWS Kinesis/DynamoDB Access...' AS step;

USE DATABASE SMDH_OPENFLOW;
USE SCHEMA OPENFLOW;

-- Network rule for AWS Kinesis and DynamoDB access (eu-west-2)
-- Openflow uses DynamoDB for checkpointing Kinesis stream position
CREATE OR REPLACE NETWORK RULE OPENFLOW_AWS_EU_WEST_2_RULE
    MODE = EGRESS
    TYPE = HOST_PORT
    VALUE_LIST = (
        'kinesis.eu-west-2.amazonaws.com:443',
        'dynamodb.eu-west-2.amazonaws.com:443',
        'sts.eu-west-2.amazonaws.com:443',
        'sts.amazonaws.com:443'
    )
    COMMENT = 'Network rule for Openflow to access AWS Kinesis and DynamoDB in eu-west-2';

-- Create external access integration
CREATE OR REPLACE EXTERNAL ACCESS INTEGRATION OPENFLOW_AWS_EAI
    ALLOWED_NETWORK_RULES = (SMDH_OPENFLOW.OPENFLOW.OPENFLOW_AWS_EU_WEST_2_RULE)
    ENABLED = TRUE
    COMMENT = 'External access integration for Openflow AWS connectivity';

SELECT 'Created network rule: OPENFLOW_AWS_EU_WEST_2_RULE' AS status;
SELECT 'Created external access integration: OPENFLOW_AWS_EAI' AS status;

-- Grant admin access (AFTER creating network rules and integration)
GRANT OWNERSHIP ON DATABASE SMDH_OPENFLOW TO ROLE OPENFLOW_ADMIN COPY CURRENT GRANTS;
GRANT OWNERSHIP ON SCHEMA SMDH_OPENFLOW.OPENFLOW TO ROLE OPENFLOW_ADMIN COPY CURRENT GRANTS;

-- ============================================================================
-- 4. Create Runtime Role for Kinesis Connector
-- ============================================================================

SELECT '4. Creating Runtime Role for Kinesis Connector...' AS step;

USE ROLE OPENFLOW_ADMIN;

-- Create runtime role specifically for Kinesis ingestion
CREATE ROLE IF NOT EXISTS OPENFLOW_RUNTIME_ROLE_KINESIS
    COMMENT = 'Runtime role for Openflow Kinesis connector - ingests sensor data';

-- Grant role to admin
GRANT ROLE OPENFLOW_RUNTIME_ROLE_KINESIS TO ROLE OPENFLOW_ADMIN;

-- Switch back to accountadmin for grants
USE ROLE ACCOUNTADMIN;

-- Grant warehouse access
GRANT USAGE, OPERATE ON WAREHOUSE SMDH_WH TO ROLE OPENFLOW_RUNTIME_ROLE_KINESIS;

-- Grant access to Openflow database/schema
GRANT USAGE ON DATABASE SMDH_OPENFLOW TO ROLE OPENFLOW_RUNTIME_ROLE_KINESIS;
GRANT USAGE ON SCHEMA SMDH_OPENFLOW.OPENFLOW TO ROLE OPENFLOW_RUNTIME_ROLE_KINESIS;

-- Grant external access integration
GRANT USAGE ON INTEGRATION OPENFLOW_AWS_EAI TO ROLE OPENFLOW_RUNTIME_ROLE_KINESIS;

-- Grant access to infrastructure database for connector tracking
GRANT USAGE ON DATABASE SMDH_INFRASTRUCTURE TO ROLE OPENFLOW_RUNTIME_ROLE_KINESIS;
GRANT USAGE ON SCHEMA SMDH_INFRASTRUCTURE.TENANT_CONFIGS TO ROLE OPENFLOW_RUNTIME_ROLE_KINESIS;
GRANT SELECT ON TABLE SMDH_INFRASTRUCTURE.TENANT_CONFIGS.TENANTS TO ROLE OPENFLOW_RUNTIME_ROLE_KINESIS;

SELECT 'Created role: OPENFLOW_RUNTIME_ROLE_KINESIS' AS status;

-- ============================================================================
-- 5. Create Stored Procedure to Grant Tenant Database Access
-- ============================================================================

SELECT '5. Creating Procedure to Grant Tenant Access...' AS step;

USE DATABASE SMDH_INFRASTRUCTURE;
USE SCHEMA TENANT_CONFIGS;

-- Procedure to grant Openflow access to a tenant database
-- Call this when onboarding a new tenant
CREATE OR REPLACE PROCEDURE sp_grant_openflow_tenant_access(tenant_id_param VARCHAR)
RETURNS STRING
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    db_name VARCHAR;
    grant_sql VARCHAR;
BEGIN
    -- Construct database name
    db_name := 'SMDH_TENANT_' || UPPER(:tenant_id_param);

    -- Grant database usage
    grant_sql := 'GRANT USAGE ON DATABASE ' || db_name || ' TO ROLE OPENFLOW_RUNTIME_ROLE_KINESIS';
    EXECUTE IMMEDIATE grant_sql;

    -- Grant schema usage
    grant_sql := 'GRANT USAGE ON SCHEMA ' || db_name || '.RAW TO ROLE OPENFLOW_RUNTIME_ROLE_KINESIS';
    EXECUTE IMMEDIATE grant_sql;

    -- Grant CREATE TABLE (Openflow auto-creates destination tables named after Kinesis stream)
    grant_sql := 'GRANT CREATE TABLE ON SCHEMA ' || db_name || '.RAW TO ROLE OPENFLOW_RUNTIME_ROLE_KINESIS';
    EXECUTE IMMEDIATE grant_sql;

    -- Grant table permissions (INSERT for ingestion, SELECT for validation)
    grant_sql := 'GRANT INSERT, SELECT ON ALL TABLES IN SCHEMA ' || db_name || '.RAW TO ROLE OPENFLOW_RUNTIME_ROLE_KINESIS';
    EXECUTE IMMEDIATE grant_sql;

    -- Grant on future tables
    grant_sql := 'GRANT INSERT, SELECT ON FUTURE TABLES IN SCHEMA ' || db_name || '.RAW TO ROLE OPENFLOW_RUNTIME_ROLE_KINESIS';
    EXECUTE IMMEDIATE grant_sql;

    RETURN 'Granted Openflow access to database: ' || db_name;
END;
$$;

GRANT USAGE ON PROCEDURE sp_grant_openflow_tenant_access(VARCHAR) TO ROLE OPENFLOW_ADMIN;

SELECT 'Created procedure: sp_grant_openflow_tenant_access' AS status;

-- ============================================================================
-- 6. Create Openflow Connector Tracking Table
-- ============================================================================

SELECT '6. Creating Openflow Connector Tracking Table...' AS step;

USE DATABASE SMDH_INFRASTRUCTURE;
USE SCHEMA TENANT_CONFIGS;

CREATE TABLE IF NOT EXISTS openflow_connectors (
    -- Primary key
    connector_id VARCHAR(255) DEFAULT UUID_STRING() PRIMARY KEY,

    -- Tenant association
    tenant_id VARCHAR(100) NOT NULL,

    -- Connector details
    connector_name VARCHAR(255) NOT NULL,
    connector_type VARCHAR(50) DEFAULT 'KINESIS',

    -- Target table details
    target_database VARCHAR(255) NOT NULL,
    target_schema VARCHAR(255) NOT NULL,
    target_table VARCHAR(255) NOT NULL,

    -- AWS Kinesis details
    kinesis_stream_name VARCHAR(255) NOT NULL,
    kinesis_stream_arn VARCHAR(500),
    aws_region VARCHAR(50) DEFAULT 'eu-west-2',

    -- Openflow runtime details
    runtime_name VARCHAR(255),
    deployment_name VARCHAR(255),

    -- Status tracking
    status VARCHAR(50) DEFAULT 'pending',
    created_date TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    activated_date TIMESTAMP_NTZ,
    last_health_check TIMESTAMP_NTZ,

    -- Metrics
    total_records_ingested NUMBER(20) DEFAULT 0,
    last_ingestion_timestamp TIMESTAMP_NTZ,
    error_count NUMBER(10) DEFAULT 0,
    last_error_message VARCHAR(2000),

    -- Configuration (JSON)
    configuration VARIANT,

    -- Foreign key (not enforced)
    CONSTRAINT fk_connector_tenant FOREIGN KEY (tenant_id)
        REFERENCES tenants(tenant_id) NOT ENFORCED
)
COMMENT = 'Registry of Snowflake Openflow connectors. Tracks Kinesis stream to Snowflake table mappings per tenant.';

-- Create index-like clustering for common queries
ALTER TABLE openflow_connectors CLUSTER BY (tenant_id, status);

SELECT 'Created table: openflow_connectors' AS status;

-- ============================================================================
-- 7. Create Monitoring Views
-- ============================================================================

SELECT '7. Creating Monitoring Views...' AS step;

USE SCHEMA MONITORING;

-- View for Openflow connector status
CREATE OR REPLACE VIEW v_openflow_connector_status AS
SELECT
    oc.connector_id,
    oc.tenant_id,
    t.tenant_name,
    oc.connector_name,
    oc.kinesis_stream_name,
    oc.target_database || '.' || oc.target_schema || '.' || oc.target_table AS target_table,
    oc.status,
    oc.total_records_ingested,
    oc.last_ingestion_timestamp,
    DATEDIFF(MINUTE, oc.last_ingestion_timestamp, CURRENT_TIMESTAMP()) AS minutes_since_last_ingestion,
    oc.error_count,
    oc.last_error_message,
    oc.created_date,
    oc.activated_date
FROM tenant_configs.openflow_connectors oc
LEFT JOIN tenant_configs.tenants t ON oc.tenant_id = t.tenant_id
ORDER BY oc.tenant_id, oc.connector_name;

GRANT SELECT ON VIEW v_openflow_connector_status TO ROLE OPENFLOW_ADMIN;

-- View for connector health summary
CREATE OR REPLACE VIEW v_openflow_health_summary AS
SELECT
    status,
    COUNT(*) AS connector_count,
    SUM(total_records_ingested) AS total_records,
    SUM(error_count) AS total_errors,
    MAX(last_ingestion_timestamp) AS most_recent_ingestion
FROM tenant_configs.openflow_connectors
GROUP BY status;

GRANT SELECT ON VIEW v_openflow_health_summary TO ROLE OPENFLOW_ADMIN;

SELECT 'Created monitoring views' AS status;

-- NOTE: Per-tenant Openflow access is granted in tenant/13_create_streams.sql
-- via: CALL smdh_infrastructure.tenant_configs.sp_grant_openflow_tenant_access($tenant_id);

-- ============================================================================
-- 8. Verification
-- ============================================================================

SELECT '8. Verifying Openflow Setup...' AS step;

-- Check roles
SELECT 'Openflow Roles:' AS verification;
SHOW ROLES LIKE '%OPENFLOW%';

-- Check database
SELECT 'Openflow Database:' AS verification;
SHOW DATABASES LIKE 'SMDH_OPENFLOW';

-- Check network rules
SELECT 'Network Rules:' AS verification;
USE DATABASE SMDH_OPENFLOW;
SHOW NETWORK RULES;

-- Check external access integration
SELECT 'External Access Integrations:' AS verification;
SHOW EXTERNAL ACCESS INTEGRATIONS LIKE 'OPENFLOW%';

-- Check tracking table
SELECT 'Connector Tracking Table:' AS verification;
DESC TABLE SMDH_INFRASTRUCTURE.TENANT_CONFIGS.OPENFLOW_CONNECTORS;

-- ============================================================================
-- 10. Summary and Next Steps
-- ============================================================================

SELECT '╔════════════════════════════════════════════════════════════════╗' AS summary
UNION ALL SELECT '║  SMDH Openflow Setup Complete (SQL Configuration)            ║'
UNION ALL SELECT '╚════════════════════════════════════════════════════════════════╝'
UNION ALL SELECT ''
UNION ALL SELECT 'Created Resources:'
UNION ALL SELECT '  [OK] Role: OPENFLOW_ADMIN'
UNION ALL SELECT '  [OK] Role: OPENFLOW_RUNTIME_ROLE_KINESIS'
UNION ALL SELECT '  [OK] Database: SMDH_OPENFLOW (with image repository)'
UNION ALL SELECT '  [OK] Network Rule: OPENFLOW_AWS_EU_WEST_2_RULE'
UNION ALL SELECT '  [OK] External Access Integration: OPENFLOW_AWS_EAI'
UNION ALL SELECT '  [OK] Table: openflow_connectors (tracking)'
UNION ALL SELECT '  [OK] Procedure: sp_grant_openflow_tenant_access'
UNION ALL SELECT '  [OK] Views: v_openflow_connector_status, v_openflow_health_summary'
UNION ALL SELECT ''
UNION ALL SELECT '════════════════════════════════════════════════════════════════'
UNION ALL SELECT '  NEXT STEPS - Complete in Snowsight UI'
UNION ALL SELECT '════════════════════════════════════════════════════════════════'
UNION ALL SELECT ''
UNION ALL SELECT '1. Open Snowsight and navigate to: Data > Openflow'
UNION ALL SELECT ''
UNION ALL SELECT '2. CREATE DEPLOYMENT:'
UNION ALL SELECT '   - Click "Create Deployment"'
UNION ALL SELECT '   - Name: smdh-openflow-deployment'
UNION ALL SELECT '   - Select Snowflake Deployment (managed)'
UNION ALL SELECT ''
UNION ALL SELECT '3. CREATE RUNTIME:'
UNION ALL SELECT '   - In your deployment, click "Create Runtime"'
UNION ALL SELECT '   - Name: smdh-kinesis-runtime'
UNION ALL SELECT '   - Role: OPENFLOW_RUNTIME_ROLE_KINESIS'
UNION ALL SELECT '   - Warehouse: SMDH_WH'
UNION ALL SELECT '   - External Access: OPENFLOW_AWS_EAI'
UNION ALL SELECT ''
UNION ALL SELECT '4. ADD KINESIS CONNECTOR:'
UNION ALL SELECT '   - In the runtime, click "Add Connector"'
UNION ALL SELECT '   - Select "Amazon Kinesis"'
UNION ALL SELECT '   - Configure AWS credentials and stream details'
UNION ALL SELECT '   - Set stream-to-table mapping'
UNION ALL SELECT ''
UNION ALL SELECT '5. For each new tenant, run:'
UNION ALL SELECT '   CALL sp_grant_openflow_tenant_access(''tenant_id'');'
UNION ALL SELECT ''
UNION ALL SELECT 'Documentation: docs/deployment/Tenant_Onboarding_Guide.md'
UNION ALL SELECT '════════════════════════════════════════════════════════════════';

-- ============================================================================
-- Quick Reference Queries
-- ============================================================================

SELECT 'Quick Reference - Useful Queries:' AS reference
UNION ALL SELECT ''
UNION ALL SELECT '-- Check connector status:'
UNION ALL SELECT 'SELECT * FROM smdh_infrastructure.monitoring.v_openflow_connector_status;'
UNION ALL SELECT ''
UNION ALL SELECT '-- Check health summary:'
UNION ALL SELECT 'SELECT * FROM smdh_infrastructure.monitoring.v_openflow_health_summary;'
UNION ALL SELECT ''
UNION ALL SELECT '-- Grant access to new tenant:'
UNION ALL SELECT 'CALL smdh_infrastructure.tenant_configs.sp_grant_openflow_tenant_access(''tenant_id'');'
UNION ALL SELECT ''
UNION ALL SELECT '-- Register new connector (after UI setup):'
UNION ALL SELECT 'INSERT INTO smdh_infrastructure.tenant_configs.openflow_connectors'
UNION ALL SELECT '  (tenant_id, connector_name, target_database, target_schema, target_table,'
UNION ALL SELECT '   kinesis_stream_name, runtime_name, status)'
UNION ALL SELECT 'SELECT ''tenant_id'', ''connector_name'', ''SMDH_TENANT_XXX'', ''RAW'','
UNION ALL SELECT '       ''sensor_readings'', ''smdh-tenant-stream'', ''smdh-kinesis-runtime'', ''active'';';
