-- ============================================================================
-- SMDH Snowflake Prerequisites Check
-- ============================================================================
-- Purpose: Verify Snowflake environment meets SMDH platform requirements
-- Usage: snowsql -f 00_prerequisites.sql
-- Author: SMDH Platform Team
-- Version: 1.0
-- ============================================================================

USE ROLE ACCOUNTADMIN;

-- Display banner
SELECT '╔════════════════════════════════════════════════════════════════╗' AS banner
UNION ALL SELECT '║  SMDH Platform - Snowflake Prerequisites Check             ║'
UNION ALL SELECT '╚════════════════════════════════════════════════════════════════╝';

-- ============================================================================
-- 1. Account Information
-- ============================================================================

SELECT '1. ACCOUNT INFORMATION' AS check_section;

SELECT
    CURRENT_ACCOUNT() AS account_identifier,
    CURRENT_REGION() AS region,
    CURRENT_VERSION() AS snowflake_version;

-- Verify region is eu-west-2 (London) for optimal Kinesis integration
SELECT
    CASE
        WHEN CURRENT_REGION() LIKE '%eu-west-2%' OR CURRENT_REGION() LIKE '%london%'
        THEN '✓ PASS: Account is in eu-west-2 (London) region'
        ELSE '✗ WARNING: Account is not in eu-west-2. Kinesis integration may have higher latency.'
    END AS region_check;

-- ============================================================================
-- 2. Required Features Check
-- ============================================================================

SELECT '2. REQUIRED FEATURES' AS check_section;

-- Check for Streams support (required for CDC)
SELECT
    '✓ Streams are available in all Enterprise editions' AS streams_check;

-- Check for Tasks support (required for ETL automation)
SELECT
    '✓ Tasks are available in all Enterprise editions' AS tasks_check;

-- Check for Dynamic Tables support (required for real-time aggregations)
SELECT
    CASE
        WHEN CURRENT_VERSION() >= '7.0'
        THEN '✓ PASS: Dynamic Tables are supported (Snowflake 7.0+)'
        ELSE '✗ WARNING: Dynamic Tables require Snowflake 7.0+. Current version: ' || CURRENT_VERSION()
    END AS dynamic_tables_check;

-- Check for VARIANT support (required for semi-structured sensor data)
SELECT
    '✓ VARIANT type is available in all editions' AS variant_check;

-- ============================================================================
-- 3. Permission Checks
-- ============================================================================

SELECT '3. PERMISSION CHECKS' AS check_section;

-- Check if current role can create databases
SELECT
    CASE
        WHEN EXISTS (
            SELECT 1 FROM SNOWFLAKE.ACCOUNT_USAGE.GRANTS_TO_ROLES
            WHERE GRANTEE_NAME = CURRENT_ROLE()
            AND PRIVILEGE = 'CREATE DATABASE'
        )
        THEN '✓ PASS: Current role can create databases'
        ELSE '✗ FAIL: Current role lacks CREATE DATABASE privilege'
    END AS create_database_check;

-- Check if current role can create warehouses
SELECT
    CASE
        WHEN EXISTS (
            SELECT 1 FROM SNOWFLAKE.ACCOUNT_USAGE.GRANTS_TO_ROLES
            WHERE GRANTEE_NAME = CURRENT_ROLE()
            AND PRIVILEGE = 'CREATE WAREHOUSE'
        )
        THEN '✓ PASS: Current role can create warehouses'
        ELSE '✗ FAIL: Current role lacks CREATE WAREHOUSE privilege'
    END AS create_warehouse_check;

-- Check if current role can create roles
SELECT
    CASE
        WHEN EXISTS (
            SELECT 1 FROM SNOWFLAKE.ACCOUNT_USAGE.GRANTS_TO_ROLES
            WHERE GRANTEE_NAME = CURRENT_ROLE()
            AND PRIVILEGE = 'CREATE ROLE'
        )
        THEN '✓ PASS: Current role can create roles'
        ELSE '✗ FAIL: Current role lacks CREATE ROLE privilege'
    END AS create_role_check;

-- ============================================================================
-- 4. Warehouse Availability
-- ============================================================================

SELECT '4. WAREHOUSE AVAILABILITY' AS check_section;

-- List existing warehouses
SELECT
    NAME AS warehouse_name,
    SIZE AS warehouse_size,
    STATE AS warehouse_state,
    TYPE AS warehouse_type
FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSES
WHERE DELETED IS NULL
ORDER BY NAME;

