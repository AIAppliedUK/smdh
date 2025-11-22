-- ============================================================================
-- SMDH Shared Resources Setup
-- ============================================================================
-- Purpose: Create shared warehouses, roles, and resource monitors
-- Usage: snowsql -f 02_shared_resources.sql
-- Author: SMDH Platform Team
-- Version: 1.0
-- ============================================================================
-- This script creates:
-- - Virtual warehouses for different workloads
-- - Resource monitors for cost control
-- - Default system users for automation
-- - Warehouse grants to appropriate roles
-- ============================================================================

USE ROLE ACCOUNTADMIN;

-- Display banner
SELECT '╔════════════════════════════════════════════════════════════════╗' AS banner
UNION ALL SELECT '║  SMDH Platform - Shared Resources Setup                    ║'
UNION ALL SELECT '╚════════════════════════════════════════════════════════════╝';

-- ============================================================================
-- 1. Create Resource Monitor (Cost Control)
-- ============================================================================

SELECT '1. Creating Resource Monitor for Cost Control...' AS step;

CREATE RESOURCE MONITOR IF NOT EXISTS smdh_platform_monitor
WITH
    CREDIT_QUOTA = 1000                           -- Monthly credit limit
    FREQUENCY = MONTHLY                           -- Reset monthly
    START_TIMESTAMP = IMMEDIATELY                 -- Start monitoring now
    TRIGGERS
        ON 75 PERCENT DO NOTIFY                   -- Notify at 75% usage
        ON 90 PERCENT DO NOTIFY                   -- Notify at 90% usage
        ON 100 PERCENT DO SUSPEND                 -- Suspend at 100% usage
        ON 110 PERCENT DO SUSPEND_IMMEDIATE       -- Force suspend at 110%
    COMMENT = 'SMDH platform monthly credit monitor. Alerts at 75%, 90% and suspends at 100%.';

-- ============================================================================
-- 2. Create Ingestion Warehouse (Streaming Data Processing)
-- ============================================================================

SELECT '2. Creating Streaming Ingestion Warehouse...' AS step;

CREATE WAREHOUSE IF NOT EXISTS smdh_streaming_wh
WITH
    WAREHOUSE_SIZE = 'SMALL'                      -- Start small, can scale up
    WAREHOUSE_TYPE = 'STANDARD'
    AUTO_SUSPEND = 60                             -- Suspend after 1 minute idle
    AUTO_RESUME = TRUE                            -- Auto-resume on query
    MIN_CLUSTER_COUNT = 1
    MAX_CLUSTER_COUNT = 3                         -- Scale to 3 clusters under load
    SCALING_POLICY = 'STANDARD'
    INITIALLY_SUSPENDED = FALSE
    RESOURCE_MONITOR = smdh_platform_monitor
    COMMENT = 'Warehouse for streaming data ingestion from Kinesis via Openflow. Auto-scales with load.';

-- ============================================================================
-- 3. Create ETL Warehouse (Task Processing)
-- ============================================================================

SELECT '3. Creating ETL Processing Warehouse...' AS step;

CREATE WAREHOUSE IF NOT EXISTS smdh_etl_wh
WITH
    WAREHOUSE_SIZE = 'SMALL'
    WAREHOUSE_TYPE = 'STANDARD'
    AUTO_SUSPEND = 120                            -- Suspend after 2 minutes idle
    AUTO_RESUME = TRUE
    MIN_CLUSTER_COUNT = 1
    MAX_CLUSTER_COUNT = 2
    SCALING_POLICY = 'STANDARD'
    INITIALLY_SUSPENDED = TRUE                    -- Start suspended
    RESOURCE_MONITOR = smdh_platform_monitor
    COMMENT = 'Warehouse for scheduled tasks and ETL processing. Runs normalization and aggregation tasks.';

-- ============================================================================
-- 4. Create Analytics Warehouse (User Queries)
-- ============================================================================

SELECT '4. Creating Analytics Warehouse...' AS step;

CREATE WAREHOUSE IF NOT EXISTS smdh_analytics_wh
WITH
    WAREHOUSE_SIZE = 'SMALL'
    WAREHOUSE_TYPE = 'STANDARD'
    AUTO_SUSPEND = 300                            -- Suspend after 5 minutes idle
    AUTO_RESUME = TRUE
    MIN_CLUSTER_COUNT = 1
    MAX_CLUSTER_COUNT = 4                         -- Scale for multiple concurrent users
    SCALING_POLICY = 'STANDARD'
    INITIALLY_SUSPENDED = TRUE
    RESOURCE_MONITOR = smdh_platform_monitor
    COMMENT = 'Warehouse for analytics queries from Streamlit portal and Power BI. Multi-cluster for concurrency.';

