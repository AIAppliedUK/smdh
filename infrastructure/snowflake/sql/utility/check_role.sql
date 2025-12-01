-- Check what role you're currently using
SELECT CURRENT_ROLE() AS current_role;

-- Check what roles are available to you
SHOW GRANTS TO USER CURRENT_USER();

-- Try to explicitly use ACCOUNTADMIN
USE ROLE ACCOUNTADMIN;
SELECT 'Successfully switched to ACCOUNTADMIN' AS status;

-- Check privileges of ACCOUNTADMIN role
SHOW GRANTS TO ROLE ACCOUNTADMIN;
