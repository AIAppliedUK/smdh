#!/bin/bash
# ============================================================================
# SMDH Snowflake Setup Validation Script
# ============================================================================
# Purpose: Validate that all Snowflake scripts execute successfully
# Usage: ./validate_setup.sh [tenant_id] [tenant_name] [aws_region] [num_sites]
# Example: ./validate_setup.sh test_tenant "Test Tenant" eu-west-2 5
# Author: SMDH Platform Team
# Version: 1.1
# ============================================================================

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
TENANT_ID="${1:-test_tenant}"
TENANT_NAME="${2:-TestTenant}"
AWS_REGION="${3:-eu-west-2}"
NUM_SITES="${4:-5}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default SnowSQL parameters
# Variables are passed with -D flag for $ substitution in SQL
SNOWSQL_OPTS="-r ACCOUNTADMIN"

# SnowSQL command (use full path if not in PATH)
if ! command -v snowsql &> /dev/null; then
    SNOWSQL_CMD="$HOME/.snowsql/1.4.5/snowsql"
    if [ ! -f "$SNOWSQL_CMD" ]; then
        echo "ERROR: snowsql not found in PATH or at $SNOWSQL_CMD"
        exit 1
    fi
else
    SNOWSQL_CMD="snowsql"
fi

# ============================================================================
# Helper Functions
# ============================================================================

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

run_sql_script() {
    local script_path="$1"
    local script_name=$(basename "$script_path")
    shift # Remove first argument
    # All remaining arguments are extra options

    log_step "Running $script_name..."

    # Debug: Show the actual command being run
    echo "DEBUG: $SNOWSQL_CMD $SNOWSQL_OPTS" "$@" "-f $script_path" >&2

    if $SNOWSQL_CMD $SNOWSQL_OPTS "$@" -f "$script_path" > /tmp/smdh_${script_name}.log 2>&1; then
        log_success "$script_name completed successfully"
        return 0
    else
        log_error "$script_name failed. Check /tmp/smdh_${script_name}.log for details"
        cat /tmp/smdh_${script_name}.log
        return 1
    fi
}

# ============================================================================
# Main Validation Flow
# ============================================================================

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║       SMDH Snowflake Infrastructure Validation                 ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "Tenant Configuration:"
echo "  • Tenant ID: $TENANT_ID"
echo "  • Tenant Name: $TENANT_NAME"
echo "  • AWS Region: $AWS_REGION"
echo "  • Number of Sites: $NUM_SITES"
echo "  • Script Directory: $SCRIPT_DIR"
echo ""

# ============================================================================
# Phase 1: Clean Slate
# ============================================================================

log_step "Phase 1: Cleaning existing infrastructure..."
echo ""

if [ -f "$SCRIPT_DIR/00_drop_all.sql" ]; then
    run_sql_script "$SCRIPT_DIR/00_drop_all.sql" || {
        log_warning "Drop script failed (may be expected if nothing exists yet)"
    }
else
    log_warning "00_drop_all.sql not found, skipping cleanup"
fi

echo ""

# ============================================================================
# Phase 2: Core Infrastructure Setup
# ============================================================================

log_step "Phase 2: Setting up core infrastructure..."
echo ""

# Infrastructure database and schemas
run_sql_script "$SCRIPT_DIR/01_infrastructure_setup.sql" || exit 1

# Shared resources (warehouses, roles)
run_sql_script "$SCRIPT_DIR/02_shared_resources.sql" || exit 1

# Openflow connector configuration
run_sql_script "$SCRIPT_DIR/03_openflow_connector.sql" \
    -D aws_iam_role_arn='arn:aws:iam::123456789012:role/placeholder' \
    -D aws_external_id='placeholder' \
    -D kinesis_stream_arn='arn:aws:kinesis:eu-west-2:123456789012:stream/placeholder' || {
    log_error "Openflow connector setup failed"
    exit 1
}

echo ""

# ============================================================================
# Phase 3: Tenant Setup
# ============================================================================

log_step "Phase 3: Setting up tenant: $TENANT_ID..."
echo ""

# Create tenant database
run_sql_script "$SCRIPT_DIR/tenant/10_create_tenant_database.sql" \
    --variable tenant_id="$TENANT_ID" \
    --variable tenant_name="$TENANT_NAME" \
    --variable aws_region="$AWS_REGION" \
    --variable num_sites="$NUM_SITES" || exit 1

