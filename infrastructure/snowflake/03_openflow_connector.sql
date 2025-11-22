-- ============================================================================
-- SMDH Snowflake Openflow Connector Setup (Kinesis Integration)
-- ============================================================================
-- Purpose: Configure Snowflake Openflow connector for Kinesis Data Streams
-- Usage: snowsql -f 03_openflow_connector.sql \
--          -D aws_iam_role_arn='<role_arn>' \
--          -D aws_external_id='<external_id>' \
--          -D kinesis_stream_arn='<stream_arn>'
-- Author: SMDH Platform Team
-- Version: 1.0
-- ============================================================================
-- Prerequisites:
-- 1. AWS Kinesis Data Stream created in eu-west-2
-- 2. AWS IAM role created with trust relationship to Snowflake
-- 3. IAM role has permissions to read from Kinesis stream
-- 4. External ID configured for secure cross-account access
-- ============================================================================

USE ROLE ACCOUNTADMIN;

-- Display banner
SELECT '╔════════════════════════════════════════════════════════════════╗' AS banner
UNION ALL SELECT '║  SMDH Platform - Openflow Kinesis Connector Setup          ║'
UNION ALL SELECT '╚════════════════════════════════════════════════════════════╝';

-- ============================================================================
-- Variable Validation
-- ============================================================================

SELECT '1. Validating Input Parameters...' AS step;

-- Variables should be passed via -D flags:
-- aws_iam_role_arn: IAM role ARN from AWS (e.g., arn:aws:iam::123456789012:role/smdh-snowflake-kinesis-role)
-- aws_external_id: External ID for role assumption security
-- kinesis_stream_arn: ARN of Kinesis stream (e.g., arn:aws:kinesis:eu-west-2:123456789012:stream/smdh-sensor-data-stream)

-- Display parameters (for verification)
SELECT 'AWS IAM Role ARN: ' || &aws_iam_role_arn AS parameter;
SELECT 'AWS External ID: ' || &aws_external_id AS parameter;
SELECT 'Kinesis Stream ARN: ' || &kinesis_stream_arn AS parameter;

-- Prompt user to verify
SELECT 'Please verify the parameters above are correct.' AS verification_prompt;
SELECT 'Press Ctrl+C to cancel, or press Enter to continue...' AS verification_prompt;

-- ============================================================================
-- 2. Create AWS IAM Integration (External Stage)
-- ============================================================================

SELECT '2. Creating AWS IAM Integration for Kinesis Access...' AS step;

-- Create storage integration for cross-account access
CREATE OR REPLACE STORAGE INTEGRATION smdh_kinesis_integration
    TYPE = EXTERNAL_STAGE
    STORAGE_PROVIDER = 'S3'
    ENABLED = TRUE
    STORAGE_AWS_ROLE_ARN = &aws_iam_role_arn
    STORAGE_AWS_EXTERNAL_ID = &aws_external_id
    STORAGE_ALLOWED_LOCATIONS = ('*')  -- Kinesis connector doesn't use specific S3 locations
    COMMENT = 'IAM integration for Snowflake Openflow to access AWS Kinesis Data Streams in eu-west-2.';

-- Describe integration to get Snowflake IAM user ARN and External ID
-- These values must be configured in AWS IAM role trust policy
DESC INTEGRATION smdh_kinesis_integration;

SELECT '⚠ IMPORTANT: Note the STORAGE_AWS_IAM_USER_ARN and STORAGE_AWS_EXTERNAL_ID from above.' AS important_note;
SELECT 'Add these to your AWS IAM role trust relationship policy.' AS important_note;

-- ============================================================================
-- 3. Create Kinesis Data Source (Openflow Connector)
-- ============================================================================

SELECT '3. Configuring Snowflake Openflow Connector for Kinesis...' AS step;

-- Note: Snowflake Openflow uses PIPE objects to configure Kinesis ingestion
-- Each tenant will have their own pipe configured in tenant setup scripts
-- Here we create a template and verify connectivity

-- Create a test database for validation (temporary)
CREATE DATABASE IF NOT EXISTS smdh_openflow_test
    DATA_RETENTION_TIME_IN_DAYS = 1
    COMMENT = 'Temporary database for testing Openflow Kinesis connector';

USE DATABASE smdh_openflow_test;
CREATE SCHEMA IF NOT EXISTS test_schema;
USE SCHEMA test_schema;

