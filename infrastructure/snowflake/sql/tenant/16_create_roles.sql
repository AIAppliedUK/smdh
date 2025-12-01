-- ============================================================================
-- SMDH Tenant RBAC Configuration (Additional Roles)
-- ============================================================================
-- Purpose: Create additional tenant-specific roles for fine-grained access control
-- Usage: snowsql -f tenant/16_create_roles.sql --variable tenant_id='company_a'
-- Author: SMDH Platform Team
-- Version: 1.0
-- ============================================================================
-- This script creates optional additional roles:
-- - Data Engineer role (for ETL development)
-- - Data Analyst role (for analytics work)
-- - API Service Account role (for programmatic access)
-- - Auditor role (read-only access for compliance)
-- ============================================================================

-- Enable SnowSQL variable substitution 
!set variable_substitution=true

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE SMDH_WH;

-- Convert SnowSQL substitution variables to session variables
SET tenant_id = '&tenant_id';

-- Display banner
SELECT '╔════════════════════════════════════════════════════════════════╗' AS banner
UNION ALL SELECT '║  SMDH Platform - Additional RBAC Configuration             ║'
UNION ALL SELECT '╚════════════════════════════════════════════════════════════╝';

-- ============================================================================
-- 1. Validate Tenant Database
-- ============================================================================

SELECT '1. Validating Tenant Database...' AS step;

SET database_name = 'smdh_tenant_' || $tenant_id;
SET tenant_prefix = 'smdh_tenant_' || $tenant_id;

USE DATABASE IDENTIFIER($database_name);

SELECT 'Using database: ' || $database_name AS info;

-- Note: Verify existing roles using SHOW ROLES IN DATABASE after creation

-- ============================================================================
-- 2. Create Data Engineer Role
-- ============================================================================

SELECT '2. Creating Data Engineer Role...' AS step;

SET data_engineer_role = $tenant_prefix || '_data_engineer';

CREATE ROLE IF NOT EXISTS IDENTIFIER($data_engineer_role)
    COMMENT = 'Data Engineer role for tenant. Can create and modify ETL objects (streams, tasks, procedures).';

-- Grant database access
GRANT USAGE ON DATABASE IDENTIFIER($database_name) TO ROLE IDENTIFIER($data_engineer_role);
GRANT USAGE ON ALL SCHEMAS IN DATABASE IDENTIFIER($database_name) TO ROLE IDENTIFIER($data_engineer_role);

-- Grant full access to RAW and NORMALIZED schemas (for ETL development)
GRANT ALL ON SCHEMA raw TO ROLE IDENTIFIER($data_engineer_role);
GRANT ALL ON SCHEMA normalized TO ROLE IDENTIFIER($data_engineer_role);
GRANT ALL ON ALL TABLES IN SCHEMA raw TO ROLE IDENTIFIER($data_engineer_role);
GRANT ALL ON ALL TABLES IN SCHEMA normalized TO ROLE IDENTIFIER($data_engineer_role);
GRANT ALL ON FUTURE TABLES IN SCHEMA raw TO ROLE IDENTIFIER($data_engineer_role);
GRANT ALL ON FUTURE TABLES IN SCHEMA normalized TO ROLE IDENTIFIER($data_engineer_role);

-- Grant stream and task management
GRANT ALL ON ALL STREAMS IN DATABASE IDENTIFIER($database_name) TO ROLE IDENTIFIER($data_engineer_role);
GRANT ALL ON FUTURE STREAMS IN DATABASE IDENTIFIER($database_name) TO ROLE IDENTIFIER($data_engineer_role);
GRANT ALL ON ALL TASKS IN DATABASE IDENTIFIER($database_name) TO ROLE IDENTIFIER($data_engineer_role);
GRANT ALL ON FUTURE TASKS IN DATABASE IDENTIFIER($database_name) TO ROLE IDENTIFIER($data_engineer_role);

-- Grant read access to AGGREGATED and ANALYTICS (for validation)
GRANT SELECT ON ALL TABLES IN SCHEMA aggregated TO ROLE IDENTIFIER($data_engineer_role);
GRANT SELECT ON ALL DYNAMIC TABLES IN SCHEMA aggregated TO ROLE IDENTIFIER($data_engineer_role);
GRANT SELECT ON ALL VIEWS IN SCHEMA analytics TO ROLE IDENTIFIER($data_engineer_role);

-- Grant warehouse access
GRANT USAGE ON WAREHOUSE SMDH_WH TO ROLE IDENTIFIER($data_engineer_role);

GRANT ROLE IDENTIFIER($data_engineer_role) TO ROLE SYSADMIN;

SELECT 'Created role: ' || $data_engineer_role AS result;

-- ============================================================================
-- 3. Create Data Analyst Role
-- ============================================================================

SELECT '3. Creating Data Analyst Role...' AS step;

SET data_analyst_role = $tenant_prefix || '_data_analyst';

CREATE ROLE IF NOT EXISTS IDENTIFIER($data_analyst_role)
    COMMENT = 'Data Analyst role for tenant. Read/write access to analytics objects only.';

