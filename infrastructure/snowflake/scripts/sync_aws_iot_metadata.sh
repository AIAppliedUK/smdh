#!/bin/bash
# ============================================================================
# SMDH AWS IoT Metadata Sync to Snowflake
# ============================================================================
# Purpose: Sync AWS IoT Thing Groups, Billing Groups, and device data to Snowflake
# Usage: ./sync_aws_iot_metadata.sh --tenant-id company_a [--all-tenants]
# Author: SMDH Platform Team
# Version: 1.0
# ============================================================================
# This script:
# 1. Queries AWS IoT Core for thing groups, billing groups, and devices
# 2. Updates Snowflake infrastructure tables with current AWS state
# 3. Maintains sync of device connectivity and thing group membership
# ============================================================================

set -euo pipefail

# Default values
AWS_REGION="${AWS_REGION:-eu-west-2}"
SNOWFLAKE_ACCOUNT="${SNOWFLAKE_ACCOUNT}"
SNOWFLAKE_USER="${SNOWFLAKE_USER}"
TENANT_ID=""
ALL_TENANTS=false
DRY_RUN=false

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

log_section() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Options:
  --tenant-id <id>     Sync specific tenant (required unless --all-tenants)
  --all-tenants        Sync all tenants
  --region <region>    AWS region (default: eu-west-2)
  --dry-run            Show what would be synced without making changes
  -h, --help           Show this help message

Required Environment Variables:
  SNOWFLAKE_ACCOUNT    Snowflake account identifier
  SNOWFLAKE_USER       Snowflake username

Examples:
  # Sync specific tenant
  $0 --tenant-id company_a

  # Sync all tenants
  $0 --all-tenants

  # Dry run to see what would change
  $0 --tenant-id company_a --dry-run
EOF
    exit 1
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --tenant-id)
            TENANT_ID="$2"
            shift 2
            ;;
        --all-tenants)
            ALL_TENANTS=true
            shift
            ;;
        --region)
            AWS_REGION="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# Validate parameters
if [[ -z "$TENANT_ID" ]] && [[ "$ALL_TENANTS" != true ]]; then
    log_error "Either --tenant-id or --all-tenants must be specified"
    usage
fi

# Check required environment variables
if [[ -z "${SNOWFLAKE_ACCOUNT:-}" ]] || [[ -z "${SNOWFLAKE_USER:-}" ]]; then
    log_error "SNOWFLAKE_ACCOUNT and SNOWFLAKE_USER environment variables must be set"
    exit 1
fi

# ============================================================================
# Sync Start
# ============================================================================

log_section "AWS IoT Metadata Sync to Snowflake"
echo "Region: $AWS_REGION"
echo "Snowflake Account: $SNOWFLAKE_ACCOUNT"
echo "Dry Run: $DRY_RUN"
echo ""