-- ============================================================================
-- 5. Create Development Warehouse (Testing)
-- ============================================================================

SELECT '5. Creating Development Warehouse...' AS step;

CREATE WAREHOUSE IF NOT EXISTS smdh_dev_wh
WITH
    WAREHOUSE_SIZE = 'XSMALL'
    WAREHOUSE_TYPE = 'STANDARD'
    AUTO_SUSPEND = 60                             -- Suspend quickly
    AUTO_RESUME = TRUE
    MIN_CLUSTER_COUNT = 1
    MAX_CLUSTER_COUNT = 1                         -- No multi-cluster for dev
    SCALING_POLICY = 'STANDARD'
    INITIALLY_SUSPENDED = TRUE
    RESOURCE_MONITOR = smdh_platform_monitor
    COMMENT = 'Small warehouse for development and testing. Cost-optimized with quick auto-suspend.';

-- ============================================================================
-- 6. Create Monitoring Warehouse (System Queries)
-- ============================================================================

SELECT '6. Creating Monitoring Warehouse...' AS step;

CREATE WAREHOUSE IF NOT EXISTS smdh_monitoring_wh
WITH
    WAREHOUSE_SIZE = 'XSMALL'
    WAREHOUSE_TYPE = 'STANDARD'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    MIN_CLUSTER_COUNT = 1
    MAX_CLUSTER_COUNT = 1
    SCALING_POLICY = 'STANDARD'
    INITIALLY_SUSPENDED = TRUE
    RESOURCE_MONITOR = smdh_platform_monitor
    COMMENT = 'Minimal warehouse for monitoring queries and health checks. Always available, minimal cost.';

-- ============================================================================
-- 7. Create Tenant Operations Role
-- ============================================================================

SELECT '7. Creating Tenant Operations Role...' AS step;

CREATE ROLE IF NOT EXISTS smdh_tenant_operator
    COMMENT = 'Role for tenant onboarding and lifecycle management operations.';

-- Grant warehouse usage
GRANT USAGE ON WAREHOUSE smdh_streaming_wh TO ROLE smdh_tenant_operator;
GRANT USAGE ON WAREHOUSE smdh_etl_wh TO ROLE smdh_tenant_operator;
GRANT USAGE ON WAREHOUSE smdh_dev_wh TO ROLE smdh_tenant_operator;

-- Grant infrastructure database access
GRANT USAGE ON DATABASE smdh_infrastructure TO ROLE smdh_tenant_operator;
GRANT USAGE ON ALL SCHEMAS IN DATABASE smdh_infrastructure TO ROLE smdh_tenant_operator;
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA smdh_infrastructure.tenant_configs TO ROLE smdh_tenant_operator;
GRANT SELECT, INSERT ON ALL TABLES IN SCHEMA smdh_infrastructure.monitoring TO ROLE smdh_tenant_operator;

-- Grant database creation (for new tenants)
GRANT CREATE DATABASE ON ACCOUNT TO ROLE smdh_tenant_operator;

-- Grant role to SYSADMIN
GRANT ROLE smdh_tenant_operator TO ROLE SYSADMIN;

-- ============================================================================
-- 8. Create Data Engineer Role
-- ============================================================================

SELECT '8. Creating Data Engineer Role...' AS step;

CREATE ROLE IF NOT EXISTS smdh_data_engineer
    COMMENT = 'Role for data engineers managing ETL pipelines and data transformations.';

-- Grant warehouse usage
GRANT USAGE ON WAREHOUSE smdh_etl_wh TO ROLE smdh_data_engineer;
GRANT USAGE ON WAREHOUSE smdh_analytics_wh TO ROLE smdh_data_engineer;
GRANT USAGE ON WAREHOUSE smdh_dev_wh TO ROLE smdh_data_engineer;
GRANT OPERATE ON WAREHOUSE smdh_etl_wh TO ROLE smdh_data_engineer;

-- Grant infrastructure database access
GRANT USAGE ON DATABASE smdh_infrastructure TO ROLE smdh_data_engineer;
GRANT USAGE ON ALL SCHEMAS IN DATABASE smdh_infrastructure TO ROLE smdh_data_engineer;
GRANT SELECT ON ALL TABLES IN DATABASE smdh_infrastructure TO ROLE smdh_data_engineer;
GRANT SELECT ON FUTURE TABLES IN DATABASE smdh_infrastructure TO ROLE smdh_data_engineer;

-- Grant role to SYSADMIN
GRANT ROLE smdh_data_engineer TO ROLE SYSADMIN;