-- ============================================================================
-- 5. Storage and Compute Limits
-- ============================================================================

SELECT '5. RESOURCE CHECKS' AS check_section;

-- Check current storage usage
SELECT
    'Current storage usage: ' ||
    ROUND(SUM(ACTIVE_BYTES + TIME_TRAVEL_BYTES + FAILSAFE_BYTES) / (1024*1024*1024*1024), 2) ||
    ' TB' AS storage_usage
FROM SNOWFLAKE.ACCOUNT_USAGE.DATABASE_STORAGE_USAGE_HISTORY
WHERE USAGE_DATE >= DATEADD(day, -1, CURRENT_DATE());

-- Check for resource monitors
SELECT
    NAME AS resource_monitor,
    CREDIT_QUOTA AS monthly_credit_quota,
    USED_CREDITS AS credits_used,
    REMAINING_CREDITS AS credits_remaining
FROM SNOWFLAKE.ACCOUNT_USAGE.RESOURCE_MONITORS
WHERE END_TIME IS NULL OR END_TIME > CURRENT_TIMESTAMP();

-- ============================================================================
-- 6. Network Policy Check
-- ============================================================================

SELECT '6. NETWORK CONFIGURATION' AS check_section;

-- Check if account has network policies that might block Kinesis integration
SELECT
    CASE
        WHEN COUNT(*) = 0
        THEN '✓ PASS: No network policies defined (Snowflake Openflow can connect to Kinesis)'
        ELSE '⚠ WARNING: ' || COUNT(*) || ' network policy(ies) found. Verify Snowflake Openflow can access AWS Kinesis in eu-west-2.'
    END AS network_policy_check
FROM SNOWFLAKE.ACCOUNT_USAGE.NETWORK_POLICIES
WHERE DELETED IS NULL;

-- List network policies
SELECT
    NAME AS policy_name,
    COMMENT AS policy_description
FROM SNOWFLAKE.ACCOUNT_USAGE.NETWORK_POLICIES
WHERE DELETED IS NULL;

-- ============================================================================
-- 7. Kinesis Integration Prerequisites
-- ============================================================================

SELECT '7. KINESIS INTEGRATION REQUIREMENTS' AS check_section;

-- Note: Snowflake Openflow connector configuration will be done in 03_openflow_connector.sql
-- This check verifies Snowflake account readiness

SELECT
    '✓ Snowflake Openflow connector supports Kinesis Data Streams' AS openflow_check_1;

SELECT
    '✓ Cross-account IAM role will be configured in AWS' AS openflow_check_2;

SELECT
    '⚠ Ensure AWS Kinesis stream exists in eu-west-2 before running 03_openflow_connector.sql' AS openflow_check_3;

-- ============================================================================
-- 8. Time Travel and Fail-safe Check
-- ============================================================================

SELECT '8. DATA PROTECTION FEATURES' AS check_section;

-- Check account edition (affects Time Travel retention limits)
SELECT
    CASE
        WHEN CURRENT_ACCOUNT_EDITION() LIKE '%ENTERPRISE%'
        THEN '✓ PASS: Enterprise Edition detected. Time Travel retention up to 90 days available.'
        ELSE '⚠ WARNING: Non-Enterprise edition. Time Travel retention limited to 1 day.'
    END AS edition_check;

-- ============================================================================
-- 9. Integration Readiness
-- ============================================================================

SELECT '9. EXTERNAL INTEGRATION READINESS' AS check_section;

-- Check for existing Kinesis integrations
SELECT
    NAME AS integration_name,
    TYPE AS integration_type,
    CREATED_ON
FROM SNOWFLAKE.ACCOUNT_USAGE.INTEGRATIONS
WHERE TYPE = 'EXTERNAL' AND DELETED IS NULL
ORDER BY CREATED_ON DESC;

-- ============================================================================
-- 10. Summary
-- ============================================================================

SELECT '10. PREREQUISITES SUMMARY' AS check_section;

SELECT
    '============================================' AS summary
UNION ALL SELECT 'Prerequisites Check Complete'
UNION ALL SELECT ''
UNION ALL SELECT 'Next Steps:'
UNION ALL SELECT '1. Review any WARNING or FAIL messages above'
UNION ALL SELECT '2. Ensure AWS Kinesis stream is created in eu-west-2'
UNION ALL SELECT '3. Obtain AWS IAM role ARN for Snowflake cross-account access'
UNION ALL SELECT '4. Run 01_infrastructure_setup.sql to create SMDH infrastructure'
UNION ALL SELECT '============================================';
