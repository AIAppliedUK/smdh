-- Quick check to see what SMDH databases exist in Snowflake
USE ROLE ACCOUNTADMIN;

-- Show all SMDH databases
SHOW DATABASES LIKE 'smdh%';

-- Check if tenant database exists
SELECT COUNT(*) as tenant_db_exists
FROM INFORMATION_SCHEMA.DATABASES
WHERE DATABASE_NAME = 'SMDH_TENANT_TEST_TENANT';

-- If infrastructure database exists, check tenants table
SELECT 'Checking Infrastructure Database...' AS step;
USE DATABASE smdh_infrastructure;
SELECT * FROM tenant_configs.tenants;