-- Grant database access
GRANT USAGE ON DATABASE IDENTIFIER($database_name) TO ROLE IDENTIFIER($data_analyst_role);
GRANT USAGE ON ALL SCHEMAS IN DATABASE IDENTIFIER($database_name) TO ROLE IDENTIFIER($data_analyst_role);

-- Grant read access to NORMALIZED and AGGREGATED
GRANT SELECT ON ALL TABLES IN SCHEMA normalized TO ROLE IDENTIFIER($data_analyst_role);
GRANT SELECT ON FUTURE TABLES IN SCHEMA normalized TO ROLE IDENTIFIER($data_analyst_role);
GRANT SELECT ON ALL TABLES IN SCHEMA aggregated TO ROLE IDENTIFIER($data_analyst_role);
GRANT SELECT ON ALL DYNAMIC TABLES IN SCHEMA aggregated TO ROLE IDENTIFIER($data_analyst_role);
GRANT SELECT ON FUTURE TABLES IN SCHEMA aggregated TO ROLE IDENTIFIER($data_analyst_role);

-- Grant full access to ANALYTICS schema (for creating custom views/tables)
GRANT ALL ON SCHEMA analytics TO ROLE IDENTIFIER($data_analyst_role);
GRANT ALL ON ALL TABLES IN SCHEMA analytics TO ROLE IDENTIFIER($data_analyst_role);
GRANT ALL ON ALL VIEWS IN SCHEMA analytics TO ROLE IDENTIFIER($data_analyst_role);
GRANT ALL ON FUTURE TABLES IN SCHEMA analytics TO ROLE IDENTIFIER($data_analyst_role);
GRANT ALL ON FUTURE VIEWS IN SCHEMA analytics TO ROLE IDENTIFIER($data_analyst_role);

-- Grant warehouse access
GRANT USAGE ON WAREHOUSE SMDH_WH TO ROLE IDENTIFIER($data_analyst_role);

GRANT ROLE IDENTIFIER($data_analyst_role) TO ROLE SYSADMIN;

SELECT 'Created role: ' || $data_analyst_role AS result;

-- ============================================================================
-- 4. Create API Service Account Role
-- ============================================================================

SELECT '4. Creating API Service Account Role...' AS step;

SET api_service_role = $tenant_prefix || '_api_service';

CREATE ROLE IF NOT EXISTS IDENTIFIER($api_service_role)
    COMMENT = 'API Service Account role for tenant. Programmatic read access for external applications.';

-- Grant database access
GRANT USAGE ON DATABASE IDENTIFIER($database_name) TO ROLE IDENTIFIER($api_service_role);
GRANT USAGE ON ALL SCHEMAS IN DATABASE IDENTIFIER($database_name) TO ROLE IDENTIFIER($api_service_role);

-- Grant read-only access to all data schemas
GRANT SELECT ON ALL TABLES IN DATABASE IDENTIFIER($database_name) TO ROLE IDENTIFIER($api_service_role);
GRANT SELECT ON ALL VIEWS IN DATABASE IDENTIFIER($database_name) TO ROLE IDENTIFIER($api_service_role);
GRANT SELECT ON ALL DYNAMIC TABLES IN SCHEMA aggregated TO ROLE IDENTIFIER($api_service_role);
GRANT SELECT ON FUTURE TABLES IN DATABASE IDENTIFIER($database_name) TO ROLE IDENTIFIER($api_service_role);
GRANT SELECT ON FUTURE VIEWS IN DATABASE IDENTIFIER($database_name) TO ROLE IDENTIFIER($api_service_role);

-- Grant warehouse access (small warehouse for API queries)
GRANT USAGE ON WAREHOUSE SMDH_WH TO ROLE IDENTIFIER($api_service_role);

GRANT ROLE IDENTIFIER($api_service_role) TO ROLE SYSADMIN;

SELECT 'Created role: ' || $api_service_role AS result;

-- ============================================================================
-- 5. Create Auditor Role
-- ============================================================================

SELECT '5. Creating Auditor Role...' AS step;

SET auditor_role = $tenant_prefix || '_auditor';

CREATE ROLE IF NOT EXISTS IDENTIFIER($auditor_role)
    COMMENT = 'Auditor role for tenant. Read-only access for compliance and audit purposes.';

-- Grant database usage
GRANT USAGE ON DATABASE IDENTIFIER($database_name) TO ROLE IDENTIFIER($auditor_role);
GRANT USAGE ON ALL SCHEMAS IN DATABASE IDENTIFIER($database_name) TO ROLE IDENTIFIER($auditor_role);

-- Grant read-only access to all objects
GRANT SELECT ON ALL TABLES IN DATABASE IDENTIFIER($database_name) TO ROLE IDENTIFIER($auditor_role);
GRANT SELECT ON ALL VIEWS IN DATABASE IDENTIFIER($database_name) TO ROLE IDENTIFIER($auditor_role);
GRANT SELECT ON ALL DYNAMIC TABLES IN SCHEMA aggregated TO ROLE IDENTIFIER($auditor_role);
GRANT SELECT ON FUTURE TABLES IN DATABASE IDENTIFIER($database_name) TO ROLE IDENTIFIER($auditor_role);
GRANT SELECT ON FUTURE VIEWS IN DATABASE IDENTIFIER($database_name) TO ROLE IDENTIFIER($auditor_role);

