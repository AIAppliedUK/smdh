-- ============================================================================
-- SMDH Tenant RBAC Configuration (Additional Roles)
-- ============================================================================
-- Purpose: Create additional tenant-specific roles for fine-grained access control
-- Usage: snowsql -f tenant/16_create_roles.sql -D tenant_id='company_a'
-- Author: SMDH Platform Team
-- Version: 1.0
-- ============================================================================
-- This script creates optional additional roles:
-- - Data Engineer role (for ETL development)
-- - Data Analyst role (for analytics work)
-- - API Service Account role (for programmatic access)
-- - Auditor role (read-only access for compliance)
-- ============================================================================

USE ROLE ACCOUNTADMIN;

-- Display banner
SELECT '╔════════════════════════════════════════════════════════════════╗' AS banner
UNION ALL SELECT '║  SMDH Platform - Additional RBAC Configuration             ║'
UNION ALL SELECT '╚════════════════════════════════════════════════════════════╝';

-- ============================================================================
-- 1. Validate Tenant Database
-- ============================================================================

SELECT '1. Validating Tenant Database...' AS step;

SET database_name = 'smdh_tenant_' || '&tenant_id';
SET tenant_prefix = 'smdh_tenant_' || '&tenant_id';

USE DATABASE IDENTIFIER(&database_name);

SELECT 'Using database: ' || '&database_name' AS info;

-- Verify existing roles
SELECT 'Existing tenant roles:' AS info;
SHOW ROLES LIKE 'smdh_tenant_' || '&tenant_id' || '%';

-- ============================================================================
-- 2. Create Data Engineer Role
-- ============================================================================

SELECT '2. Creating Data Engineer Role...' AS step;

SET data_engineer_role = $tenant_prefix || '_data_engineer';

CREATE ROLE IF NOT EXISTS IDENTIFIER($data_engineer_role)
    COMMENT = CONCAT('Data Engineer role for tenant ', &tenant_id, '. Can create and modify ETL objects (streams, tasks, procedures).');

-- Grant database access
GRANT USAGE ON DATABASE IDENTIFIER(&database_name) TO ROLE IDENTIFIER($data_engineer_role);
GRANT USAGE ON ALL SCHEMAS IN DATABASE IDENTIFIER(&database_name) TO ROLE IDENTIFIER($data_engineer_role);

-- Grant full access to RAW and NORMALIZED schemas (for ETL development)
GRANT ALL ON SCHEMA smdh_tenant_${tenant_id}.raw TO ROLE IDENTIFIER($data_engineer_role);
GRANT ALL ON SCHEMA smdh_tenant_${tenant_id}.normalized TO ROLE IDENTIFIER($data_engineer_role);
GRANT ALL ON ALL TABLES IN SCHEMA smdh_tenant_${tenant_id}.raw TO ROLE IDENTIFIER($data_engineer_role);
GRANT ALL ON ALL TABLES IN SCHEMA smdh_tenant_${tenant_id}.normalized TO ROLE IDENTIFIER($data_engineer_role);
GRANT ALL ON FUTURE TABLES IN SCHEMA smdh_tenant_${tenant_id}.raw TO ROLE IDENTIFIER($data_engineer_role);
GRANT ALL ON FUTURE TABLES IN SCHEMA smdh_tenant_${tenant_id}.normalized TO ROLE IDENTIFIER($data_engineer_role);

-- Grant stream and task management
GRANT ALL ON ALL STREAMS IN DATABASE IDENTIFIER(&database_name) TO ROLE IDENTIFIER($data_engineer_role);
GRANT ALL ON FUTURE STREAMS IN DATABASE IDENTIFIER(&database_name) TO ROLE IDENTIFIER($data_engineer_role);
GRANT ALL ON ALL TASKS IN DATABASE IDENTIFIER(&database_name) TO ROLE IDENTIFIER($data_engineer_role);
GRANT ALL ON FUTURE TASKS IN DATABASE IDENTIFIER(&database_name) TO ROLE IDENTIFIER($data_engineer_role);

-- Grant read access to AGGREGATED and ANALYTICS (for validation)
GRANT SELECT ON ALL TABLES IN SCHEMA smdh_tenant_${tenant_id}.aggregated TO ROLE IDENTIFIER($data_engineer_role);
GRANT SELECT ON ALL DYNAMIC TABLES IN SCHEMA smdh_tenant_${tenant_id}.aggregated TO ROLE IDENTIFIER($data_engineer_role);
GRANT SELECT ON ALL VIEWS IN SCHEMA smdh_tenant_${tenant_id}.analytics TO ROLE IDENTIFIER($data_engineer_role);