-- ============================================================================
-- 9. Create Analytics User Role (Template for Tenants)
-- ============================================================================

SELECT '9. Creating Analytics User Role Template...' AS step;

CREATE ROLE IF NOT EXISTS smdh_analytics_user
    COMMENT = 'Base role template for analytics users. Tenant-specific roles will inherit from this.';

-- Grant analytics warehouse usage only
GRANT USAGE ON WAREHOUSE smdh_analytics_wh TO ROLE smdh_analytics_user;

-- This role will be granted to tenant-specific roles
-- Each tenant role will inherit warehouse access but have database-specific permissions
GRANT ROLE smdh_analytics_user TO ROLE SYSADMIN;

-- ============================================================================
-- 10. Create Service Account for Automation
-- ============================================================================

SELECT '10. Creating Service Account for Automation...' AS step;

CREATE USER IF NOT EXISTS smdh_automation_svc
    PASSWORD = NULL                               -- Use key-pair authentication
    DEFAULT_ROLE = smdh_tenant_operator
    DEFAULT_WAREHOUSE = smdh_etl_wh
    MUST_CHANGE_PASSWORD = FALSE
    RSA_PUBLIC_KEY = NULL                         -- Set via ALTER USER after generating key pair
    COMMENT = 'Service account for automated tenant onboarding and maintenance. Uses key-pair authentication.';

GRANT ROLE smdh_tenant_operator TO USER smdh_automation_svc;

-- Note: Generate RSA key pair and set public key with:
-- ALTER USER smdh_automation_svc SET RSA_PUBLIC_KEY = '<public_key>';

-- ============================================================================
-- 11. Grant Warehouse Monitoring to Monitoring Role
-- ============================================================================

SELECT '11. Configuring Warehouse Monitoring Access...' AS step;

GRANT USAGE ON WAREHOUSE smdh_monitoring_wh TO ROLE smdh_monitoring;
GRANT MONITOR ON WAREHOUSE smdh_streaming_wh TO ROLE smdh_monitoring;
GRANT MONITOR ON WAREHOUSE smdh_etl_wh TO ROLE smdh_monitoring;
GRANT MONITOR ON WAREHOUSE smdh_analytics_wh TO ROLE smdh_monitoring;

-- ============================================================================
-- 12. Create Warehouse Utilization Monitoring View
-- ============================================================================

SELECT '12. Creating Warehouse Utilization Views...' AS step;

USE DATABASE smdh_infrastructure;
USE SCHEMA monitoring;

CREATE OR REPLACE VIEW v_warehouse_utilization AS
SELECT
    warehouse_name,
    DATE_TRUNC('hour', start_time) AS hour,
    SUM(credits_used) AS credits_used,
    COUNT(*) AS query_count,
    AVG(execution_time) / 1000 AS avg_execution_seconds,
    SUM(bytes_scanned) / (1024*1024*1024) AS gb_scanned
FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
WHERE warehouse_name LIKE 'smdh_%'
    AND start_time >= DATEADD(day, -7, CURRENT_TIMESTAMP())
GROUP BY warehouse_name, hour
ORDER BY hour DESC, warehouse_name;

GRANT SELECT ON v_warehouse_utilization TO ROLE smdh_monitoring;

-- Create real-time warehouse state view
CREATE OR REPLACE VIEW v_warehouse_state AS
SELECT
    name AS warehouse_name,
    state,
    size,
    running,
    queued,
    is_suspended,
    auto_suspend,
    auto_resume,
    scaling_policy,
    min_cluster_count,
    max_cluster_count,
    started_clusters,
    comment
FROM SNOWFLAKE.INFORMATION_SCHEMA.WAREHOUSES
WHERE name LIKE 'smdh_%'
ORDER BY name;

GRANT SELECT ON v_warehouse_state TO ROLE smdh_monitoring;

-- ============================================================================
-- 13. Create Cost Tracking View
-- ============================================================================

SELECT '13. Creating Cost Tracking View...' AS step;

CREATE OR REPLACE VIEW v_daily_costs AS
SELECT
    DATE_TRUNC('day', start_time) AS usage_date,
    warehouse_name,
    SUM(credits_used) AS total_credits,
    COUNT(*) AS query_count,
    SUM(credits_used) * 3.00 AS estimated_cost_usd  -- Adjust rate as needed
FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
WHERE warehouse_name LIKE 'smdh_%'
    AND start_time >= DATEADD(day, -30, CURRENT_TIMESTAMP())
GROUP BY usage_date, warehouse_name
ORDER BY usage_date DESC, warehouse_name;