-- Create test table matching sensor data structure
CREATE OR REPLACE TABLE kinesis_test_data (
    record_metadata VARIANT,
    record_content VARIANT,
    ingestion_timestamp TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'Temporary table for testing Kinesis connector';

-- Create test pipe for Kinesis stream
-- Note: COPY INTO will be executed automatically by Snowflake when new data arrives in Kinesis
CREATE OR REPLACE PIPE kinesis_test_pipe
    AUTO_INGEST = TRUE
    AWS_SNS_TOPIC = NULL  -- Not used for Kinesis (SNS is for S3 notifications)
    INTEGRATION = 'smdh_kinesis_integration'
    COMMENT = 'Test pipe for validating Kinesis connectivity'
AS
COPY INTO kinesis_test_data (record_metadata, record_content)
FROM (
    SELECT
        METADATA$KINESIS AS record_metadata,
        $1 AS record_content
    FROM '@' || &kinesis_stream_arn
)
FILE_FORMAT = (TYPE = 'JSON');

-- Show pipe status
SHOW PIPES LIKE 'kinesis_test_pipe';

-- Get pipe notification channel (for AWS EventBridge if needed)
SELECT SYSTEM$PIPE_STATUS('kinesis_test_pipe') AS pipe_status;

-- ============================================================================
-- 4. Create Infrastructure Tracking Table for Openflow Configs
-- ============================================================================

SELECT '4. Creating Openflow Configuration Tracking...' AS step;

USE DATABASE smdh_infrastructure;
USE SCHEMA tenant_configs;

CREATE TABLE IF NOT EXISTS openflow_connectors (
    connector_id VARCHAR(255) DEFAULT UUID_STRING(),
    tenant_id VARCHAR(100) NOT NULL,

    -- Pipe details
    database_name VARCHAR(255) NOT NULL,
    schema_name VARCHAR(255) NOT NULL,
    pipe_name VARCHAR(255) NOT NULL,
    table_name VARCHAR(255) NOT NULL,

    -- AWS details
    kinesis_stream_arn VARCHAR(500) NOT NULL,
    aws_region VARCHAR(50) NOT NULL DEFAULT 'eu-west-2',

    -- Status
    status VARCHAR(50) DEFAULT 'active',
    created_date TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    last_ingestion_timestamp TIMESTAMP_NTZ,
    total_records_ingested NUMBER(20) DEFAULT 0,

    -- Configuration
    auto_ingest BOOLEAN DEFAULT TRUE,
    integration_name VARCHAR(255) DEFAULT 'smdh_kinesis_integration',

    -- Metadata
    configuration VARIANT,

    PRIMARY KEY (connector_id),
    CONSTRAINT fk_connector_tenant FOREIGN KEY (tenant_id)
        REFERENCES tenants(tenant_id) NOT ENFORCED

    -- Note: Snowflake does not support CHECK constraints
    -- Valid values for status: 'active', 'paused', 'error', 'decommissioned'
)
COMMENT = 'Registry of Snowflake Openflow connectors per tenant. Tracks Kinesis pipes and ingestion status.';

-- ============================================================================
-- 5. Create Monitoring View for Pipe Status
-- ============================================================================

SELECT '5. Creating Pipe Monitoring Views...' AS step;

USE SCHEMA monitoring;

CREATE OR REPLACE VIEW v_pipe_status AS
SELECT
    pipe_catalog_name || '.' || pipe_schema_name || '.' || pipe_name AS pipe_full_name,
    pipe_name,
    is_autoingest_enabled,
    notification_channel_name,
    pipe_owner,
    definition,
    created_on,
    SYSTEM$PIPE_STATUS(pipe_catalog_name || '.' || pipe_schema_name || '.' || pipe_name) AS pipe_status
FROM SNOWFLAKE.ACCOUNT_USAGE.PIPES
WHERE pipe_name LIKE '%kinesis%' OR pipe_name LIKE 'smdh_%'
ORDER BY created_on DESC;

GRANT SELECT ON v_pipe_status TO ROLE smdh_monitoring;

-- Create view for copy history (data ingestion metrics)
CREATE OR REPLACE VIEW v_kinesis_ingestion_metrics AS
SELECT
    pipe_name,
    DATE_TRUNC('hour', last_load_time) AS ingestion_hour,
    SUM(row_count) AS total_rows_ingested,
    SUM(file_size) AS total_bytes_ingested,
    COUNT(*) AS load_count,
    AVG(row_count) AS avg_rows_per_load,
    MIN(last_load_time) AS first_load,
    MAX(last_load_time) AS last_load
FROM SNOWFLAKE.ACCOUNT_USAGE.COPY_HISTORY
WHERE pipe_name LIKE 'smdh_%'
    AND last_load_time >= DATEADD(day, -7, CURRENT_TIMESTAMP())
GROUP BY pipe_name, ingestion_hour
ORDER BY ingestion_hour DESC, pipe_name;

GRANT SELECT ON v_kinesis_ingestion_metrics TO ROLE smdh_monitoring;

-- ============================================================================
-- 6. Create Stored Procedure for Pipe Management
-- ============================================================================

SELECT '6. Creating Pipe Management Procedures...' AS step;

USE DATABASE smdh_infrastructure;
USE SCHEMA tenant_configs;

-- Procedure to pause a tenant's Kinesis ingestion
CREATE OR REPLACE PROCEDURE sp_pause_tenant_ingestion(tenant_id_param VARCHAR)
RETURNS STRING
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    pipe_list RESULTSET;
    pipe_full_name VARCHAR;
    result_msg VARCHAR DEFAULT '';
BEGIN
    -- Get all pipes for tenant
    pipe_list := (
        SELECT database_name || '.' || schema_name || '.' || pipe_name AS full_pipe_name
        FROM smdh_infrastructure.tenant_configs.openflow_connectors
        WHERE tenant_id = :tenant_id_param AND status = 'active'
    );

    -- Pause each pipe
    FOR record IN pipe_list DO
        pipe_full_name := record.full_pipe_name;
        EXECUTE IMMEDIATE 'ALTER PIPE ' || pipe_full_name || ' SET PIPE_EXECUTION_PAUSED = TRUE';
        result_msg := result_msg || 'Paused: ' || pipe_full_name || '; ';
    END FOR;

    -- Update status in tracking table
    UPDATE smdh_infrastructure.tenant_configs.openflow_connectors
    SET status = 'paused'
    WHERE tenant_id = :tenant_id_param;

    RETURN 'Successfully paused ingestion for tenant ' || tenant_id_param || '. ' || result_msg;
END;
$$;

-- Procedure to resume a tenant's Kinesis ingestion
CREATE OR REPLACE PROCEDURE sp_resume_tenant_ingestion(tenant_id_param VARCHAR)
RETURNS STRING
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    pipe_list RESULTSET;
    pipe_full_name VARCHAR;
    result_msg VARCHAR DEFAULT '';
BEGIN
    -- Get all pipes for tenant
    pipe_list := (
        SELECT database_name || '.' || schema_name || '.' || pipe_name AS full_pipe_name
        FROM smdh_infrastructure.tenant_configs.openflow_connectors
        WHERE tenant_id = :tenant_id_param AND status = 'paused'
    );

    -- Resume each pipe
    FOR record IN pipe_list DO
        pipe_full_name := record.full_pipe_name;
        EXECUTE IMMEDIATE 'ALTER PIPE ' || pipe_full_name || ' SET PIPE_EXECUTION_PAUSED = FALSE';
        result_msg := result_msg || 'Resumed: ' || pipe_full_name || '; ';
    END FOR;

    -- Update status in tracking table
    UPDATE smdh_infrastructure.tenant_configs.openflow_connectors
    SET status = 'active'
    WHERE tenant_id = :tenant_id_param;

    RETURN 'Successfully resumed ingestion for tenant ' || tenant_id_param || '. ' || result_msg;
END;
$$;

GRANT USAGE ON PROCEDURE sp_pause_tenant_ingestion(VARCHAR) TO ROLE smdh_tenant_operator;
GRANT USAGE ON PROCEDURE sp_resume_tenant_ingestion(VARCHAR) TO ROLE smdh_tenant_operator;

-- ============================================================================
-- 7. Verification and Testing
-- ============================================================================

SELECT '7. Verifying Openflow Connector Setup...' AS step;

-- Check integration
SELECT 'Storage Integration Status:' AS verification;
DESC INTEGRATION smdh_kinesis_integration;

-- Check test pipe
SELECT 'Test Pipe Status:' AS verification;
USE DATABASE smdh_openflow_test;
USE SCHEMA test_schema;
SHOW PIPES LIKE 'kinesis_test_pipe';

-- Check tracking table
SELECT 'Openflow Connector Tracking Table:' AS verification;
DESC TABLE smdh_infrastructure.tenant_configs.openflow_connectors;

-- Check procedures
SELECT 'Pipe Management Procedures:' AS verification;
SHOW PROCEDURES LIKE 'sp_%_tenant_ingestion' IN smdh_infrastructure.tenant_configs;

-- ============================================================================
-- 8. Summary and Next Steps
-- ============================================================================

SELECT '╔════════════════════════════════════════════════════════════════╗' AS summary
UNION ALL SELECT '║  SMDH Openflow Kinesis Connector Setup Complete            ║'
UNION ALL SELECT '╚════════════════════════════════════════════════════════════╝'
UNION ALL SELECT ''
UNION ALL SELECT 'Created Resources:'
UNION ALL SELECT '  ✓ Storage Integration: smdh_kinesis_integration'
UNION ALL SELECT '  ✓ Test Database: smdh_openflow_test (for validation)'
UNION ALL SELECT '  ✓ Tracking Table: openflow_connectors'
UNION ALL SELECT '  ✓ Monitoring Views: v_pipe_status, v_kinesis_ingestion_metrics'
UNION ALL SELECT '  ✓ Management Procedures: sp_pause/resume_tenant_ingestion'
UNION ALL SELECT ''
UNION ALL SELECT '⚠ CRITICAL AWS CONFIGURATION REQUIRED:'
UNION ALL SELECT ''
UNION ALL SELECT 'Run this query to get Snowflake credentials for AWS:'
UNION ALL SELECT '  DESC INTEGRATION smdh_kinesis_integration;'
UNION ALL SELECT ''
UNION ALL SELECT 'Copy the following values:'
UNION ALL SELECT '  • STORAGE_AWS_IAM_USER_ARN'
UNION ALL SELECT '  • STORAGE_AWS_EXTERNAL_ID'
UNION ALL SELECT ''
UNION ALL SELECT 'Update your AWS IAM role trust policy with these values:'
UNION ALL SELECT '{'
UNION ALL SELECT '  "Version": "2012-10-17",'
UNION ALL SELECT '  "Statement": ['
UNION ALL SELECT '    {'
UNION ALL SELECT '      "Effect": "Allow",'
UNION ALL SELECT '      "Principal": {'
UNION ALL SELECT '        "AWS": "<STORAGE_AWS_IAM_USER_ARN from above>"'
UNION ALL SELECT '      },'
UNION ALL SELECT '      "Action": "sts:AssumeRole",'
UNION ALL SELECT '      "Condition": {'
UNION ALL SELECT '        "StringEquals": {'
UNION ALL SELECT '          "sts:ExternalId": "<STORAGE_AWS_EXTERNAL_ID from above>"'
UNION ALL SELECT '        }'
UNION ALL SELECT '      }'
UNION ALL SELECT '    }'
UNION ALL SELECT '  ]'
UNION ALL SELECT '}'
UNION ALL SELECT ''
UNION ALL SELECT 'Testing:'
UNION ALL SELECT '  1. Send test message to Kinesis stream from AWS console'
UNION ALL SELECT '  2. Wait 60 seconds for Snowflake to poll Kinesis'
UNION ALL SELECT '  3. Query: SELECT * FROM smdh_openflow_test.test_schema.kinesis_test_data;'
UNION ALL SELECT '  4. Verify data appears in table'
UNION ALL SELECT ''
UNION ALL SELECT 'Next Steps:'
UNION ALL SELECT '  1. Update AWS IAM role trust policy (CRITICAL)'
UNION ALL SELECT '  2. Test connectivity with sample Kinesis message'
UNION ALL SELECT '  3. Run tenant/10_create_tenant_database.sql to onboard first tenant'
UNION ALL SELECT '  4. Each tenant will get their own Kinesis pipe configured automatically'
UNION ALL SELECT ''
UNION ALL SELECT 'Monitoring Queries:'
UNION ALL SELECT '  • Pipe status: SELECT * FROM smdh_infrastructure.monitoring.v_pipe_status;'
UNION ALL SELECT '  • Ingestion metrics: SELECT * FROM smdh_infrastructure.monitoring.v_kinesis_ingestion_metrics;'
UNION ALL SELECT '  • Pause ingestion: CALL sp_pause_tenant_ingestion(''tenant_id'');'
UNION ALL SELECT '  • Resume ingestion: CALL sp_resume_tenant_ingestion(''tenant_id'');'
UNION ALL SELECT '============================================================';

-- Display integration details for AWS configuration
SELECT 'Copy these values to AWS IAM role trust policy:' AS instruction;
DESC INTEGRATION smdh_kinesis_integration;