-- Grant warehouse access
GRANT USAGE ON WAREHOUSE smdh_etl_wh TO ROLE IDENTIFIER($data_engineer_role);
GRANT USAGE ON WAREHOUSE smdh_dev_wh TO ROLE IDENTIFIER($data_engineer_role);

GRANT ROLE IDENTIFIER($data_engineer_role) TO ROLE SYSADMIN;

SELECT 'Created role: ' || $data_engineer_role AS result;

-- ============================================================================
-- 3. Create Data Analyst Role
-- ============================================================================

SELECT '3. Creating Data Analyst Role...' AS step;

SET data_analyst_role = $tenant_prefix || '_data_analyst';

CREATE ROLE IF NOT EXISTS IDENTIFIER($data_analyst_role)
    COMMENT = CONCAT('Data Analyst role for tenant ', &tenant_id, '. Read/write access to analytics objects only.');

-- Grant database access
GRANT USAGE ON DATABASE IDENTIFIER(&database_name) TO ROLE IDENTIFIER($data_analyst_role);
GRANT USAGE ON ALL SCHEMAS IN DATABASE IDENTIFIER(&database_name) TO ROLE IDENTIFIER($data_analyst_role);

-- Grant read access to NORMALIZED and AGGREGATED
GRANT SELECT ON ALL TABLES IN SCHEMA smdh_tenant_${tenant_id}.normalized TO ROLE IDENTIFIER($data_analyst_role);
GRANT SELECT ON FUTURE TABLES IN SCHEMA smdh_tenant_${tenant_id}.normalized TO ROLE IDENTIFIER($data_analyst_role);
GRANT SELECT ON ALL TABLES IN SCHEMA smdh_tenant_${tenant_id}.aggregated TO ROLE IDENTIFIER($data_analyst_role);
GRANT SELECT ON ALL DYNAMIC TABLES IN SCHEMA smdh_tenant_${tenant_id}.aggregated TO ROLE IDENTIFIER($data_analyst_role);
GRANT SELECT ON FUTURE TABLES IN SCHEMA smdh_tenant_${tenant_id}.aggregated TO ROLE IDENTIFIER($data_analyst_role);

-- Grant full access to ANALYTICS schema (for creating custom views/tables)
GRANT ALL ON SCHEMA smdh_tenant_${tenant_id}.analytics TO ROLE IDENTIFIER($data_analyst_role);
GRANT ALL ON ALL TABLES IN SCHEMA smdh_tenant_${tenant_id}.analytics TO ROLE IDENTIFIER($data_analyst_role);
GRANT ALL ON ALL VIEWS IN SCHEMA smdh_tenant_${tenant_id}.analytics TO ROLE IDENTIFIER($data_analyst_role);
GRANT ALL ON FUTURE TABLES IN SCHEMA smdh_tenant_${tenant_id}.analytics TO ROLE IDENTIFIER($data_analyst_role);
GRANT ALL ON FUTURE VIEWS IN SCHEMA smdh_tenant_${tenant_id}.analytics TO ROLE IDENTIFIER($data_analyst_role);

-- Grant warehouse access
GRANT USAGE ON WAREHOUSE smdh_analytics_wh TO ROLE IDENTIFIER($data_analyst_role);

GRANT ROLE IDENTIFIER($data_analyst_role) TO ROLE SYSADMIN;

SELECT 'Created role: ' || $data_analyst_role AS result;

-- ============================================================================
-- 4. Create API Service Account Role
-- ============================================================================

SELECT '4. Creating API Service Account Role...' AS step;

SET api_service_role = $tenant_prefix || '_api_service';

CREATE ROLE IF NOT EXISTS IDENTIFIER($api_service_role)
    COMMENT = CONCAT('API Service Account role for tenant ', &tenant_id, '. Programmatic read access for external applications.');

-- Grant database access
GRANT USAGE ON DATABASE IDENTIFIER(&database_name) TO ROLE IDENTIFIER($api_service_role);
GRANT USAGE ON ALL SCHEMAS IN DATABASE IDENTIFIER(&database_name) TO ROLE IDENTIFIER($api_service_role);

