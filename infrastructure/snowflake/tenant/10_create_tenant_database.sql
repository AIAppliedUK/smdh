-- ============================================================================
-- SMDH Tenant Database Creation
-- ============================================================================
-- Purpose: Create isolated database for a new tenant
-- Usage: snowsql -f tenant/10_create_tenant_database.sql \
--          --variable tenant_id='company_a' \
--          --variable tenant_name='Company A Manufacturing Ltd' \
--          --variable aws_region='eu-west-2' \
--          --variable num_sites=5
-- Author: SMDH Platform Team
-- Version: 1.0
-- ============================================================================
-- This script creates:
-- - Tenant-specific database (smdh_tenant_{tenant_id})
-- - Four schemas: raw, normalized, aggregated, analytics
-- - Registers tenant in infrastructure database
-- ============================================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE SMDH_WH;

-- Display banner
SELECT '╔════════════════════════════════════════════════════════════════╗' AS banner
UNION ALL SELECT '║  SMDH Platform - Tenant Database Creation                  ║'
UNION ALL SELECT '╚════════════════════════════════════════════════════════════╝';

-- ============================================================================
-- 1. Validate Input Parameters
-- ============================================================================

SELECT '1. Validating Tenant Parameters...' AS step;

-- Parameters expected via --variable flags
SELECT 'Tenant ID: ' || $tenant_id AS parameter;
SELECT 'Tenant Name: ' || $tenant_name AS parameter;
SELECT 'AWS Region: ' || $aws_region AS parameter;
SELECT 'Number of Sites: ' || $num_sites AS parameter;

-- Validate tenant_id format (lowercase, alphanumeric, underscores only)
SELECT
    CASE
        WHEN $tenant_id REGEXP '^[a-z0-9_]+$'
        THEN '✓ Tenant ID format is valid'
        ELSE '✗ ERROR: Tenant ID must be lowercase alphanumeric with underscores only'
    END AS validation;

-- Check if tenant already exists
SELECT
    CASE
        WHEN EXISTS (
            SELECT 1 FROM smdh_infrastructure.tenant_configs.tenants
            WHERE tenant_id = $tenant_id
        )
        THEN '⚠ WARNING: Tenant ' || $tenant_id || ' already exists. This will update configuration.'
        ELSE '✓ New tenant will be created'
    END AS tenant_check;

-- ============================================================================
-- 2. Create Tenant Database
-- ============================================================================

SELECT '2. Creating Tenant Database...' AS step;

SET database_name = 'smdh_tenant_' || $tenant_id;

-- Create database with Time Travel enabled
CREATE DATABASE IF NOT EXISTS IDENTIFIER($database_name)
    DATA_RETENTION_TIME_IN_DAYS = 7  -- 7 days Time Travel for recovery
    COMMENT = 'SMDH Tenant Database for ' || $tenant_name || '. Isolated database per tenant for complete data separation.';

SELECT 'Created database: ' || $database_name AS result;

-- ============================================================================
-- 3. Create Schemas
-- ============================================================================

SELECT '3. Creating Tenant Schemas...' AS step;

USE DATABASE IDENTIFIER($database_name);

-- Raw ingested data schema
CREATE SCHEMA IF NOT EXISTS raw
    DATA_RETENTION_TIME_IN_DAYS = 7
    COMMENT = 'Raw ingested sensor data from IoT devices. Minimal transformation, preserves original payload structure.';

-- Normalized and validated data schema
CREATE SCHEMA IF NOT EXISTS normalized
    DATA_RETENTION_TIME_IN_DAYS = 7
    COMMENT = 'Cleaned, normalized, and validated data. Ready for analytics and aggregation.';

-- Aggregated metrics and KPIs schema
CREATE SCHEMA IF NOT EXISTS aggregated
    DATA_RETENTION_TIME_IN_DAYS = 30
    COMMENT = 'Pre-aggregated metrics and KPIs. Used for dashboards and reporting. Longer retention for historical analysis.';

-- Analytics views and ML results schema
CREATE SCHEMA IF NOT EXISTS analytics
    DATA_RETENTION_TIME_IN_DAYS = 30
    COMMENT = 'Analytics views, ML model results, and business intelligence objects.';

SELECT 'Created schemas: raw, normalized, aggregated, analytics' AS result;

-- ============================================================================
-- 4. Register Tenant in Infrastructure Database
-- ============================================================================

SELECT '4. Registering Tenant in Infrastructure Registry...' AS step;

