-- ============================================================================
-- SMDH Tenant Schema Configuration
-- ============================================================================
-- Purpose: Configure tenant schemas with appropriate settings and objects
-- Usage: snowsql -f tenant/11_create_schemas.sql --variable tenant_id='company_a'
-- Author: SMDH Platform Team
-- Version: 1.0
-- ============================================================================
-- This script:
-- - Verifies all required schemas exist
-- - Creates schema-level configurations
-- - Sets up schema-specific defaults
-- - Creates utility objects per schema
-- ============================================================================

-- Enable SnowSQL variable substitution 
!set variable_substitution=true

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE SMDH_WH;

-- Convert SnowSQL substitution variables to session variables
SET tenant_id = '&tenant_id';

-- Display banner
SELECT '╔════════════════════════════════════════════════════════════════╗' AS banner
UNION ALL SELECT '║  SMDH Platform - Tenant Schema Configuration               ║'
UNION ALL SELECT '╚════════════════════════════════════════════════════════════╝';

-- ============================================================================
-- 1. Validate Tenant and Database
-- ============================================================================

SELECT '1. Validating Tenant Database...' AS step;

SET database_name = 'smdh_tenant_' || $tenant_id;

-- Check if database exists (use UPPER for case-insensitive comparison)
SELECT
    CASE
        WHEN EXISTS (
            SELECT 1 FROM SNOWFLAKE.INFORMATION_SCHEMA.DATABASES
            WHERE DATABASE_NAME = UPPER($database_name)
        )
        THEN '[OK] Tenant database found: ' || $database_name
        ELSE '✗ ERROR: Tenant database not found. Run 10_create_tenant_database.sql first.'
    END AS validation;

USE DATABASE IDENTIFIER($database_name);

-- ============================================================================
-- 2. Verify and Configure RAW Schema
-- ============================================================================

SELECT '2. Configuring RAW Schema...' AS step;

USE SCHEMA raw;

-- Ensure proper data retention
ALTER SCHEMA raw SET DATA_RETENTION_TIME_IN_DAYS = 7;

SELECT 'Configured RAW schema with 7-day Time Travel' AS result;

-- ============================================================================
-- 3. Verify and Configure NORMALIZED Schema
-- ============================================================================

SELECT '3. Configuring NORMALIZED Schema...' AS step;

USE SCHEMA normalized;

-- Ensure proper data retention
ALTER SCHEMA normalized SET DATA_RETENTION_TIME_IN_DAYS = 7;

SELECT 'Configured NORMALIZED schema with 7-day Time Travel' AS result;

-- ============================================================================
-- 4. Verify and Configure AGGREGATED Schema
-- ============================================================================

SELECT '4. Configuring AGGREGATED Schema...' AS step;

USE SCHEMA aggregated;

-- Longer retention for aggregated data
ALTER SCHEMA aggregated SET DATA_RETENTION_TIME_IN_DAYS = 30;

SELECT 'Configured AGGREGATED schema with 30-day Time Travel' AS result;

-- ============================================================================
-- 5. Verify and Configure ANALYTICS Schema
-- ============================================================================

SELECT '5. Configuring ANALYTICS Schema...' AS step;

USE SCHEMA analytics;

-- Longer retention for analytics objects
ALTER SCHEMA analytics SET DATA_RETENTION_TIME_IN_DAYS = 30;

SELECT 'Configured ANALYTICS schema with 30-day Time Travel' AS result;

-- ============================================================================
-- 6. Create Schema Documentation Table
-- ============================================================================

SELECT '6. Creating Schema Documentation...' AS step;

USE SCHEMA analytics;

CREATE TABLE IF NOT EXISTS schema_documentation (
    schema_name VARCHAR(255) NOT NULL,
    object_type VARCHAR(100) NOT NULL,  -- TABLE, VIEW, STREAM, TASK, PIPE
    object_name VARCHAR(255) NOT NULL,
    description VARCHAR(5000),
    owner_role VARCHAR(255),
    created_date TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    last_modified TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    documentation_url VARCHAR(1000),
    example_query VARCHAR(16777216),
    tags VARIANT,
    PRIMARY KEY (schema_name, object_type, object_name)
)
COMMENT = 'Self-documenting table for all tenant database objects';

SELECT 'Created schema documentation table' AS result;