-- Grant access to audit logs in infrastructure database
GRANT USAGE ON DATABASE smdh_infrastructure TO ROLE IDENTIFIER($auditor_role);
GRANT USAGE ON SCHEMA smdh_infrastructure.audit TO ROLE IDENTIFIER($auditor_role);
GRANT SELECT ON ALL TABLES IN SCHEMA smdh_infrastructure.audit TO ROLE IDENTIFIER($auditor_role);

-- Grant monitoring access
GRANT MONITOR ON DATABASE IDENTIFIER($database_name) TO ROLE IDENTIFIER($auditor_role);

-- Grant warehouse access
GRANT USAGE ON WAREHOUSE SMDH_WH TO ROLE IDENTIFIER($auditor_role);

GRANT ROLE IDENTIFIER($auditor_role) TO ROLE SYSADMIN;

SELECT 'Created role: ' || $auditor_role AS result;

-- ============================================================================
-- 6. Create Role Hierarchy View
-- ============================================================================

SELECT '6. Creating Role Hierarchy View...' AS step;

USE SCHEMA analytics;

-- Note: View is created with tenant pattern embedded at creation time
SET role_like_pattern = 'smdh_tenant_' || $tenant_id || '%';

CREATE OR REPLACE VIEW v_role_hierarchy AS
SELECT
    grantee_name AS role_name,
    granted_on AS object_type,
    name AS object_name,
    privilege,
    granted_by,
    created_on
FROM SNOWFLAKE.ACCOUNT_USAGE.GRANTS_TO_ROLES
WHERE grantee_name LIKE $role_like_pattern
ORDER BY grantee_name, object_type, object_name;

SELECT 'Created view: V_ROLE_HIERARCHY' AS result;

-- ============================================================================
-- 7. Create User Management Procedures
-- ============================================================================

SELECT '7. Creating User Management Procedures...' AS step;

-- Procedure to create a new tenant user
-- Note: tenant_id_param is required because session variables are not available inside stored procedures
CREATE OR REPLACE PROCEDURE sp_create_tenant_user(
    tenant_id_param VARCHAR,
    username_param VARCHAR,
    email_param VARCHAR,
    role_type_param VARCHAR,  -- 'admin', 'user', 'readonly', 'data_engineer', 'data_analyst', 'auditor'
    default_warehouse_param VARCHAR DEFAULT 'SMDH_WH'
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
            full_role_name := 'smdh_tenant_' || :tenant_id_param || '_admin';
        WHEN 'user' THEN
            full_role_name := 'smdh_tenant_' || :tenant_id_param || '_user';
        WHEN 'readonly' THEN
            full_role_name := 'smdh_tenant_' || :tenant_id_param || '_readonly';
        WHEN 'data_engineer' THEN
            full_role_name := 'smdh_tenant_' || :tenant_id_param || '_data_engineer';
        WHEN 'data_analyst' THEN
            full_role_name := 'smdh_tenant_' || :tenant_id_param || '_data_analyst';
        WHEN 'auditor' THEN
            full_role_name := 'smdh_tenant_' || :tenant_id_param || '_auditor';
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
        :tenant_id_param, :username_param, :email_param, :full_role_name, TRUE
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

-- Note: Role documentation is handled in 17_create_monitoring.sql
-- where schema_documentation table is created
SELECT 'Role documentation will be added in monitoring setup' AS result;

-- ============================================================================
-- 9. Verification
-- ============================================================================

SELECT '9. Verifying Role Creation...' AS step;

-- Show all tenant roles (uses role_like_pattern set earlier)
SHOW ROLES;

-- Query role hierarchy
SELECT * FROM analytics.v_role_hierarchy LIMIT 20;

-- Show grants summary for tenant roles
SELECT 'Role grants summary:' AS info;
SELECT
    grantee_name AS role_name,
    COUNT(*) AS privilege_count,
    COUNT(DISTINCT granted_on) AS object_type_count
FROM SNOWFLAKE.ACCOUNT_USAGE.GRANTS_TO_ROLES
WHERE grantee_name LIKE $role_like_pattern
GROUP BY grantee_name
ORDER BY grantee_name;

-- ============================================================================
-- 10. Summary
-- ============================================================================

SELECT '╔════════════════════════════════════════════════════════════════╗' AS summary;
SELECT '║  Additional RBAC Configuration Complete                    ║';
SELECT '╚════════════════════════════════════════════════════════════╝';
SELECT 'Tenant: ' || $tenant_id AS tenant_info;
SELECT 'All Roles Created: _admin, _user, _readonly, _data_engineer, _data_analyst, _api_service, _auditor' AS created_roles;
SELECT 'Views: v_role_hierarchy | Procedures: sp_create_tenant_user' AS created_objects;