-- Use MERGE to handle both new tenants and updates
MERGE INTO smdh_infrastructure.tenant_configs.tenants AS target
USING (
    SELECT
        $tenant_id AS tenant_id,
        $tenant_name AS tenant_name,
        'provisioning' AS status,
        $aws_region AS aws_region,
        $num_sites AS num_sites,
        CURRENT_TIMESTAMP() AS created_date
) AS source
ON target.tenant_id = source.tenant_id
WHEN MATCHED THEN
    UPDATE SET
        tenant_name = source.tenant_name,
        num_sites = source.num_sites,
        updated_date = CURRENT_TIMESTAMP()
WHEN NOT MATCHED THEN
    INSERT (
        tenant_id,
        tenant_name,
        status,
        aws_region,
        num_sites,
        created_date
    )
    VALUES (
        source.tenant_id,
        source.tenant_name,
        source.status,
        source.aws_region,
        source.num_sites,
        source.created_date
    );

SELECT 'Tenant registered in infrastructure database' AS result;

-- ============================================================================
-- 5. Create Default File Formats
-- ============================================================================

SELECT '5. Creating Default File Formats...' AS step;

USE DATABASE IDENTIFIER($database_name);
USE SCHEMA raw;

-- JSON format for MQTT sensor data
CREATE OR REPLACE FILE FORMAT ff_json
    TYPE = 'JSON'
    COMPRESSION = 'AUTO'
    STRIP_OUTER_ARRAY = FALSE
    STRIP_NULL_VALUES = FALSE
    IGNORE_UTF8_ERRORS = FALSE
    COMMENT = 'Standard JSON format for sensor data ingestion';

-- CSV format for file uploads
CREATE OR REPLACE FILE FORMAT ff_csv
    TYPE = 'CSV'
    COMPRESSION = 'AUTO'
    FIELD_DELIMITER = ','
    RECORD_DELIMITER = '\n'
    SKIP_HEADER = 1
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
    TRIM_SPACE = TRUE
    ERROR_ON_COLUMN_COUNT_MISMATCH = FALSE
    NULL_IF = ('NULL', 'null', '')
    COMMENT = 'Standard CSV format for file uploads';

-- Parquet format for optimized batch loads
CREATE OR REPLACE FILE FORMAT ff_parquet
    TYPE = 'PARQUET'
    COMPRESSION = 'SNAPPY'
    COMMENT = 'Parquet format for optimized batch data loads';

SELECT 'Created file formats: ff_json, ff_csv, ff_parquet' AS result;

-- ============================================================================
-- 6. Create Default Stages
-- ============================================================================

SELECT '6. Creating Default Stages...' AS step;

-- Internal stage for file uploads (temporary storage)
CREATE STAGE IF NOT EXISTS stage_uploads
    FILE_FORMAT = ff_csv
    COPY_OPTIONS = (ON_ERROR = 'CONTINUE')
    COMMENT = 'Internal stage for user file uploads via Streamlit portal';

-- Internal stage for error handling
CREATE STAGE IF NOT EXISTS stage_errors
    FILE_FORMAT = ff_json
    COMMENT = 'Internal stage for storing failed ingestion records';

SELECT 'Created stages: stage_uploads, stage_errors' AS result;

-- ============================================================================
-- 7. Create Tenant-Specific Roles
-- ============================================================================

SELECT '7. Creating Tenant-Specific Roles...' AS step;

USE ROLE ACCOUNTADMIN;

-- Admin role for tenant (full access to tenant database)
SET admin_role_name = 'smdh_tenant_' || '&tenant_id' || '_admin';
SET user_role_name = 'smdh_tenant_' || '&tenant_id' || '_user';
SET readonly_role_name = 'smdh_tenant_' || '&tenant_id' || '_readonly';

CREATE ROLE IF NOT EXISTS IDENTIFIER($admin_role_name)
    COMMENT = 'Admin role for tenant &tenant_name. Full access to tenant database and objects.';

CREATE ROLE IF NOT EXISTS IDENTIFIER($user_role_name)
    COMMENT = 'Standard user role for tenant &tenant_name. Read/write access to analytics objects.';

CREATE ROLE IF NOT EXISTS IDENTIFIER($readonly_role_name)
    COMMENT = 'Read-only role for tenant &tenant_name. View access for reporting and dashboards.';

-- Inherit from base analytics role
GRANT ROLE smdh_analytics_user TO ROLE IDENTIFIER($admin_role_name);
GRANT ROLE smdh_analytics_user TO ROLE IDENTIFIER($user_role_name);
GRANT ROLE smdh_analytics_user TO ROLE IDENTIFIER($readonly_role_name);

