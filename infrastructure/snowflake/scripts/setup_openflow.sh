#!/bin/bash

################################################################################
# SMDH Snowflake Openflow Setup Script
################################################################################
#
# Purpose: Configure Snowflake Openflow infrastructure for Kinesis ingestion
#
# Usage:
#   ./setup_openflow.sh
#   ./setup_openflow.sh --skip-mfa-check    # Skip MFA enrollment check
#
# Prerequisites:
#   - SnowSQL installed and configured
#   - SNOWSQL_PWD environment variable set (or use browser auth)
#   - ACCOUNTADMIN role access
#
# What this script does:
#   1. Creates OPENFLOW_ADMIN and OPENFLOW_RUNTIME_ROLE_KINESIS roles
#   2. Creates OPENFLOW database with image repository
#   3. Creates network rules for AWS access (eu-west-2)
#   4. Creates External Access Integration
#   5. Creates tracking table and monitoring views
#   6. Grants permissions to existing tenant databases
#
# After running this script, complete these MANUAL steps in Snowsight:
#   1. Navigate to Data > Openflow
#   2. Create Deployment: smdh-openflow-deployment
#   3. Create Runtime: smdh-kinesis-runtime
#   4. Add Kinesis Connector with stream configuration
#
# See: docs/deployment/Tenant_Onboarding_Guide.md
#
################################################################################

set -euo pipefail

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration - adjust these as needed
SNOWFLAKE_ACCOUNT="${SNOWFLAKE_ACCOUNT:-qqoylnv-zy42691}"
SNOWFLAKE_USER="${SNOWFLAKE_USER:-AIAPPLIED}"
SNOWFLAKE_ROLE="ACCOUNTADMIN"
SNOWFLAKE_WAREHOUSE="SMDH_WH"
AWS_REGION="eu-west-2"

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQL_DIR="${SCRIPT_DIR}/../sql"

# Parse arguments
SKIP_MFA_CHECK=false
for arg in "$@"; do
    case $arg in
        --skip-mfa-check)
            SKIP_MFA_CHECK=true
            shift
            ;;
    esac
done