# Function to sync tenant metadata
sync_tenant() {
    local tenant_id=$1

    log_info "Syncing tenant: $tenant_id"

    # Get tenant thing group from AWS
    local tenant_group_name="smdh-tenant-${tenant_id}"

    if ! aws iot describe-thing-group --thing-group-name "$tenant_group_name" --region "$AWS_REGION" &>/dev/null; then
        log_warn "Thing group not found: $tenant_group_name. Skipping tenant."
        return
    fi

    local thing_group_info=$(aws iot describe-thing-group \
        --thing-group-name "$tenant_group_name" \
        --region "$AWS_REGION" \
        --output json)

    local tenant_group_arn=$(echo "$thing_group_info" | jq -r '.thingGroupArn')

    # Get billing group
    local billing_group_name="smdh-billing-${tenant_id}"
    local billing_group_arn=""

    if aws iot describe-billing-group --billing-group-name "$billing_group_name" --region "$AWS_REGION" &>/dev/null; then
        billing_group_arn=$(aws iot describe-billing-group \
            --billing-group-name "$billing_group_name" \
            --region "$AWS_REGION" \
            --query 'billingGroupArn' \
            --output text)
    fi

    # Update tenant record in Snowflake
    local sql_update_tenant="
    UPDATE smdh_infrastructure.tenant_configs.tenants
    SET tenant_thing_group_name = '${tenant_group_name}',
        tenant_thing_group_arn = '${tenant_group_arn}',
        billing_group_name = '${billing_group_name}',
        billing_group_arn = '${billing_group_arn}',
        updated_date = CURRENT_TIMESTAMP()
    WHERE tenant_id = '${tenant_id}';
    "

    if [[ "$DRY_RUN" == true ]]; then
        echo "Would execute: $sql_update_tenant"
    else
        snowsql -a "$SNOWFLAKE_ACCOUNT" -u "$SNOWFLAKE_USER" -q "$sql_update_tenant"
        log_info "Updated tenant: $tenant_id"
    fi

    # Get all site groups for tenant
    local site_groups=$(aws iot list-thing-groups \
        --parent-group "$tenant_group_name" \
        --region "$AWS_REGION" \
        --query 'thingGroups[*].groupName' \
        --output text)

    if [[ -n "$site_groups" ]]; then
        log_info "Found $(echo $site_groups | wc -w | tr -d ' ') site groups"

        for site_group_name in $site_groups; do
            # Extract site_id from group name (format: smdh-{tenant_id}-{site_id})
            local site_id=$(echo "$site_group_name" | sed "s/smdh-${tenant_id}-//")

            # Get site thing group ARN
            local site_group_arn=$(aws iot describe-thing-group \
                --thing-group-name "$site_group_name" \
                --region "$AWS_REGION" \
                --query 'thingGroupArn' \
                --output text)

            # Get device count in site
            local device_count=$(aws iot list-things-in-thing-group \
                --thing-group-name "$site_group_name" \
                --region "$AWS_REGION" \
                --query 'things | length(@)' \
                --output text)

            # Update site record
            local sql_update_site="
            MERGE INTO smdh_infrastructure.tenant_configs.sites AS target
            USING (SELECT '${site_id}' AS site_id, '${tenant_id}' AS tenant_id) AS source
            ON target.site_id = source.site_id AND target.tenant_id = source.tenant_id
            WHEN MATCHED THEN UPDATE SET
                site_thing_group_name = '${site_group_name}',
                site_thing_group_arn = '${site_group_arn}',
                total_devices = ${device_count},
                last_device_sync = CURRENT_TIMESTAMP()
            WHEN NOT MATCHED THEN INSERT (
                site_id, tenant_id, site_name, site_thing_group_name,
                site_thing_group_arn, total_devices, status, created_date
            ) VALUES (
                '${site_id}', '${tenant_id}', '${site_id}',
                '${site_group_name}', '${site_group_arn}',
                ${device_count}, 'active', CURRENT_TIMESTAMP()
            );
            "

            if [[ "$DRY_RUN" == true ]]; then
                echo "Would execute: $sql_update_site"
            else
                snowsql -a "$SNOWFLAKE_ACCOUNT" -u "$SNOWFLAKE_USER" -q "$sql_update_site"
                log_info "Updated site: $site_id (${device_count} devices)"
            fi

            # Sync devices in this site
            local devices=$(aws iot list-things-in-thing-group \
                --thing-group-name "$site_group_name" \
                --region "$AWS_REGION" \
                --query 'things' \
                --output text)

            for device_name in $devices; do
                # Get device details
                local device_info=$(aws iot describe-thing \
                    --thing-name "$device_name" \
                    --region "$AWS_REGION" \
                    --output json)

                local device_arn=$(echo "$device_info" | jq -r '.thingArn')
                local device_type=$(echo "$device_info" | jq -r '.thingTypeName // "unknown"')

                # Get certificate info
                local cert_arn=$(aws iot list-thing-principals \
                    --thing-name "$device_name" \
                    --region "$AWS_REGION" \
                    --query 'principals[0]' \
                    --output text 2>/dev/null || echo "")

                local cert_id=""
                local cert_expiry="NULL"

                if [[ -n "$cert_arn" ]] && [[ "$cert_arn" != "None" ]]; then
                    cert_id=$(echo "$cert_arn" | awk -F'/' '{print $2}')

                    cert_expiry=$(aws iot describe-certificate \
                        --certificate-id "$cert_id" \
                        --region "$AWS_REGION" \
                        --query 'certificateDescription.validity.notAfter' \
                        --output text 2>/dev/null || echo "NULL")

                    if [[ "$cert_expiry" != "NULL" ]]; then
                        cert_expiry="'${cert_expiry}'"
                    fi
                fi

                # Get connectivity status (requires IoT search index)
                local last_connection="NULL"
                local connectivity=$(aws iot search-index \
                    --index-name "AWS_Things" \
                    --query-string "thingName:$device_name" \
                    --region "$AWS_REGION" \
                    --query 'things[0].connectivity.timestamp' \
                    --output text 2>/dev/null || echo "NULL")

                if [[ "$connectivity" != "NULL" ]] && [[ -n "$connectivity" ]]; then
                    last_connection="'${connectivity}'"
                fi

                # Update device record
                local sql_update_device="
                MERGE INTO smdh_infrastructure.tenant_configs.devices AS target
                USING (SELECT '${device_name}' AS device_id) AS source
                ON target.device_id = source.device_id
                WHEN MATCHED THEN UPDATE SET
                    iot_thing_name = '${device_name}',
                    iot_thing_arn = '${device_arn}',
                    device_type = '${device_type}',
                    site_id = '${site_id}',
                    site_thing_group_name = '${site_group_name}',
                    tenant_thing_group_name = '${tenant_group_name}',
                    billing_group_name = '${billing_group_name}',
                    certificate_id = '${cert_id}',
                    certificate_arn = '${cert_arn}',
                    certificate_expiry = ${cert_expiry},
                    last_connection = ${last_connection}
                WHEN NOT MATCHED THEN INSERT (
                    device_id, tenant_id, site_id, device_name, device_type,
                    iot_thing_name, iot_thing_arn, certificate_id, certificate_arn,
                    certificate_expiry, site_thing_group_name, tenant_thing_group_name,
                    billing_group_name, last_connection, status, deployed_date
                ) VALUES (
                    '${device_name}', '${tenant_id}', '${site_id}', '${device_name}',
                    '${device_type}', '${device_name}', '${device_arn}',
                    '${cert_id}', '${cert_arn}', ${cert_expiry},
                    '${site_group_name}', '${tenant_group_name}', '${billing_group_name}',
                    ${last_connection}, 'active', CURRENT_TIMESTAMP()
                );
                "

                if [[ "$DRY_RUN" == true ]]; then
                    echo "Would sync device: $device_name"
                else
                    snowsql -a "$SNOWFLAKE_ACCOUNT" -u "$SNOWFLAKE_USER" -q "$sql_update_device" -o friendly=false -o header=false
                fi
            done
        done
    fi

    log_info "Completed sync for tenant: $tenant_id"
}

# ============================================================================
# Main Sync Logic
# ============================================================================

if [[ "$ALL_TENANTS" == true ]]; then
    # Get all tenant IDs from Snowflake
    TENANTS=$(snowsql -a "$SNOWFLAKE_ACCOUNT" -u "$SNOWFLAKE_USER" \
        -q "SELECT tenant_id FROM smdh_infrastructure.tenant_configs.tenants WHERE status = 'active';" \
        -o friendly=false -o header=false -o output_format=plain | tr -d ' ')

    for tenant in $TENANTS; do
        sync_tenant "$tenant"
    done
else
    sync_tenant "$TENANT_ID"
fi

# ============================================================================
# Sync Complete
# ============================================================================

log_section "Sync Complete"
echo "Timestamp: $(date)"

if [[ "$DRY_RUN" == true ]]; then
    log_warn "DRY RUN - No changes were made"
fi

echo ""
log_info "Query synced data in Snowflake:"
echo "  SELECT * FROM smdh_infrastructure.monitoring.v_thing_group_hierarchy;"
echo "  SELECT * FROM smdh_infrastructure.monitoring.v_site_device_summary;"
echo "  SELECT * FROM smdh_infrastructure.monitoring.v_disconnected_devices;"