-- Grant roles to SYSADMIN for management
GRANT ROLE IDENTIFIER($admin_role_name) TO ROLE SYSADMIN;
GRANT ROLE IDENTIFIER($user_role_name) TO ROLE SYSADMIN;
GRANT ROLE IDENTIFIER($readonly_role_name) TO ROLE SYSADMIN;

SELECT 'Created roles: ' || $admin_role_name || ', ' || $user_role_name || ', ' || $readonly_role_name AS result;

-- ============================================================================
-- 8. Grant Permissions to Tenant Roles
-- ============================================================================

SELECT '8. Granting Permissions to Tenant Roles...' AS step;

-- Admin role: Full access to tenant database
GRANT ALL ON DATABASE IDENTIFIER($database_name) TO ROLE IDENTIFIER($admin_role_name);
GRANT ALL ON ALL SCHEMAS IN DATABASE IDENTIFIER($database_name) TO ROLE IDENTIFIER($admin_role_name);
GRANT ALL ON FUTURE SCHEMAS IN DATABASE IDENTIFIER($database_name) TO ROLE IDENTIFIER($admin_role_name);
GRANT ALL ON ALL TABLES IN DATABASE IDENTIFIER($database_name) TO ROLE IDENTIFIER($admin_role_name);
GRANT ALL ON FUTURE TABLES IN DATABASE IDENTIFIER($database_name) TO ROLE IDENTIFIER($admin_role_name);
GRANT ALL ON ALL VIEWS IN DATABASE IDENTIFIER($database_name) TO ROLE IDENTIFIER($admin_role_name);
GRANT ALL ON FUTURE VIEWS IN DATABASE IDENTIFIER($database_name) TO ROLE IDENTIFIER($admin_role_name);
GRANT ALL ON ALL STAGES IN DATABASE IDENTIFIER($database_name) TO ROLE IDENTIFIER($admin_role_name);
GRANT ALL ON FUTURE STAGES IN DATABASE IDENTIFIER($database_name) TO ROLE IDENTIFIER($admin_role_name);

-- User role: Read/write access (no DDL)
GRANT USAGE ON DATABASE IDENTIFIER($database_name) TO ROLE IDENTIFIER($user_role_name);
GRANT USAGE ON ALL SCHEMAS IN DATABASE IDENTIFIER($database_name) TO ROLE IDENTIFIER($user_role_name);
GRANT USAGE ON FUTURE SCHEMAS IN DATABASE IDENTIFIER($database_name) TO ROLE IDENTIFIER($user_role_name);
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN DATABASE IDENTIFIER($database_name) TO ROLE IDENTIFIER($user_role_name);
GRANT SELECT, INSERT, UPDATE, DELETE ON FUTURE TABLES IN DATABASE IDENTIFIER($database_name) TO ROLE IDENTIFIER($user_role_name);
GRANT SELECT ON ALL VIEWS IN DATABASE IDENTIFIER($database_name) TO ROLE IDENTIFIER($user_role_name);
GRANT SELECT ON FUTURE VIEWS IN DATABASE IDENTIFIER($database_name) TO ROLE IDENTIFIER($user_role_name);
GRANT READ, WRITE ON ALL STAGES IN DATABASE IDENTIFIER($database_name) TO ROLE IDENTIFIER($user_role_name);

-- Read-only role: SELECT only
GRANT USAGE ON DATABASE IDENTIFIER($database_name) TO ROLE IDENTIFIER($readonly_role_name);
GRANT USAGE ON ALL SCHEMAS IN DATABASE IDENTIFIER($database_name) TO ROLE IDENTIFIER($readonly_role_name);
GRANT USAGE ON FUTURE SCHEMAS IN DATABASE IDENTIFIER($database_name) TO ROLE IDENTIFIER($readonly_role_name);
GRANT SELECT ON ALL TABLES IN DATABASE IDENTIFIER($database_name) TO ROLE IDENTIFIER($readonly_role_name);
GRANT SELECT ON FUTURE TABLES IN DATABASE IDENTIFIER($database_name) TO ROLE IDENTIFIER($readonly_role_name);
GRANT SELECT ON ALL VIEWS IN DATABASE IDENTIFIER($database_name) TO ROLE IDENTIFIER($readonly_role_name);
GRANT SELECT ON FUTURE VIEWS IN DATABASE IDENTIFIER($database_name) TO ROLE IDENTIFIER($readonly_role_name);

SELECT 'Permissions granted to all tenant roles' AS result;

-- ============================================================================
-- 9. Create Metadata Tables for Tenant
-- ============================================================================

SELECT '9. Creating Tenant Metadata Tables...' AS step;

USE DATABASE IDENTIFIER($database_name);
USE SCHEMA analytics;

