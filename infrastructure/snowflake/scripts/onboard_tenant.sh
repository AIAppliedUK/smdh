#!/bin/bash
# ============================================================================
# SMDH Tenant Onboarding Automation Script
# ============================================================================
# Purpose: Automate complete tenant onboarding in Snowflake
# Usage: ./onboard_tenant.sh --tenant-id company_a --tenant-name "Company A Ltd" --num-sites 5
# Author: SMDH Platform Team
# Version: 1.0
# ============================================================================

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SNOWFLAKE_DIR="$(dirname "$SCRIPT_DIR")"
SQL_DIR="$SNOWFLAKE_DIR/sql"

# Default values
AWS_REGION="${AWS_REGION:-eu-west-2}"
SNOWFLAKE_ACCOUNT="${SNOWFLAKE_ACCOUNT:-}"
SNOWFLAKE_USER="${SNOWFLAKE_USER:-}"
SNOWFLAKE_ROLE="${SNOWFLAKE_ROLE:-ACCOUNTADMIN}"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "\n${BLUE}==>${NC} $1"
}

# Run SQL script with proper error detection
# snowsql returns 0 even on SQL errors, so we need to check output
# -o variable_substitution=true enables &variable syntax in SQL files
run_sql_with_check() {
    local script_path="$1"
    local script_name=$(basename "$script_path")
    local log_file="/tmp/smdh_onboard_${script_name}.log"
    shift  # Remove first argument, rest are snowsql args

    snowsql -o variable_substitution=true "$@" -f "$script_path" > "$log_file" 2>&1
    local exit_code=$?

    # Check for SQL errors in output (pattern: NNNNNN (NNNNN): error message)
    if grep -qE "^[0-9]{6} \([0-9]{5}\):" "$log_file"; then
        local error_count=$(grep -cE "^[0-9]{6} \([0-9]{5}\):" "$log_file" || echo 0)
        log_error "$script_name had $error_count SQL error(s)"
        echo ""
        echo "=== SQL Errors Found ==="
        grep -E "^[0-9]{6} \([0-9]{5}\):" "$log_file" | head -20
        echo "========================"
        echo "Full log: $log_file"
        return 1
    elif [ $exit_code -ne 0 ]; then
        log_error "$script_name failed with exit code $exit_code"
        cat "$log_file"
        return 1
    fi
    return 0
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --tenant-id)
            TENANT_ID="$2"
            shift 2
            ;;
        --tenant-name)
            TENANT_NAME="$2"
            shift 2
            ;;
        --num-sites)
            NUM_SITES="$2"
            shift 2
            ;;
        --contact-email)
            CONTACT_EMAIL="$2"
            shift 2
            ;;
        --snowflake-account)
            SNOWFLAKE_ACCOUNT="$2"
            shift 2
            ;;
        --snowflake-user)
            SNOWFLAKE_USER="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --tenant-id ID              Tenant identifier (lowercase, alphanumeric, underscores)"
            echo "  --tenant-name NAME          Tenant display name"
            echo "  --num-sites N               Number of manufacturing sites"
            echo "  --contact-email EMAIL       Tenant contact email"
            echo "  --snowflake-account ACC     Snowflake account identifier"
            echo "  --snowflake-user USER       Snowflake user for authentication"
            echo "  --help                      Show this help message"
            echo ""
            echo "Environment Variables:"
            echo "  SNOWFLAKE_ACCOUNT          Snowflake account (alternative to --snowflake-account)"
            echo "  SNOWFLAKE_USER             Snowflake user (alternative to --snowflake-user)"
            echo "  AWS_REGION                 AWS region (default: eu-west-2)"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Run with --help for usage information"
            exit 1
            ;;
    esac
done

# Validate required parameters
if [[ -z "${TENANT_ID:-}" ]]; then
    log_error "Missing required parameter: --tenant-id"
    exit 1
fi

if [[ -z "${TENANT_NAME:-}" ]]; then
    log_error "Missing required parameter: --tenant-name"
    exit 1
fi

if [[ -z "${NUM_SITES:-}" ]]; then
    log_error "Missing required parameter: --num-sites"
    exit 1