-- Grant read-only access to all data schemas
GRANT SELECT ON ALL TABLES IN DATABASE IDENTIFIER(&database_name) TO ROLE IDENTIFIER($api_service_role);
GRANT SELECT ON ALL VIEWS IN DATABASE IDENTIFIER(&database_name) TO ROLE IDENTIFIER($api_service_role);
GRANT SELECT ON ALL DYNAMIC TABLES IN SCHEMA smdh_tenant_${tenant_id}.aggregated TO ROLE IDENTIFIER($api_service_role);
GRANT SELECT ON FUTURE TABLES IN DATABASE IDENTIFIER(&database_name) TO ROLE IDENTIFIER($api_service_role);
GRANT SELECT ON FUTURE VIEWS IN DATABASE IDENTIFIER(&database_name) TO ROLE IDENTIFIER($api_service_role);

-- Grant warehouse access (small warehouse for API queries)
GRANT USAGE ON WAREHOUSE smdh_analytics_wh TO ROLE IDENTIFIER($api_service_role);

GRANT ROLE IDENTIFIER($api_service_role) TO ROLE SYSADMIN;

SELECT 'Created role: ' || $api_service_role AS result;

-- ============================================================================
-- 5. Create Auditor Role
-- ============================================================================

SELECT '5. Creating Auditor Role...' AS step;

SET auditor_role = $tenant_prefix || '_auditor';

CREATE ROLE IF NOT EXISTS IDENTIFIER($auditor_role)
    COMMENT = CONCAT('Auditor role for tenant ', &tenant_id, '. Read-only access for compliance and audit purposes.');

-- Grant database usage
GRANT USAGE ON DATABASE IDENTIFIER(&database_name) TO ROLE IDENTIFIER($auditor_role);
GRANT USAGE ON ALL SCHEMAS IN DATABASE IDENTIFIER(&database_name) TO ROLE IDENTIFIER($auditor_role);

-- Grant read-only access to all objects
GRANT SELECT ON ALL TABLES IN DATABASE IDENTIFIER(&database_name) TO ROLE IDENTIFIER($auditor_role);
GRANT SELECT ON ALL VIEWS IN DATABASE IDENTIFIER(&database_name) TO ROLE IDENTIFIER($auditor_role);
GRANT SELECT ON ALL DYNAMIC TABLES IN SCHEMA smdh_tenant_${tenant_id}.aggregated TO ROLE IDENTIFIER($auditor_role);
GRANT SELECT ON FUTURE TABLES IN DATABASE IDENTIFIER(&database_name) TO ROLE IDENTIFIER($auditor_role);
GRANT SELECT ON FUTURE VIEWS IN DATABASE IDENTIFIER(&database_name) TO ROLE IDENTIFIER($auditor_role);

-- Grant access to audit logs in infrastructure database
GRANT USAGE ON DATABASE smdh_infrastructure TO ROLE IDENTIFIER($auditor_role);
GRANT USAGE ON SCHEMA smdh_infrastructure.audit TO ROLE IDENTIFIER($auditor_role);
GRANT SELECT ON ALL TABLES IN SCHEMA smdh_infrastructure.audit TO ROLE IDENTIFIER($auditor_role);

-- Grant monitoring access
GRANT MONITOR ON DATABASE IDENTIFIER(&database_name) TO ROLE IDENTIFIER($auditor_role);
GRANT MONITOR ON ALL WAREHOUSES IN ACCOUNT TO ROLE IDENTIFIER($auditor_role);

-- Grant warehouse access
GRANT USAGE ON WAREHOUSE smdh_monitoring_wh TO ROLE IDENTIFIER($auditor_role);

GRANT ROLE IDENTIFIER($auditor_role) TO ROLE SYSADMIN;

SELECT 'Created role: ' || $auditor_role AS result;

-- ============================================================================
-- 6. Create Role Hierarchy View
-- ============================================================================

SELECT '6. Creating Role Hierarchy View...' AS step;

USE SCHEMA analytics;

CREATE OR REPLACE VIEW v_role_hierarchy AS
SELECT
    grantee_name AS role_name,
    granted_on AS object_type,
    name AS object_name,
    privilege,
    granted_by,
    created_on
FROM SNOWFLAKE.ACCOUNT_USAGE.GRANTS_TO_ROLES
WHERE grantee_name LIKE 'smdh_tenant_' || '&tenant_id' || '%'
ORDER BY grantee_name, object_type, object_name;