-- Tenant configuration metadata table
CREATE OR REPLACE TABLE tenant_metadata (
    tenant_id VARCHAR(100) DEFAULT $tenant_id,
    metadata_key VARCHAR(255) NOT NULL,
    metadata_value VARIANT,
    description VARCHAR(1000),
    created_date TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    updated_date TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    updated_by VARCHAR(255) DEFAULT CURRENT_USER(),
    PRIMARY KEY (metadata_key)
)
COMMENT = 'Tenant-specific configuration and metadata key-value store';

-- Insert initial metadata
INSERT INTO tenant_metadata (metadata_key, metadata_value, description) VALUES
    ('tenant_id', TO_VARIANT($tenant_id), 'Tenant identifier'),
    ('tenant_name', TO_VARIANT($tenant_name), 'Tenant display name'),
    ('aws_region', TO_VARIANT($aws_region), 'AWS region for IoT Core and Kinesis'),
    ('num_sites', TO_VARIANT($num_sites), 'Number of manufacturing sites'),
    ('database_created', TO_VARIANT(CURRENT_TIMESTAMP()), 'Database creation timestamp'),
    ('schema_version', TO_VARIANT('1.0'), 'Database schema version');

SELECT 'Created tenant metadata table with initial configuration' AS result;

-- ============================================================================
-- 10. Verification
-- ============================================================================

SELECT '10. Verifying Tenant Database Setup...' AS step;

-- Verify database
SHOW DATABASES LIKE 'smdh_tenant_%';

-- Verify schemas
USE DATABASE IDENTIFIER($database_name);
SHOW SCHEMAS;

-- Verify roles
SHOW ROLES LIKE 'smdh_tenant_' || '&tenant_id' || '%';

-- Verify file formats
USE SCHEMA raw;
SHOW FILE FORMATS;

-- Verify stages
SHOW STAGES;

-- Query tenant registry
SELECT 'Tenant Registry Entry:' AS verification;
SELECT
    tenant_id,
    tenant_name,
    status,
    num_sites,
    aws_region,
    created_date
FROM smdh_infrastructure.tenant_configs.tenants
WHERE tenant_id = $tenant_id;

-- ============================================================================
-- 11. Summary
-- ============================================================================

SELECT '╔════════════════════════════════════════════════════════════════╗' AS summary
UNION ALL SELECT '║  Tenant Database Creation Complete                         ║'
UNION ALL SELECT '╚════════════════════════════════════════════════════════════╝'
UNION ALL SELECT ''
UNION ALL SELECT 'Tenant Details:'
UNION ALL SELECT '  • Tenant ID: ' || $tenant_id
UNION ALL SELECT '  • Tenant Name: ' || $tenant_name
UNION ALL SELECT '  • Database: smdh_tenant_' || $tenant_id
UNION ALL SELECT '  • AWS Region: ' || $aws_region
UNION ALL SELECT '  • Number of Sites: ' || $num_sites
UNION ALL SELECT ''
UNION ALL SELECT 'Created Resources:'
UNION ALL SELECT '  ✓ Database: smdh_tenant_' || $tenant_id
UNION ALL SELECT '  ✓ Schemas: raw, normalized, aggregated, analytics'
UNION ALL SELECT '  ✓ File Formats: ff_json, ff_csv, ff_parquet'
UNION ALL SELECT '  ✓ Stages: stage_uploads, stage_errors'
UNION ALL SELECT '  ✓ Roles: _admin, _user, _readonly'
UNION ALL SELECT '  ✓ Metadata: tenant_metadata table'
UNION ALL SELECT ''
UNION ALL SELECT 'Next Steps:'
UNION ALL SELECT '  1. Run 11_create_schemas.sql (if not auto-included)'
UNION ALL SELECT '  2. Run 12_create_tables.sql to create data tables'
UNION ALL SELECT '  3. Run 13_create_streams.sql to enable CDC'
UNION ALL SELECT '  4. Run 14_create_tasks.sql to configure processing'
UNION ALL SELECT '  5. Run 15_create_dynamic_tables.sql for aggregations'
UNION ALL SELECT '  6. Run 16_create_roles.sql for additional RBAC (optional)'
UNION ALL SELECT '  7. Run 17_create_monitoring.sql for tenant dashboards'
UNION ALL SELECT ''
UNION ALL SELECT 'Verification:'
UNION ALL SELECT '  USE DATABASE smdh_tenant_' || $tenant_id || ';'
UNION ALL SELECT '  SHOW SCHEMAS;'
UNION ALL SELECT '  SELECT * FROM analytics.tenant_metadata;'
UNION ALL SELECT '============================================================';