# Configure schemas
run_sql_script "$SCRIPT_DIR/tenant/11_create_schemas.sql" \
    --variable tenant_id="$TENANT_ID" || exit 1

# Create tables
run_sql_script "$SCRIPT_DIR/tenant/12_create_tables.sql" \
    --variable tenant_id="$TENANT_ID" || exit 1

# Create streams
run_sql_script "$SCRIPT_DIR/tenant/13_create_streams.sql" \
    --variable tenant_id="$TENANT_ID" || exit 1

# Create tasks
run_sql_script "$SCRIPT_DIR/tenant/14_create_tasks.sql" \
    --variable tenant_id="$TENANT_ID" || exit 1

# Create dynamic tables
run_sql_script "$SCRIPT_DIR/tenant/15_create_dynamic_tables.sql" \
    --variable tenant_id="$TENANT_ID" || exit 1

# Create roles
run_sql_script "$SCRIPT_DIR/tenant/16_create_roles.sql" \
    --variable tenant_id="$TENANT_ID" || exit 1

# Create monitoring
run_sql_script "$SCRIPT_DIR/tenant/17_create_monitoring.sql" \
    --variable tenant_id="$TENANT_ID" || exit 1

echo ""

# ============================================================================
# Phase 4: Verification
# ============================================================================

log_step "Phase 4: Verifying setup..."
echo ""

# Create verification SQL
cat > /tmp/smdh_verification.sql << 'EOF'
USE ROLE ACCOUNTADMIN;

SELECT '╔════════════════════════════════════════════════════════════════╗' AS verification
UNION ALL SELECT '║  Verification Report                                       ║'
UNION ALL SELECT '╚════════════════════════════════════════════════════════════╝';

-- Check databases
SELECT 'Databases:' AS check_type;
SHOW DATABASES LIKE 'smdh%';

-- Check warehouses
SELECT 'Warehouses:' AS check_type;
SHOW WAREHOUSES LIKE 'smdh%';

-- Check roles
SELECT 'Roles:' AS check_type;
SHOW ROLES LIKE 'smdh%';

-- Check infrastructure tables
SELECT 'Infrastructure Tables:' AS check_type;
USE DATABASE smdh_infrastructure;
SELECT
    table_schema,
    COUNT(*) as table_count
FROM smdh_infrastructure.INFORMATION_SCHEMA.TABLES
GROUP BY table_schema
ORDER BY table_schema;

-- Check tenant tables
SELECT 'Tenant Tables:' AS check_type;
SET tenant_db = 'smdh_tenant_' || '&tenant_id';
USE DATABASE IDENTIFIER($tenant_db);
SELECT
    table_schema,
    COUNT(*) as table_count
FROM INFORMATION_SCHEMA.TABLES
GROUP BY table_schema
ORDER BY table_schema;

SELECT '╔════════════════════════════════════════════════════════════════╗' AS summary
UNION ALL SELECT '║  Validation Complete                                       ║'
UNION ALL SELECT '╚════════════════════════════════════════════════════════════╝';
EOF

$SNOWSQL_CMD $SNOWSQL_OPTS --variable "tenant_id=$TENANT_ID" -f /tmp/smdh_verification.sql

log_success "Verification completed"
echo ""

# ============================================================================
# Summary
# ============================================================================

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  VALIDATION SUMMARY                                            ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
log_success "All scripts executed successfully!"
echo ""
echo "Created Resources:"
echo "  ✓ Infrastructure database: smdh_infrastructure"
echo "  ✓ Tenant database: smdh_tenant_${TENANT_ID}"
echo "  ✓ Warehouses: streaming, etl, analytics, dev, monitoring"
echo "  ✓ Roles: infrastructure_admin, monitoring, tenant_operator, data_engineer"
echo "  ✓ Openflow connector: configured (requires AWS IAM setup)"
echo ""
echo "Next Steps:"
echo "  1. Configure AWS IAM role trust policy with Snowflake credentials"
echo "  2. Update terraform output values for Kinesis integration"
echo "  3. Test data ingestion from IoT Core → Kinesis → Snowflake"
echo "  4. Set up Streamlit portal for tenant analytics"
echo ""
echo "Log files saved to /tmp/smdh_*.log"
echo ""