fi

if [[ -z "${SNOWFLAKE_ACCOUNT}" ]]; then
    log_error "Snowflake account not specified. Use --snowflake-account or set SNOWFLAKE_ACCOUNT environment variable"
    exit 1
fi

if [[ -z "${SNOWFLAKE_USER}" ]]; then
    log_error "Snowflake user not specified. Use --snowflake-user or set SNOWFLAKE_USER environment variable"
    exit 1
fi

# Validate tenant ID format
if ! [[ $TENANT_ID =~ ^[a-z0-9_]+$ ]]; then
    log_error "Tenant ID must be lowercase alphanumeric with underscores only"
    exit 1
fi

# Banner
echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  SMDH Tenant Onboarding Automation                            ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
log_info "Tenant ID: $TENANT_ID"
log_info "Tenant Name: $TENANT_NAME"
log_info "Number of Sites: $NUM_SITES"
log_info "AWS Region: $AWS_REGION"
log_info "Snowflake Account: $SNOWFLAKE_ACCOUNT"
echo ""

# Check snowsql is installed
if ! command -v snowsql &> /dev/null; then
    log_error "snowsql command not found. Please install SnowSQL CLI."
    log_info "Installation: https://docs.snowflake.com/en/user-guide/snowsql-install-config.html"
    exit 1
fi

# Test Snowflake connection
log_step "Testing Snowflake connection..."
if snowsql -a "$SNOWFLAKE_ACCOUNT" -u "$SNOWFLAKE_USER" -q "SELECT CURRENT_VERSION();" > /dev/null 2>&1; then
    log_info "[OK] Snowflake connection successful"
else
    log_error "Failed to connect to Snowflake. Check your credentials."
    exit 1
fi

# Step 1: Create tenant database
log_step "Step 1/8: Creating tenant database..."
if run_sql_with_check "$SQL_DIR/tenant/10_create_tenant_database.sql" \
    -a "$SNOWFLAKE_ACCOUNT" -u "$SNOWFLAKE_USER" \
    --variable tenant_id="$TENANT_ID" \
    --variable tenant_name="$TENANT_NAME" \
    --variable aws_region="$AWS_REGION" \
    --variable num_sites="$NUM_SITES" \
    -o output_format=plain \
    -o quiet=true \
    -o friendly=false; then
    log_info "[OK] Tenant database created"
else
    log_error "Failed to create tenant database"
    exit 1
fi

# Step 2: Configure schemas
log_step "Step 2/8: Configuring schemas..."
if run_sql_with_check "$SQL_DIR/tenant/11_create_schemas.sql" \
    -a "$SNOWFLAKE_ACCOUNT" -u "$SNOWFLAKE_USER" \
    --variable tenant_id="$TENANT_ID" \
    -o output_format=plain \
    -o quiet=true \
    -o friendly=false; then
    log_info "[OK] Schemas configured"
else
    log_error "Failed to configure schemas"
    exit 1
fi

# Step 3: Create tables
log_step "Step 3/8: Creating tables..."
if run_sql_with_check "$SQL_DIR/tenant/12_create_tables.sql" \
    -a "$SNOWFLAKE_ACCOUNT" -u "$SNOWFLAKE_USER" \
    --variable tenant_id="$TENANT_ID" \
    -o output_format=plain \
    -o quiet=true \
    -o friendly=false; then
    log_info "[OK] Tables created"
else
    log_error "Failed to create tables"
    exit 1
fi

# Step 4: Create streams
log_step "Step 4/8: Creating streams for CDC..."
if run_sql_with_check "$SQL_DIR/tenant/13_create_streams.sql" \
    -a "$SNOWFLAKE_ACCOUNT" -u "$SNOWFLAKE_USER" \
    --variable tenant_id="$TENANT_ID" \
    -o output_format=plain \
    -o quiet=true \
    -o friendly=false; then
    log_info "[OK] Streams created"
else
    log_error "Failed to create streams"
    exit 1
fi