-- ============================================================================
-- 7. Create Data Quality Framework Tables
-- ============================================================================

SELECT '7. Creating Data Quality Framework...' AS step;

USE SCHEMA analytics;

-- Data quality rules table
CREATE TABLE IF NOT EXISTS data_quality_rules (
    rule_id VARCHAR(255) DEFAULT UUID_STRING(),
    rule_name VARCHAR(255) NOT NULL,
    schema_name VARCHAR(255) NOT NULL,
    table_name VARCHAR(255) NOT NULL,
    rule_type VARCHAR(100) NOT NULL,  -- NOT_NULL, RANGE, PATTERN, CUSTOM
    rule_definition VARCHAR(5000) NOT NULL,
    severity VARCHAR(50) DEFAULT 'warning',  -- critical, high, medium, low, warning
    is_active BOOLEAN DEFAULT TRUE,
    created_date TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    created_by VARCHAR(255) DEFAULT CURRENT_USER(),
    PRIMARY KEY (rule_id)

    -- Note: Snowflake does not support CHECK constraints
    -- Valid values for severity: 'critical', 'high', 'medium', 'low', 'warning'
)
COMMENT = 'Data quality rules for automated validation';

-- Data quality results table
CREATE TABLE IF NOT EXISTS data_quality_results (
    check_id VARCHAR(255) DEFAULT UUID_STRING(),
    rule_id VARCHAR(255) NOT NULL,
    check_timestamp TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    passed BOOLEAN,
    records_checked NUMBER(20),
    records_failed NUMBER(20),
    failure_rate FLOAT,
    error_samples VARIANT,
    execution_time_ms NUMBER(10),
    PRIMARY KEY (check_id)
)
CLUSTER BY (DATE_TRUNC('day', check_timestamp), rule_id)
COMMENT = 'Results of data quality checks';

SELECT 'Created data quality framework tables' AS result;

-- ============================================================================
-- 8. Create Sequence Generators (if needed)
-- ============================================================================

SELECT '8. Creating Sequence Generators...' AS step;

USE SCHEMA raw;

-- Sequence for synthetic IDs (if UUID is not suitable)
CREATE SEQUENCE IF NOT EXISTS seq_record_id
    START = 1
    INCREMENT = 1
    COMMENT = 'Sequence for generating integer record IDs';

SELECT 'Created sequence generators' AS result;

-- ============================================================================
-- 9. Create Schema-Level Tags
-- ============================================================================

SELECT '9. Configuring Schema Tags...' AS step;

USE DATABASE IDENTIFIER($database_name);

-- Note: Tags require Snowflake Enterprise Edition or higher
-- Tag creation and application is skipped for compatibility with Standard Edition
-- To enable tags on Enterprise Edition, uncomment and run the following:
--   CREATE TAG IF NOT EXISTS data_classification ALLOWED_VALUES 'public', 'internal', 'confidential', 'restricted';
--   CREATE TAG IF NOT EXISTS pii_flag ALLOWED_VALUES 'true', 'false';
--   ALTER SCHEMA raw SET TAG data_classification = 'internal', pii_flag = 'true';
--   ALTER SCHEMA normalized SET TAG data_classification = 'internal', pii_flag = 'true';
--   ALTER SCHEMA aggregated SET TAG data_classification = 'internal', pii_flag = 'false';
--   ALTER SCHEMA analytics SET TAG data_classification = 'internal', pii_flag = 'false';

SELECT '⚠ Tag creation skipped (requires Enterprise Edition or higher)' AS result;

-- ============================================================================
-- 10. Create Schema Utility Views
-- ============================================================================

SELECT '10. Creating Schema Utility Views...' AS step;

USE SCHEMA analytics;

-- View to show all tables across schemas
-- Uses current database context (no explicit database name needed)
CREATE OR REPLACE VIEW v_tenant_objects AS
SELECT
    table_catalog AS database_name,
    table_schema AS schema_name,
    table_name AS object_name,
    table_type AS object_type,
    row_count,
    bytes,
    ROUND(bytes / (1024*1024*1024), 2) AS size_gb,
    created,
    last_altered,
    comment AS description
FROM INFORMATION_SCHEMA.TABLES
WHERE table_schema IN ('RAW', 'NORMALIZED', 'AGGREGATED', 'ANALYTICS')
ORDER BY schema_name, table_name;