GRANT SELECT ON v_daily_costs TO ROLE smdh_monitoring;
GRANT SELECT ON v_daily_costs TO ROLE smdh_infrastructure_admin;

-- ============================================================================
-- 14. Create Resource Monitor Status View
-- ============================================================================

SELECT '14. Creating Resource Monitor Status View...' AS step;

CREATE OR REPLACE VIEW v_resource_monitor_status AS
SELECT
    name AS monitor_name,
    credit_quota,
    used_credits,
    remaining_credits,
    level,
    comment
FROM SNOWFLAKE.ACCOUNT_USAGE.RESOURCE_MONITORS
WHERE name = 'smdh_platform_monitor'
    AND (end_time IS NULL OR end_time > CURRENT_TIMESTAMP());

GRANT SELECT ON v_resource_monitor_status TO ROLE smdh_monitoring;
GRANT SELECT ON v_resource_monitor_status TO ROLE smdh_infrastructure_admin;

-- ============================================================================
-- 15. Verification
-- ============================================================================

SELECT '15. Verifying Shared Resources Setup...' AS step;

-- Show warehouses
SELECT 'Created Warehouses:' AS verification;
SHOW WAREHOUSES LIKE 'smdh_%';

-- Show resource monitors
SELECT 'Created Resource Monitors:' AS verification;
SHOW RESOURCE MONITORS LIKE 'smdh_%';

-- Show roles
SELECT 'Created Roles:' AS verification;
SHOW ROLES LIKE 'smdh_%';

-- Show users
SELECT 'Created Service Accounts:' AS verification;
SHOW USERS LIKE 'smdh_%';

-- Test warehouse functionality
SELECT 'Testing Warehouse Availability:' AS verification;
USE WAREHOUSE smdh_monitoring_wh;
SELECT CURRENT_WAREHOUSE() AS current_warehouse;

-- ============================================================================
-- 16. Summary
-- ============================================================================

SELECT '╔════════════════════════════════════════════════════════════════╗' AS summary
UNION ALL SELECT '║  SMDH Shared Resources Setup Complete                      ║'
UNION ALL SELECT '╚════════════════════════════════════════════════════════════╝'
UNION ALL SELECT ''
UNION ALL SELECT 'Created Resources:'
UNION ALL SELECT '  ✓ Resource Monitor: smdh_platform_monitor (1000 credits/month)'
UNION ALL SELECT '  ✓ Warehouses:'
UNION ALL SELECT '      - smdh_streaming_wh (SMALL, auto-scale 1-3)'
UNION ALL SELECT '      - smdh_etl_wh (SMALL, auto-scale 1-2)'
UNION ALL SELECT '      - smdh_analytics_wh (SMALL, auto-scale 1-4)'
UNION ALL SELECT '      - smdh_dev_wh (XSMALL, single cluster)'
UNION ALL SELECT '      - smdh_monitoring_wh (XSMALL, single cluster)'
UNION ALL SELECT '  ✓ Roles:'
UNION ALL SELECT '      - smdh_tenant_operator'
UNION ALL SELECT '      - smdh_data_engineer'
UNION ALL SELECT '      - smdh_analytics_user (template)'
UNION ALL SELECT '  ✓ Service Account: smdh_automation_svc'
UNION ALL SELECT '  ✓ Monitoring Views: v_warehouse_utilization, v_warehouse_state, v_daily_costs'
UNION ALL SELECT ''
UNION ALL SELECT 'Configuration Notes:'
UNION ALL SELECT '  • All warehouses have auto-suspend enabled (cost optimization)'
UNION ALL SELECT '  • Multi-cluster enabled for streaming and analytics workloads'
UNION ALL SELECT '  • Resource monitor will alert at 75% and 90%, suspend at 100%'
UNION ALL SELECT '  • Service account requires RSA public key for key-pair authentication'
UNION ALL SELECT ''
UNION ALL SELECT 'Next Steps:'
UNION ALL SELECT '  1. Set RSA public key for smdh_automation_svc service account'
UNION ALL SELECT '  2. Run 03_openflow_connector.sql to configure Kinesis integration'
UNION ALL SELECT '  3. Adjust warehouse sizes based on actual workload'
UNION ALL SELECT '  4. Configure notification email for resource monitor alerts'
UNION ALL SELECT ''
UNION ALL SELECT 'Cost Control:'
UNION ALL SELECT '  • Monitor credit usage: SELECT * FROM v_daily_costs;'
UNION ALL SELECT '  • Check resource monitor: SELECT * FROM v_resource_monitor_status;'
UNION ALL SELECT '  • View warehouse state: SELECT * FROM v_warehouse_state;'
UNION ALL SELECT '============================================================';