SELECT 'Created view: V_ROLE_HIERARCHY' AS result;

-- ============================================================================
-- 7. Create User Management Procedures
-- ============================================================================

SELECT '7. Creating User Management Procedures...' AS step;

-- Procedure to create a new tenant user
CREATE OR REPLACE PROCEDURE sp_create_tenant_user(
    username_param VARCHAR,
    email_param VARCHAR,
    role_type_param VARCHAR,  -- 'admin', 'user', 'readonly', 'data_engineer', 'data_analyst', 'auditor'
    default_warehouse_param VARCHAR DEFAULT 'smdh_analytics_wh'
)
RETURNS STRING
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    full_role_name VARCHAR;
    user_exists BOOLEAN;
BEGIN
    -- Check if user already exists
    user_exists := (SELECT COUNT(*) > 0 FROM SNOWFLAKE.ACCOUNT_USAGE.USERS WHERE NAME = :username_param);

    IF (user_exists) THEN
        RETURN 'Error: User ' || :username_param || ' already exists';
    END IF;

    -- Determine full role name
    CASE :role_type_param
        WHEN 'admin' THEN
            full_role_name := 'smdh_tenant_' || '&tenant_id' || '_admin';
        WHEN 'user' THEN
            full_role_name := 'smdh_tenant_' || '&tenant_id' || '_user';
        WHEN 'readonly' THEN
            full_role_name := 'smdh_tenant_' || '&tenant_id' || '_readonly';
        WHEN 'data_engineer' THEN
            full_role_name := 'smdh_tenant_' || '&tenant_id' || '_data_engineer';
        WHEN 'data_analyst' THEN
            full_role_name := 'smdh_tenant_' || '&tenant_id' || '_data_analyst';
        WHEN 'auditor' THEN
            full_role_name := 'smdh_tenant_' || '&tenant_id' || '_auditor';
        ELSE
            RETURN 'Error: Invalid role_type. Use: admin, user, readonly, data_engineer, data_analyst, or auditor';
    END CASE;

    -- Create user
    EXECUTE IMMEDIATE
        'CREATE USER ' || :username_param ||
        ' DEFAULT_ROLE = ' || :full_role_name ||
        ' DEFAULT_WAREHOUSE = ' || :default_warehouse_param ||
        ' MUST_CHANGE_PASSWORD = TRUE' ||
        ' EMAIL = ''' || :email_param || '''';

    -- Grant role to user
    EXECUTE IMMEDIATE 'GRANT ROLE ' || :full_role_name || ' TO USER ' || :username_param;

    -- Log user creation
    INSERT INTO smdh_infrastructure.tenant_configs.tenant_users (
        tenant_id, username, email, role_name, is_active
    ) VALUES (
        &tenant_id, :username_param, :email_param, :full_role_name, TRUE
    );

    RETURN 'Successfully created user ' || :username_param || ' with role ' || :full_role_name;
EXCEPTION
    WHEN OTHER THEN
        RETURN 'Error creating user: ' || SQLERRM;
END;
$$;

SELECT 'Created procedure: SP_CREATE_TENANT_USER' AS result;

-- ============================================================================
-- 8. Document Roles
-- ============================================================================

SELECT '8. Documenting Roles...' AS step;

MERGE INTO schema_documentation AS target
USING (
    SELECT 'RBAC' AS schema_name, 'ROLE' AS object_type,
           'smdh_tenant_' || '&tenant_id' || '_admin' AS object_name,
           'Full admin access to tenant database and objects' AS description
    UNION ALL
    SELECT 'RBAC', 'ROLE', 'smdh_tenant_' || '&tenant_id' || '_user',
           'Standard user with read/write access to analytics'
    UNION ALL
    SELECT 'RBAC', 'ROLE', 'smdh_tenant_' || '&tenant_id' || '_readonly',
           'Read-only access for reporting and dashboards'
    UNION ALL
    SELECT 'RBAC', 'ROLE', 'smdh_tenant_' || '&tenant_id' || '_data_engineer',
           'ETL development access (streams, tasks, procedures)'
    UNION ALL
    SELECT 'RBAC', 'ROLE', 'smdh_tenant_' || '&tenant_id' || '_data_analyst',
           'Analytics development access (create views, tables in analytics schema)'
    UNION ALL
    SELECT 'RBAC', 'ROLE', 'smdh_tenant_' || '&tenant_id' || '_api_service',
           'Programmatic read-only access for external applications'
    UNION ALL
    SELECT 'RBAC', 'ROLE', 'smdh_tenant_' || '&tenant_id' || '_auditor',
           'Compliance and audit read-only access'
) AS source
ON target.schema_name = source.schema_name
    AND target.object_type = source.object_type
    AND target.object_name = source.object_name
WHEN NOT MATCHED THEN
    INSERT (schema_name, object_type, object_name, description)
    VALUES (source.schema_name, source.object_type, source.object_name, source.description);

SELECT 'Documented all roles' AS result;

-- ============================================================================
-- 9. Verification
-- ============================================================================

SELECT '9. Verifying Role Creation...' AS step;

-- Show all tenant roles
SHOW ROLES LIKE 'smdh_tenant_' || '&tenant_id' || '%';

-- Query role hierarchy
SELECT * FROM analytics.v_role_hierarchy LIMIT 20;

-- Show grants for each role
SELECT 'Role grants summary:' AS info;
SELECT
    grantee_name AS role_name,
    COUNT(*) AS privilege_count,
    COUNT(DISTINCT granted_on) AS object_type_count
FROM SNOWFLAKE.ACCOUNT_USAGE.GRANTS_TO_ROLES
WHERE grantee_name LIKE 'smdh_tenant_' || '&tenant_id' || '%'
GROUP BY grantee_name
ORDER BY grantee_name;

-- ============================================================================
-- 10. Summary
-- ============================================================================

SELECT '╔════════════════════════════════════════════════════════════════╗' AS summary
UNION ALL SELECT '║  Additional RBAC Configuration Complete                    ║'
UNION ALL SELECT '╚════════════════════════════════════════════════════════════╝'
UNION ALL SELECT ''
UNION ALL SELECT 'Tenant: ' || '&tenant_id'
UNION ALL SELECT ''
UNION ALL SELECT 'All Roles Created:'
UNION ALL SELECT '  ✓ _admin (full access)'
UNION ALL SELECT '  ✓ _user (standard read/write)'
UNION ALL SELECT '  ✓ _readonly (reporting only)'
UNION ALL SELECT '  ✓ _data_engineer (ETL development)'
UNION ALL SELECT '  ✓ _data_analyst (analytics development)'
UNION ALL SELECT '  ✓ _api_service (programmatic access)'
UNION ALL SELECT '  ✓ _auditor (compliance/audit)'
UNION ALL SELECT ''
UNION ALL SELECT 'Role Capabilities:'
UNION ALL SELECT '  • Admin: All database operations, task/stream management'
UNION ALL SELECT '  • User: Read/write analytics, read normalized data'
UNION ALL SELECT '  • Readonly: View all data, no modifications'
UNION ALL SELECT '  • Data Engineer: Create/modify ETL objects, streams, tasks'
UNION ALL SELECT '  • Data Analyst: Create views/tables in analytics schema'
UNION ALL SELECT '  • API Service: Read-only for external applications'
UNION ALL SELECT '  • Auditor: Read-only + audit log access + monitoring'
UNION ALL SELECT ''
UNION ALL SELECT 'Management:'
UNION ALL SELECT '  ✓ v_role_hierarchy (view)'
UNION ALL SELECT '  ✓ sp_create_tenant_user (procedure)'
UNION ALL SELECT ''
UNION ALL SELECT 'Creating Users:'
UNION ALL SELECT '  CALL analytics.sp_create_tenant_user('
UNION ALL SELECT '    ''john_smith'','
UNION ALL SELECT '    ''john@company.com'','
UNION ALL SELECT '    ''data_analyst'','
UNION ALL SELECT '    ''smdh_analytics_wh'''
UNION ALL SELECT '  );'
UNION ALL SELECT ''
UNION ALL SELECT 'Querying Roles:'
UNION ALL SELECT '  SELECT * FROM analytics.v_role_hierarchy;'
UNION ALL SELECT '  SHOW GRANTS TO ROLE smdh_tenant_' || '&tenant_id' || '_data_analyst;'
UNION ALL SELECT ''
UNION ALL SELECT 'Next Steps:'
UNION ALL SELECT '  1. Run 17_create_monitoring.sql for monitoring dashboards'
UNION ALL SELECT '  2. Create initial tenant users using sp_create_tenant_user'
UNION ALL SELECT '  3. Configure SSO for user authentication (optional)'
UNION ALL SELECT '============================================================';