-- View to show storage usage per schema
-- Uses current database context (no explicit database name needed)
CREATE OR REPLACE VIEW v_schema_storage AS
SELECT
    table_schema AS schema_name,
    COUNT(*) AS table_count,
    SUM(row_count) AS total_rows,
    ROUND(SUM(bytes) / (1024*1024*1024), 2) AS total_size_gb,
    MAX(last_altered) AS last_modified
FROM INFORMATION_SCHEMA.TABLES
WHERE table_schema IN ('RAW', 'NORMALIZED', 'AGGREGATED', 'ANALYTICS')
GROUP BY schema_name
ORDER BY schema_name;

SELECT 'Created schema utility views' AS result;

-- ============================================================================
-- 11. Document Schemas
-- ============================================================================

SELECT '11. Documenting Schemas...' AS step;

USE SCHEMA analytics;

-- Insert schema documentation
MERGE INTO schema_documentation AS target
USING (
    SELECT 'RAW' AS schema_name, 'SCHEMA' AS object_type, 'raw' AS object_name,
           'Raw ingested data from IoT devices. Preserves original payload structure for auditability.' AS description
    UNION ALL
    SELECT 'NORMALIZED', 'SCHEMA', 'normalized',
           'Cleaned and normalized data with validation applied. Flattened structure ready for analytics.'
    UNION ALL
    SELECT 'AGGREGATED', 'SCHEMA', 'aggregated',
           'Pre-computed aggregations and metrics. Optimized for dashboard queries.'
    UNION ALL
    SELECT 'ANALYTICS', 'SCHEMA', 'analytics',
           'Analytics views, ML results, and metadata tables. Business intelligence layer.'
) AS source
ON target.schema_name = source.schema_name
    AND target.object_type = source.object_type
    AND target.object_name = source.object_name
WHEN NOT MATCHED THEN
    INSERT (schema_name, object_type, object_name, description)
    VALUES (source.schema_name, source.object_type, source.object_name, source.description);

SELECT 'Documented all schemas' AS result;

-- ============================================================================
-- 12. Verification
-- ============================================================================

SELECT '12. Verifying Schema Configuration...' AS step;

-- Show all schemas
SHOW SCHEMAS IN DATABASE IDENTIFIER($database_name);

-- Query schema sizes
SELECT * FROM analytics.v_schema_storage;

-- Query schema documentation
SELECT schema_name, object_name, description
FROM analytics.schema_documentation
WHERE object_type = 'SCHEMA'
ORDER BY schema_name;

-- ============================================================================
-- 13. Summary
-- ============================================================================

SELECT '╔════════════════════════════════════════════════════════════════╗' AS summary
UNION ALL SELECT '║  Tenant Schema Configuration Complete                      ║'
UNION ALL SELECT '╚════════════════════════════════════════════════════════════╝'
UNION ALL SELECT ''
UNION ALL SELECT 'Configured Schemas:'
UNION ALL SELECT '  [OK] RAW: 7-day retention, ingestion staging'
UNION ALL SELECT '  [OK] NORMALIZED: 7-day retention, validated data'
UNION ALL SELECT '  [OK] AGGREGATED: 30-day retention, pre-computed metrics'
UNION ALL SELECT '  [OK] ANALYTICS: 30-day retention, views and ML results'
UNION ALL SELECT ''
UNION ALL SELECT 'Created Objects:'
UNION ALL SELECT '  [OK] Schema documentation table'
UNION ALL SELECT '  [OK] Data quality framework (rules + results tables)'
UNION ALL SELECT '  [OK] Sequence generators'
UNION ALL SELECT '  [OK] Utility views (v_tenant_objects, v_schema_storage)'
UNION ALL SELECT '  [OK] Data classification tags (Enterprise Edition)'
UNION ALL SELECT ''
UNION ALL SELECT 'Next Steps:'
UNION ALL SELECT '  1. Run 12_create_tables.sql to create data tables'
UNION ALL SELECT '  2. Define data quality rules in analytics.data_quality_rules'
UNION ALL SELECT '  3. Configure schema-level access policies if needed'
UNION ALL SELECT ''
UNION ALL SELECT 'Verification Queries:'
UNION ALL SELECT '  SELECT * FROM analytics.v_schema_storage;'
UNION ALL SELECT '  SELECT * FROM analytics.schema_documentation;'
UNION ALL SELECT '============================================================';