# Step 5: Create tasks
log_step "Step 5/8: Creating ETL tasks..."
if run_sql_with_check "$SQL_DIR/tenant/14_create_tasks.sql" \
    -a "$SNOWFLAKE_ACCOUNT" -u "$SNOWFLAKE_USER" \
    --variable tenant_id="$TENANT_ID" \
    -o output_format=plain \
    -o quiet=true \
    -o friendly=false; then
    log_info "[OK] Tasks created and started"
else
    log_error "Failed to create tasks"
    exit 1
fi

# Step 6: Create dynamic tables
log_step "Step 6/8: Creating dynamic tables..."
if run_sql_with_check "$SQL_DIR/tenant/15_create_dynamic_tables.sql" \
    -a "$SNOWFLAKE_ACCOUNT" -u "$SNOWFLAKE_USER" \
    --variable tenant_id="$TENANT_ID" \
    -o output_format=plain \
    -o quiet=true \
    -o friendly=false; then
    log_info "[OK] Dynamic tables created"
else
    log_error "Failed to create dynamic tables"
    exit 1
fi

# Step 7: Configure RBAC
log_step "Step 7/8: Configuring roles and permissions..."
if run_sql_with_check "$SQL_DIR/tenant/16_create_roles.sql" \
    -a "$SNOWFLAKE_ACCOUNT" -u "$SNOWFLAKE_USER" \
    --variable tenant_id="$TENANT_ID" \
    -o output_format=plain \
    -o quiet=true \
    -o friendly=false; then
    log_info "[OK] Roles configured"
else
    log_error "Failed to configure roles"
    exit 1
fi

# Step 8: Setup monitoring
log_step "Step 8/8: Setting up monitoring..."
if run_sql_with_check "$SQL_DIR/tenant/17_create_monitoring.sql" \
    -a "$SNOWFLAKE_ACCOUNT" -u "$SNOWFLAKE_USER" \
    --variable tenant_id="$TENANT_ID" \
    -o output_format=plain \
    -o quiet=true \
    -o friendly=false; then
    log_info "[OK] Monitoring configured"
else
    log_error "Failed to setup monitoring"
    exit 1
fi

# Validation
log_step "Running validation checks..."
snowsql -a "$SNOWFLAKE_ACCOUNT" -u "$SNOWFLAKE_USER" \
    -f "$SQL_DIR/utility/validate_tenant.sql" \
    --variable tenant_id="$TENANT_ID" \
    -o output_format=psql \
    -o header=true

# Summary
echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  Tenant Onboarding Complete!                                   ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
log_info "Deliverables:"
echo "   [OK] Database: smdh_tenant_${TENANT_ID}"
echo "   [OK] Schemas: raw, normalized, aggregated, analytics"
echo "   [OK] Tables: sensor_readings, sensor_metrics, aggregations, etc."
echo "   [OK] Streams: 6 CDC streams for real-time processing"
echo "   [OK] Tasks: 5 automated ETL tasks (running)"
echo "   [OK] Dynamic Tables: 6 real-time aggregation tables"
echo "   [OK] Roles: 7 tenant-specific roles"
echo "   [OK] Monitoring: Views and health checks"
echo ""
log_info "Next Steps:"
echo "   1. Configure Snowflake Openflow connector for Kinesis"
echo "   2. Update tenant entry with Kinesis stream details"
echo "   3. Deploy IoT device certificates from AWS"
echo "   4. Start MQTT message ingestion"
echo "   5. Monitor data flow:"
echo "      snowsql -a $SNOWFLAKE_ACCOUNT -u $SNOWFLAKE_USER \\"
echo "        -q \"USE DATABASE smdh_tenant_${TENANT_ID}; CALL analytics.sp_health_check();\""
echo ""
log_info "Validation:"
echo "   Run validation script:"
echo "   ./scripts/validate_tenant.sh --tenant-id $TENANT_ID"
echo ""
log_info "Access tenant data:"
echo "   Database: smdh_tenant_${TENANT_ID}"
echo "   Dashboard: SELECT * FROM analytics.v_system_summary;"
echo "   Health Check: CALL analytics.sp_health_check();"
echo ""