# Print banner
print_banner() {
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║   SMDH Snowflake Openflow Setup                                ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# Check prerequisites
check_prerequisites() {
    echo -e "${BLUE}Checking prerequisites...${NC}"

    # Check snowsql
    if ! command -v snowsql &> /dev/null; then
        echo -e "${RED}✗ SnowSQL not found. Please install it first.${NC}"
        echo "  See: https://docs.snowflake.com/en/user-guide/snowsql-install-config"
        exit 1
    fi
    echo -e "${GREEN}✓${NC} SnowSQL installed"

    # Check password
    if [ -z "${SNOWSQL_PWD:-}" ]; then
        echo -e "${RED}✗ SNOWSQL_PWD not set${NC}"
        echo ""
        echo "Please set your Snowflake password:"
        echo "  export SNOWSQL_PWD='your_password'"
        echo ""
        echo "Then re-run this script."
        exit 1
    else
        echo -e "${GREEN}✓${NC} SNOWSQL_PWD set"
    fi
    USE_BROWSER_AUTH=false

    echo -e "${GREEN}[OK] Prerequisites check passed${NC}"
    echo ""
}

# Test Snowflake connection
test_connection() {
    echo -e "${BLUE}Testing Snowflake connection...${NC}"

    local result
    if ! result=$(snowsql -a "${SNOWFLAKE_ACCOUNT}" -u "${SNOWFLAKE_USER}" \
        -o output_format=plain -o header=false -o timing=false \
        -q "SELECT 'connected'" 2>&1); then
        echo -e "${RED}✗ Failed to connect to Snowflake${NC}"
        echo ""
        echo "Error: ${result}"
        echo ""
        echo "Possible issues:"
        echo "  1. Incorrect password - Check SNOWSQL_PWD value"
        echo "  2. MFA required - If prompted, enter your MFA code"
        echo "  3. Network issues - Check connectivity"
        echo ""
        echo "Test manually with:"
        echo "  snowsql -a ${SNOWFLAKE_ACCOUNT} -u ${SNOWFLAKE_USER}"
        exit 1
    fi

    echo -e "${GREEN}[OK] Connected to Snowflake${NC}"
    echo ""
}

# Run SQL file or inline SQL
run_sql() {
    local sql="$1"
    local description="$2"

    echo -e "${BLUE}${description}...${NC}"

    local result
    if ! result=$(snowsql -a "${SNOWFLAKE_ACCOUNT}" -u "${SNOWFLAKE_USER}" \
        -r "${SNOWFLAKE_ROLE}" -w "${SNOWFLAKE_WAREHOUSE}" \
        -o output_format=plain -o header=false -o timing=false \
        -q "${sql}" 2>&1); then
        echo -e "${RED}✗ Failed: ${description}${NC}"
        echo "${result}"
        return 1
    fi

    echo -e "${GREEN}✓${NC} ${description}"
    return 0
}

# Create Openflow Admin Role
setup_admin_role() {
    echo -e "\n${CYAN}Step 1: Creating Openflow Admin Role${NC}"

    run_sql "
        CREATE ROLE IF NOT EXISTS OPENFLOW_ADMIN
            COMMENT = 'Administrator role for Snowflake Openflow deployments and runtimes';
        GRANT CREATE ROLE ON ACCOUNT TO ROLE OPENFLOW_ADMIN;
        GRANT CREATE OPENFLOW DATA PLANE INTEGRATION ON ACCOUNT TO ROLE OPENFLOW_ADMIN;
        GRANT CREATE OPENFLOW RUNTIME INTEGRATION ON ACCOUNT TO ROLE OPENFLOW_ADMIN;
        GRANT USAGE ON WAREHOUSE ${SNOWFLAKE_WAREHOUSE} TO ROLE OPENFLOW_ADMIN;
        GRANT ROLE OPENFLOW_ADMIN TO ROLE ACCOUNTADMIN;
    " "Creating OPENFLOW_ADMIN role"
}

# Create Openflow Database and Image Repository
setup_database() {
    echo -e "\n${CYAN}Step 2: Creating Openflow Database${NC}"

    run_sql "
        CREATE DATABASE IF NOT EXISTS OPENFLOW
            DATA_RETENTION_TIME_IN_DAYS = 7
            COMMENT = 'Snowflake Openflow configuration and image repository';
        USE DATABASE OPENFLOW;
        CREATE SCHEMA IF NOT EXISTS OPENFLOW
            COMMENT = 'Openflow image repository and configuration';
        USE SCHEMA OPENFLOW;
        CREATE IMAGE REPOSITORY IF NOT EXISTS OPENFLOW
            COMMENT = 'Container image repository for Openflow connectors';
        GRANT USAGE ON DATABASE OPENFLOW TO ROLE PUBLIC;
        GRANT USAGE ON SCHEMA OPENFLOW.OPENFLOW TO ROLE PUBLIC;
        GRANT READ ON IMAGE REPOSITORY OPENFLOW.OPENFLOW.OPENFLOW TO ROLE PUBLIC;
    " "Creating OPENFLOW database and image repository"
}

# Create Network Rules
setup_network_rules() {
    echo -e "\n${CYAN}Step 3: Creating Network Rules for AWS Access${NC}"

    run_sql "
        USE DATABASE OPENFLOW;
        USE SCHEMA OPENFLOW;
        CREATE OR REPLACE NETWORK RULE OPENFLOW_AWS_EU_WEST_2_RULE
            MODE = EGRESS
            TYPE = HOST_PORT
            VALUE_LIST = (
                'kinesis.${AWS_REGION}.amazonaws.com:443',
                'dynamodb.${AWS_REGION}.amazonaws.com:443',
                'sts.${AWS_REGION}.amazonaws.com:443',
                'sts.amazonaws.com:443'
            )
            COMMENT = 'Network rule for Openflow to access AWS Kinesis and DynamoDB in ${AWS_REGION}';
    " "Creating network rule for AWS ${AWS_REGION}"
}

# Create External Access Integration
setup_external_access() {
    echo -e "\n${CYAN}Step 4: Creating External Access Integration${NC}"

    if ! run_sql "
        CREATE OR REPLACE EXTERNAL ACCESS INTEGRATION OPENFLOW_AWS_EAI
            ALLOWED_NETWORK_RULES = (OPENFLOW.OPENFLOW.OPENFLOW_AWS_EU_WEST_2_RULE)
            ENABLED = TRUE
            COMMENT = 'External access integration for Openflow AWS connectivity';
    " "Creating External Access Integration"; then
        echo -e "${YELLOW}⚠ External Access Integration failed - may require paid account${NC}"
        return 1
    fi
}

# Create Runtime Role
setup_runtime_role() {
    echo -e "\n${CYAN}Step 5: Creating Runtime Role${NC}"

    run_sql "
        USE ROLE ACCOUNTADMIN;
        CREATE ROLE IF NOT EXISTS OPENFLOW_RUNTIME_ROLE_KINESIS
            COMMENT = 'Runtime role for Openflow Kinesis connector - ingests sensor data';
        GRANT ROLE OPENFLOW_RUNTIME_ROLE_KINESIS TO ROLE OPENFLOW_ADMIN;
        GRANT USAGE, OPERATE ON WAREHOUSE ${SNOWFLAKE_WAREHOUSE} TO ROLE OPENFLOW_RUNTIME_ROLE_KINESIS;
        GRANT USAGE ON DATABASE OPENFLOW TO ROLE OPENFLOW_RUNTIME_ROLE_KINESIS;
        GRANT USAGE ON SCHEMA OPENFLOW.OPENFLOW TO ROLE OPENFLOW_RUNTIME_ROLE_KINESIS;
    " "Creating OPENFLOW_RUNTIME_ROLE_KINESIS"

    # Grant external access if it exists
    run_sql "
        GRANT USAGE ON INTEGRATION OPENFLOW_AWS_EAI TO ROLE OPENFLOW_RUNTIME_ROLE_KINESIS;
    " "Granting external access to runtime role" || true
}

# Create tracking infrastructure
setup_tracking() {
    echo -e "\n${CYAN}Step 6: Creating Tracking Infrastructure${NC}"

    run_sql "
        USE DATABASE SMDH_INFRASTRUCTURE;
        USE SCHEMA TENANT_CONFIGS;

        -- Create or replace the stored procedure
        CREATE OR REPLACE PROCEDURE sp_grant_openflow_tenant_access(tenant_id_param VARCHAR)
        RETURNS STRING
        LANGUAGE SQL
        EXECUTE AS CALLER
        AS
        \$\$
        DECLARE
            db_name VARCHAR;
            grant_sql VARCHAR;
        BEGIN
            db_name := 'SMDH_TENANT_' || UPPER(:tenant_id_param);
            grant_sql := 'GRANT USAGE ON DATABASE ' || db_name || ' TO ROLE OPENFLOW_RUNTIME_ROLE_KINESIS';
            EXECUTE IMMEDIATE grant_sql;
            grant_sql := 'GRANT USAGE ON SCHEMA ' || db_name || '.RAW TO ROLE OPENFLOW_RUNTIME_ROLE_KINESIS';
            EXECUTE IMMEDIATE grant_sql;
            grant_sql := 'GRANT INSERT, SELECT ON ALL TABLES IN SCHEMA ' || db_name || '.RAW TO ROLE OPENFLOW_RUNTIME_ROLE_KINESIS';
            EXECUTE IMMEDIATE grant_sql;
            grant_sql := 'GRANT INSERT, SELECT ON FUTURE TABLES IN SCHEMA ' || db_name || '.RAW TO ROLE OPENFLOW_RUNTIME_ROLE_KINESIS';
            EXECUTE IMMEDIATE grant_sql;
            RETURN 'Granted Openflow access to database: ' || db_name;
        END;
        \$\$;

        GRANT USAGE ON PROCEDURE sp_grant_openflow_tenant_access(VARCHAR) TO ROLE OPENFLOW_ADMIN;
    " "Creating sp_grant_openflow_tenant_access procedure"

    run_sql "
        USE DATABASE SMDH_INFRASTRUCTURE;
        USE SCHEMA TENANT_CONFIGS;

        CREATE TABLE IF NOT EXISTS openflow_connectors (
            connector_id VARCHAR(255) DEFAULT UUID_STRING() PRIMARY KEY,
            tenant_id VARCHAR(100) NOT NULL,
            connector_name VARCHAR(255) NOT NULL,
            connector_type VARCHAR(50) DEFAULT 'KINESIS',
            target_database VARCHAR(255) NOT NULL,
            target_schema VARCHAR(255) NOT NULL,
            target_table VARCHAR(255) NOT NULL,
            kinesis_stream_name VARCHAR(255) NOT NULL,
            kinesis_stream_arn VARCHAR(500),
            aws_region VARCHAR(50) DEFAULT '${AWS_REGION}',
            runtime_name VARCHAR(255),
            deployment_name VARCHAR(255),
            status VARCHAR(50) DEFAULT 'pending',
            created_date TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
            activated_date TIMESTAMP_NTZ,
            last_health_check TIMESTAMP_NTZ,
            total_records_ingested NUMBER(20) DEFAULT 0,
            last_ingestion_timestamp TIMESTAMP_NTZ,
            error_count NUMBER(10) DEFAULT 0,
            last_error_message VARCHAR(2000),
            configuration VARIANT
        )
        COMMENT = 'Registry of Snowflake Openflow connectors for Kinesis ingestion';
    " "Creating openflow_connectors tracking table"
}

# Create monitoring views
setup_monitoring() {
    echo -e "\n${CYAN}Step 7: Creating Monitoring Views${NC}"

    run_sql "
        USE DATABASE SMDH_INFRASTRUCTURE;
        USE SCHEMA MONITORING;

        CREATE OR REPLACE VIEW v_openflow_connector_status AS
        SELECT
            oc.connector_id,
            oc.tenant_id,
            t.tenant_name,
            oc.connector_name,
            oc.kinesis_stream_name,
            oc.target_database || '.' || oc.target_schema || '.' || oc.target_table AS target_table,
            oc.status,
            oc.total_records_ingested,
            oc.last_ingestion_timestamp,
            DATEDIFF(MINUTE, oc.last_ingestion_timestamp, CURRENT_TIMESTAMP()) AS minutes_since_last_ingestion,
            oc.error_count,
            oc.last_error_message,
            oc.created_date,
            oc.activated_date
        FROM tenant_configs.openflow_connectors oc
        LEFT JOIN tenant_configs.tenants t ON oc.tenant_id = t.tenant_id
        ORDER BY oc.tenant_id, oc.connector_name;

        GRANT SELECT ON VIEW v_openflow_connector_status TO ROLE OPENFLOW_ADMIN;

        CREATE OR REPLACE VIEW v_openflow_health_summary AS
        SELECT
            status,
            COUNT(*) AS connector_count,
            SUM(total_records_ingested) AS total_records,
            SUM(error_count) AS total_errors,
            MAX(last_ingestion_timestamp) AS most_recent_ingestion
        FROM tenant_configs.openflow_connectors
        GROUP BY status;

        GRANT SELECT ON VIEW v_openflow_health_summary TO ROLE OPENFLOW_ADMIN;
    " "Creating monitoring views"
}

# Grant access to existing tenant databases
grant_existing_tenants() {
    echo -e "\n${CYAN}Step 8: Granting Access to Existing Tenants${NC}"

    local tenants
    # Use ACCOUNT_USAGE.DATABASES (INFORMATION_SCHEMA.DATABASES doesn't exist at account level)
    tenants=$(snowsql -a "${SNOWFLAKE_ACCOUNT}" -u "${SNOWFLAKE_USER}" \
        -r "${SNOWFLAKE_ROLE}" \
        -o output_format=plain -o header=false -o timing=false \
        -q "SELECT REPLACE(database_name, 'SMDH_TENANT_', '') FROM SNOWFLAKE.ACCOUNT_USAGE.DATABASES WHERE database_name LIKE 'SMDH_TENANT_%' AND deleted IS NULL" 2>/dev/null || echo "")

    if [ -n "${tenants}" ]; then
        for tenant in ${tenants}; do
            tenant=$(echo "${tenant}" | tr '[:upper:]' '[:lower:]' | xargs)
            if [ -n "${tenant}" ]; then
                run_sql "CALL smdh_infrastructure.tenant_configs.sp_grant_openflow_tenant_access('${tenant}');" \
                    "Granting access to tenant: ${tenant}" || true
            fi
        done
    else
        echo -e "${YELLOW}No existing tenant databases found${NC}"
    fi
}

# Verify setup
verify_setup() {
    echo -e "\n${CYAN}Step 9: Verifying Setup${NC}"

    echo -e "${BLUE}Checking roles...${NC}"
    run_sql "SHOW ROLES LIKE '%OPENFLOW%';" "Listing Openflow roles" || true

    echo -e "${BLUE}Checking integrations...${NC}"
    run_sql "SHOW EXTERNAL ACCESS INTEGRATIONS LIKE 'OPENFLOW%';" "Listing External Access Integrations" || true
}

# Print summary
print_summary() {
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║   Openflow SQL Setup Complete                                  ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "Created Resources:"
    echo "  ✓ Role: OPENFLOW_ADMIN"
    echo "  ✓ Role: OPENFLOW_RUNTIME_ROLE_KINESIS"
    echo "  ✓ Database: OPENFLOW (with image repository)"
    echo "  ✓ Network Rule: OPENFLOW_AWS_EU_WEST_2_RULE"
    echo "  ✓ External Access Integration: OPENFLOW_AWS_EAI"
    echo "  ✓ Table: openflow_connectors"
    echo "  ✓ Procedure: sp_grant_openflow_tenant_access"
    echo "  ✓ Views: v_openflow_connector_status, v_openflow_health_summary"
    echo ""
    echo -e "${YELLOW}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}  MANUAL STEPS REQUIRED - Complete in Snowsight UI${NC}"
    echo -e "${YELLOW}════════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "1. Open Snowsight: https://app.snowflake.com"
    echo ""
    echo "2. Navigate to: Data > Openflow"
    echo ""
    echo "3. CREATE DEPLOYMENT:"
    echo "   - Click 'Create Deployment'"
    echo "   - Name: smdh-openflow-deployment"
    echo "   - Type: Snowflake Deployment (managed)"
    echo ""
    echo "4. CREATE RUNTIME:"
    echo "   - Click 'Create Runtime'"
    echo "   - Name: smdh-kinesis-runtime"
    echo "   - Role: OPENFLOW_RUNTIME_ROLE_KINESIS"
    echo "   - Warehouse: ${SNOWFLAKE_WAREHOUSE}"
    echo "   - External Access: OPENFLOW_AWS_EAI"
    echo ""
    echo "5. ADD KINESIS CONNECTOR:"
    echo "   - Click 'Add Connector' > Amazon Kinesis"
    echo "   - Configure AWS credentials and stream mapping"
    echo ""
    echo "See: docs/deployment/Tenant_Onboarding_Guide.md"
    echo ""
}

# Main execution
main() {
    print_banner
    check_prerequisites
    test_connection

    setup_admin_role
    setup_database
    setup_network_rules
    setup_external_access || echo -e "${YELLOW}⚠ Continuing without External Access Integration${NC}"
    setup_runtime_role
    setup_tracking
    setup_monitoring
    grant_existing_tenants
    verify_setup

    print_summary
}

# Run main function
main "$@"
