-- SMDH Platform - Complete Infrastructure Cleanup
-- Drops all SMDH databases and objects to allow clean recreation
-- Run this script with ACCOUNTADMIN role

USE ROLE ACCOUNTADMIN;

-- Display banner
SELECT '╔════════════════════════════════════════════════════════════════╗' AS banner
UNION ALL SELECT '║  SMDH Platform - Infrastructure Cleanup                   ║'
UNION ALL SELECT '║  WARNING: This will DROP all SMDH databases!               ║'
UNION ALL SELECT '╚════════════════════════════════════════════════════════════╝';

-- Drop infrastructure database (cascades to all dependent objects)
DROP DATABASE IF EXISTS smdh_infrastructure CASCADE;

-- Drop roles
DROP ROLE IF EXISTS smdh_infrastructure_admin;
DROP ROLE IF EXISTS smdh_monitoring;

-- Display completion message
SELECT '╔════════════════════════════════════════════════════════════════╗' AS summary
UNION ALL SELECT '║  SMDH Infrastructure Cleanup Complete                      ║'
UNION ALL SELECT '╚════════════════════════════════════════════════════════════╝'
UNION ALL SELECT ''
UNION ALL SELECT 'All SMDH infrastructure has been dropped.'
UNION ALL SELECT ''
UNION ALL SELECT 'You can now run 01_infrastructure_setup.sql for a clean setup.';
