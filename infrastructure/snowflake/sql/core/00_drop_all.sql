-- ============================================================================
-- SMDH Platform - Complete Infrastructure Cleanup
-- ============================================================================
-- Drops ALL SMDH databases including tenant databases
-- Run this script with ACCOUNTADMIN role
-- ============================================================================
-- WARNING: This will DROP ALL SMDH databases including tenant data!
-- ============================================================================

USE ROLE ACCOUNTADMIN;

-- Display banner
SELECT '╔════════════════════════════════════════════════════════════════╗' AS banner
UNION ALL SELECT '║  SMDH Platform - COMPLETE Infrastructure Cleanup          ║'
UNION ALL SELECT '║  WARNING: This will DROP ALL SMDH databases!              ║'
UNION ALL SELECT '║  INCLUDING ALL TENANT DATA!                                ║'
UNION ALL SELECT '╚════════════════════════════════════════════════════════════════╝';

-- ============================================================================
-- 1. Drop ALL Tenant Databases
-- ============================================================================

SELECT '1. Dropping ALL Tenant Databases...' AS step;

-- Drop known tenant databases (add more as needed)
DROP DATABASE IF EXISTS SMDH_TENANT_TEST_TENANT CASCADE;
DROP DATABASE IF EXISTS SMDH_TENANT_TEST_CORP CASCADE;

-- Drop tenant roles
DROP ROLE IF EXISTS SMDH_TENANT_TEST_TENANT_ADMIN;
DROP ROLE IF EXISTS SMDH_TENANT_TEST_TENANT_USER;
DROP ROLE IF EXISTS SMDH_TENANT_TEST_TENANT_READONLY;
DROP ROLE IF EXISTS SMDH_TENANT_TEST_CORP_ADMIN;
DROP ROLE IF EXISTS SMDH_TENANT_TEST_CORP_USER;
DROP ROLE IF EXISTS SMDH_TENANT_TEST_CORP_READONLY;

SELECT 'Dropped all tenant databases and roles' AS result;

-- ============================================================================
-- 2. Drop Openflow Database (from 03_openflow_connector.sql)
-- ============================================================================

SELECT '2. Dropping Openflow Database...' AS step;

DROP DATABASE IF EXISTS SMDH_OPENFLOW CASCADE;

SELECT 'Dropped database: SMDH_OPENFLOW' AS result;

-- ============================================================================
-- 2. Drop Infrastructure Database (from 01_infrastructure_setup.sql)
-- ============================================================================

SELECT '2. Dropping Infrastructure Database...' AS step;

DROP DATABASE IF EXISTS SMDH_INFRASTRUCTURE CASCADE;

SELECT 'Dropped database: SMDH_INFRASTRUCTURE' AS result;

-- ============================================================================
-- 3. Drop Openflow Roles (from 03_openflow_connector.sql)
-- ============================================================================

SELECT '3. Dropping Openflow Roles...' AS step;

DROP ROLE IF EXISTS OPENFLOW_RUNTIME_ROLE_KINESIS;
DROP ROLE IF EXISTS OPENFLOW_ADMIN;

SELECT 'Dropped roles: OPENFLOW_ADMIN, OPENFLOW_RUNTIME_ROLE_KINESIS' AS result;

-- ============================================================================
-- 4. Drop Platform Roles (from 02_shared_resources.sql)
-- ============================================================================

SELECT '4. Dropping Platform Roles...' AS step;

DROP ROLE IF EXISTS SMDH_ANALYTICS_USER;
DROP ROLE IF EXISTS SMDH_DATA_ENGINEER;
DROP ROLE IF EXISTS SMDH_TENANT_OPERATOR;
DROP ROLE IF EXISTS SMDH_MONITORING;
DROP ROLE IF EXISTS SMDH_INFRASTRUCTURE_ADMIN;

SELECT 'Dropped platform roles' AS result;

-- ============================================================================
-- 5. Drop External Access Integration (from 03_openflow_connector.sql)
-- ============================================================================

SELECT '5. Dropping External Access Integration...' AS step;

DROP INTEGRATION IF EXISTS OPENFLOW_AWS_EAI;

SELECT 'Dropped integration: OPENFLOW_AWS_EAI' AS result;

-- ============================================================================
-- 6. Drop Warehouse (optional - uncomment if needed)
-- ============================================================================

-- Uncomment the following lines to also drop the warehouse
-- SELECT '6. Dropping Warehouse...' AS step;
-- DROP WAREHOUSE IF EXISTS SMDH_WH;
-- SELECT 'Dropped warehouse: SMDH_WH' AS result;

-- ============================================================================
-- 7. Drop Resource Monitor (optional - uncomment if needed)
-- ============================================================================

-- Uncomment to drop resource monitor
-- DROP RESOURCE MONITOR IF EXISTS SMDH_PLATFORM_MONITOR;

-- ============================================================================
-- Summary
-- ============================================================================

SELECT '╔════════════════════════════════════════════════════════════════╗' AS summary
UNION ALL SELECT '║  SMDH COMPLETE Infrastructure Cleanup Done                 ║'
UNION ALL SELECT '╚════════════════════════════════════════════════════════════════╝'
UNION ALL SELECT ''
UNION ALL SELECT 'Dropped Resources:'
UNION ALL SELECT '  [OK] Tenant Databases: SMDH_TENANT_*'
UNION ALL SELECT '  [OK] Tenant Roles: SMDH_TENANT_*_ADMIN/USER/READONLY'
UNION ALL SELECT '  [OK] Database: SMDH_OPENFLOW'
UNION ALL SELECT '  [OK] Database: SMDH_INFRASTRUCTURE'
UNION ALL SELECT '  [OK] Role: OPENFLOW_ADMIN'
UNION ALL SELECT '  [OK] Role: OPENFLOW_RUNTIME_ROLE_KINESIS'
UNION ALL SELECT '  [OK] Role: SMDH_INFRASTRUCTURE_ADMIN'
UNION ALL SELECT '  [OK] Role: SMDH_MONITORING'
UNION ALL SELECT '  [OK] Role: SMDH_TENANT_OPERATOR'
UNION ALL SELECT '  [OK] Role: SMDH_DATA_ENGINEER'
UNION ALL SELECT '  [OK] Role: SMDH_ANALYTICS_USER'
UNION ALL SELECT '  [OK] Integration: OPENFLOW_AWS_EAI'
UNION ALL SELECT ''
UNION ALL SELECT 'To recreate everything, run in order:'
UNION ALL SELECT '  Phase 2 (Core):'
UNION ALL SELECT '    1. snowsql -f sql/core/01_infrastructure_setup.sql'
UNION ALL SELECT '    2. snowsql -f sql/core/02_shared_resources.sql'
UNION ALL SELECT '    3. snowsql -f sql/core/03_openflow_connector.sql'
UNION ALL SELECT ''
UNION ALL SELECT '  Phase 3 (Per Tenant):'
UNION ALL SELECT '    snowsql -f sql/tenant/10_create_tenant_database.sql --variable tenant_id=xxx ...'
UNION ALL SELECT '    snowsql -f sql/tenant/11_create_schemas.sql --variable tenant_id=xxx'
UNION ALL SELECT '    snowsql -f sql/tenant/12_create_tables.sql --variable tenant_id=xxx'
UNION ALL SELECT '    snowsql -f sql/tenant/13_create_streams.sql --variable tenant_id=xxx'
UNION ALL SELECT '    ... (14-17)';
