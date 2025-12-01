#!/bin/bash
# ============================================================================
# SMDH Snowflake Management Script
# ============================================================================
# Purpose: Deploy, drop, or check Snowflake infrastructure
# Usage:
#   ./snowflake.sh deploy    # Deploy core infrastructure
#   ./snowflake.sh drop      # Drop all infrastructure
#   ./snowflake.sh status    # Check current state
# Author: SMDH Platform Team
# Version: 1.0
# ============================================================================

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SNOWFLAKE_DIR="$(dirname "$SCRIPT_DIR")"
SQL_DIR="$SNOWFLAKE_DIR/sql"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Functions
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "\n${BLUE}==>${NC} $1"; }

# Default SnowSQL options
SNOWSQL_OPTS="-r ACCOUNTADMIN -o variable_substitution=true"

# SnowSQL command
if ! command -v snowsql &> /dev/null; then
    SNOWSQL_CMD="$HOME/.snowsql/1.4.5/snowsql"
    if [ ! -f "$SNOWSQL_CMD" ]; then
        log_error "snowsql not found in PATH or at $SNOWSQL_CMD"
        exit 1
    fi
else
    SNOWSQL_CMD="snowsql"
fi

# Run SQL script with error detection
run_sql_with_check() {
    local script_path="$1"
    local script_name=$(basename "$script_path")
    local log_file="/tmp/smdh_${script_name}.log"
    shift

    $SNOWSQL_CMD $SNOWSQL_OPTS "$@" -f "$script_path" > "$log_file" 2>&1
    local exit_code=$?

    if grep -qE "^[0-9]{6} \([0-9]{5}\):" "$log_file"; then
        local error_count=$(grep -cE "^[0-9]{6} \([0-9]{5}\):" "$log_file" || echo 0)
        log_error "$script_name had $error_count SQL error(s)"
        grep -E "^[0-9]{6} \([0-9]{5}\):" "$log_file" | head -10
        echo "Full log: $log_file"
        return 1
    elif [ $exit_code -ne 0 ]; then
        log_error "$script_name failed with exit code $exit_code"
        cat "$log_file"
        return 1
    fi
    return 0
}

show_usage() {
    echo "Usage: $0 <command>"
    echo ""
    echo "Commands:"
    echo "  deploy     Deploy core Snowflake infrastructure"
    echo "  drop       Drop all Snowflake infrastructure (DESTRUCTIVE!)"
    echo "  status     Check current infrastructure state"
    echo "  help       Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 deploy              # Deploy infrastructure"
    echo "  $0 drop                # Drop everything"
    echo "  $0 status              # Check what exists"
    echo ""
    echo "Environment:"
    echo "  SNOWSQL_PWD            Snowflake password (required)"
    echo "  SNOWFLAKE_ACCOUNT      Snowflake account (optional, uses config)"
    echo "  SNOWFLAKE_USER         Snowflake user (optional, uses config)"
}

deploy_infrastructure() {
    echo ""
    echo "============================================="
    echo "   SMDH Core Infrastructure Deployment"
    echo "============================================="
    echo ""

    log_step "Step 1/3: Setting up infrastructure database..."
    if run_sql_with_check "$SQL_DIR/core/01_infrastructure_setup.sql"; then
        log_info "[OK] Infrastructure database created"
    else
        log_error "Failed to create infrastructure database"
        exit 1
    fi

    log_step "Step 2/3: Creating shared resources..."
    if run_sql_with_check "$SQL_DIR/core/02_shared_resources.sql"; then
        log_info "[OK] Shared resources created (warehouse, roles)"
    else
        log_error "Failed to create shared resources"
        exit 1
    fi

    log_step "Step 3/3: Configuring Openflow connector..."
    if run_sql_with_check "$SQL_DIR/core/03_openflow_connector.sql" \
        -D aws_iam_role_arn='arn:aws:iam::placeholder:role/placeholder' \
        -D aws_external_id='placeholder' \
        -D kinesis_stream_arn='arn:aws:kinesis:eu-west-2:placeholder:stream/placeholder'; then
        log_info "[OK] Openflow connector configured (update with real AWS values later)"
    else
        log_warn "Openflow connector setup failed (expected with placeholder values)"
        log_info "Run setup_kinesis_integration.sh with real AWS values after terraform apply"
    fi

    echo ""
    echo "============================================="
    echo "   Infrastructure Deployment Complete!"
    echo "============================================="
    echo ""
    echo "Created:"
    echo "  [OK] Database: smdh_infrastructure"
    echo "  [OK] Warehouse: SMDH_WH"
    echo "  [OK] Roles: smdh_infrastructure_admin, smdh_monitoring, etc."
    echo ""
    echo "Next Steps:"
    echo "  1. Deploy AWS infrastructure: cd ../terraform && terraform apply"
    echo "  2. Configure Kinesis: ./setup_kinesis_integration.sh"
    echo "  3. Onboard a tenant: ./onboard_tenant.sh --tenant-id mycompany --tenant-name 'My Company' --num-sites 3"
    echo ""
}

drop_infrastructure() {
    echo ""
    echo "============================================="
    echo "   SMDH Infrastructure Drop (DESTRUCTIVE!)"
    echo "============================================="
    echo ""

    log_warn "This will DROP ALL SMDH databases, warehouses, and roles!"
    log_warn "All tenant data will be PERMANENTLY DELETED!"
    echo ""
    read -p "Are you sure you want to continue? (type 'yes' to confirm): " confirm

    if [ "$confirm" != "yes" ]; then
        log_info "Operation cancelled"
        exit 0
    fi

    log_step "Dropping all infrastructure..."
    if run_sql_with_check "$SQL_DIR/core/00_drop_all.sql"; then
        log_info "[OK] All infrastructure dropped"
    else
        log_warn "Some objects may not have existed (this is normal for first run)"
    fi

    echo ""
    echo "============================================="
    echo "   Infrastructure Dropped"
    echo "============================================="
    echo ""
}

check_status() {
    echo ""
    echo "============================================="
    echo "   SMDH Infrastructure Status"
    echo "============================================="
    echo ""

    log_step "Checking current state..."
    if [ -f "$SQL_DIR/utility/check_current_state.sql" ]; then
        $SNOWSQL_CMD $SNOWSQL_OPTS -f "$SQL_DIR/utility/check_current_state.sql"
    else
        # Inline status check
        $SNOWSQL_CMD $SNOWSQL_OPTS -q "
            SELECT 'Databases:' AS check_type;
            SHOW DATABASES LIKE 'smdh%';
            SELECT 'Warehouses:' AS check_type;
            SHOW WAREHOUSES LIKE 'smdh%';
            SELECT 'Roles:' AS check_type;
            SHOW ROLES LIKE 'smdh%';
        "
    fi
}

# Main
COMMAND="${1:-help}"

case "$COMMAND" in
    deploy)
        deploy_infrastructure
        ;;
    drop)
        drop_infrastructure
        ;;
    status)
        check_status
        ;;
    help|--help|-h)
        show_usage
        ;;
    *)
        log_error "Unknown command: $COMMAND"
        show_usage
        exit 1
        ;;
esac
