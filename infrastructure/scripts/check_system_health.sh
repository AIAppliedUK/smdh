#!/bin/bash
# ============================================================================
# SMDH System Health Check with Thing Group Support
# ============================================================================
# Purpose: Check system health using AWS IoT Thing Groups for efficient queries
# Usage: ./check_system_health.sh --tenant-id company_a [--site-id site_001]
# Author: SMDH Platform Team
# Version: 2.0 (with Thing Group support)
# ============================================================================

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default values
AWS_REGION="${AWS_REGION:-eu-west-2}"
SITE_ID=""
VERBOSE=false

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
Usage: $0 --tenant-id <tenant_id> [OPTIONS]

Required Arguments:
  --tenant-id <id>     Tenant identifier (e.g., company_a)

Optional Arguments:
  --site-id <id>       Check specific site only (e.g., site_001)
  --region <region>    AWS region (default: eu-west-2)
  --verbose            Show detailed output
  -h, --help           Show this help message

Examples:
  # Check all sites for a tenant
  $0 --tenant-id company_a

  # Check specific site
  $0 --tenant-id company_a --site-id site_001

  # Verbose output
  $0 --tenant-id company_a --verbose
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
        --site-id)
            SITE_ID="$2"
            shift 2
            ;;
        --region)
            AWS_REGION="$2"
            shift 2
            ;;
        --verbose)
            VERBOSE=true
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

# Validate required parameters
if [[ -z "${TENANT_ID:-}" ]]; then
    log_error "Missing required parameter: --tenant-id"
    usage
fi

# ============================================================================
# Health Check Start
# ============================================================================

log_section "SMDH System Health Check"
echo "Tenant: $TENANT_ID"
echo "Region: $AWS_REGION"
if [[ -n "$SITE_ID" ]]; then
    echo "Site: $SITE_ID (specific site check)"
else
    echo "Site: ALL (tenant-wide check)"
fi
echo "Time: $(date)"

# ============================================================================
# Check 1: Thing Group Status
# ============================================================================

log_section "1. Thing Group Overview"

TENANT_GROUP_NAME="smdh-tenant-${TENANT_ID}"

# Check if tenant thing group exists
if aws iot describe-thing-group \
    --thing-group-name "$TENANT_GROUP_NAME" \
    --region "$AWS_REGION" &>/dev/null; then

    log_info "Tenant thing group found: $TENANT_GROUP_NAME"

    # Get total device count in tenant
    TOTAL_DEVICES=$(aws iot list-things-in-thing-group \
        --thing-group-name "$TENANT_GROUP_NAME" \
        --region "$AWS_REGION" \
        --query 'things | length(@)' \
        --output text)

    echo "  Total devices in tenant: $TOTAL_DEVICES"

    # Get thing group details
    if [[ "$VERBOSE" == true ]]; then
        echo ""
        echo "  Thing Group Details:"
        aws iot describe-thing-group \
            --thing-group-name "$TENANT_GROUP_NAME" \
            --region "$AWS_REGION" \
            --query 'thingGroupProperties.attributePayload.attributes' \
            --output table
    fi
else
    log_error "Tenant thing group not found: $TENANT_GROUP_NAME"
    log_warn "Run Terraform to create thing groups for this tenant"
    exit 1
fi

# ============================================================================
# Check 2: Site-Level Status
# ============================================================================

log_section "2. Site-Level Device Status"

if [[ -n "$SITE_ID" ]]; then
    # Check specific site
    SITE_GROUPS=("smdh-${TENANT_ID}-${SITE_ID}")
else
    # Get all site groups for tenant
    SITE_GROUPS=($(aws iot list-thing-groups \
        --parent-group "$TENANT_GROUP_NAME" \
        --region "$AWS_REGION" \
        --query 'thingGroups[*].groupName' \
        --output text))
fi

if [[ ${#SITE_GROUPS[@]} -eq 0 ]]; then
    log_warn "No site groups found for tenant: $TENANT_ID"
else
    for SITE_GROUP in "${SITE_GROUPS[@]}"; do
        echo ""
        echo "Site Group: $SITE_GROUP"
        echo "----------------------------------------"

        # Get devices in this site
        SITE_DEVICES=$(aws iot list-things-in-thing-group \
            --thing-group-name "$SITE_GROUP" \
            --region "$AWS_REGION" \
            --query 'things' \
            --output text)

        if [[ -z "$SITE_DEVICES" ]]; then
            log_warn "  No devices found in site group: $SITE_GROUP"
            continue
        fi

        DEVICE_COUNT=$(echo "$SITE_DEVICES" | wc -w | tr -d ' ')
        echo "  Total devices: $DEVICE_COUNT"

        # Check connectivity for each device
        CONNECTED=0
        DISCONNECTED=0

        for DEVICE in $SITE_DEVICES; do
            CONNECTIVITY=$(aws iot describe-thing \
                --thing-name "$DEVICE" \
                --region "$AWS_REGION" \
                --query 'attributes.connectivity' \
                --output text 2>/dev/null || echo "unknown")

            # Use IoT search index for connectivity (more reliable)
            CONNECTED_STATUS=$(aws iot search-index \
                --index-name "AWS_Things" \
                --query-string "thingName:$DEVICE" \
                --region "$AWS_REGION" \
                --query 'things[0].connectivity.connected' \
                --output text 2>/dev/null || echo "false")

            if [[ "$CONNECTED_STATUS" == "true" ]]; then
                ((CONNECTED++))
                if [[ "$VERBOSE" == true ]]; then
                    echo -e "    ${GREEN}✓${NC} $DEVICE (connected)"
                fi
            else
                ((DISCONNECTED++))
                if [[ "$VERBOSE" == true ]]; then
                    echo -e "    ${RED}✗${NC} $DEVICE (disconnected)"
                else
                    echo -e "    ${RED}✗${NC} $DEVICE (disconnected)"
                fi
            fi
        done

        echo "  Status Summary:"
        echo -e "    Connected:    ${GREEN}$CONNECTED${NC} devices"
        echo -e "    Disconnected: ${RED}$DISCONNECTED${NC} devices"

        # Health percentage
        if [[ $DEVICE_COUNT -gt 0 ]]; then
            HEALTH_PCT=$((CONNECTED * 100 / DEVICE_COUNT))
            if [[ $HEALTH_PCT -ge 80 ]]; then
                echo -e "    Site Health:  ${GREEN}${HEALTH_PCT}%${NC}"
            elif [[ $HEALTH_PCT -ge 50 ]]; then
                echo -e "    Site Health:  ${YELLOW}${HEALTH_PCT}%${NC}"
            else
                echo -e "    Site Health:  ${RED}${HEALTH_PCT}%${NC}"
            fi
        fi
    done
fi

# ============================================================================
# Check 3: Dynamic Thing Groups (Disconnected Devices)
# ============================================================================

log_section "3. Disconnected Devices Alert"

DISCONNECTED_GROUP="smdh-${TENANT_ID}-disconnected"

DISCONNECTED_DEVICES=$(aws iot list-things-in-thing-group \
    --thing-group-name "$DISCONNECTED_GROUP" \
    --region "$AWS_REGION" \
    --query 'things' \
    --output text 2>/dev/null || echo "")

if [[ -n "$DISCONNECTED_DEVICES" ]]; then
    DISCONNECTED_COUNT=$(echo "$DISCONNECTED_DEVICES" | wc -w | tr -d ' ')
    log_warn "Found $DISCONNECTED_COUNT disconnected device(s):"

    for DEVICE in $DISCONNECTED_DEVICES; do
        # Get last connection time
        LAST_SEEN=$(aws iot search-index \
            --index-name "AWS_Things" \
            --query-string "thingName:$DEVICE" \
            --region "$AWS_REGION" \
            --query 'things[0].connectivity.timestamp' \
            --output text 2>/dev/null || echo "unknown")

        echo "  - $DEVICE (last seen: $LAST_SEEN)"
    done
else
    log_info "No disconnected devices - all systems operational!"
fi

# ============================================================================
# Check 4: MQTT Message Rate (last hour)
# ============================================================================

log_section "4. MQTT Message Ingestion (last hour)"

MESSAGES=$(aws cloudwatch get-metric-statistics \
    --namespace AWS/IoT \
    --metric-name PublishIn.Success \
    --start-time "$(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S)" \
    --end-time "$(date -u +%Y-%m-%dT%H:%M:%S)" \
    --period 3600 \
    --statistics Sum \
    --region "$AWS_REGION" \
    --query 'Datapoints[0].Sum' \
    --output text 2>/dev/null || echo "0")

if [[ "$MESSAGES" == "None" ]] || [[ -z "$MESSAGES" ]]; then
    MESSAGES=0
fi

echo "Total messages published (last hour): $MESSAGES"

if [[ $(echo "$MESSAGES > 0" | bc -l) -eq 1 ]]; then
    MSG_PER_MIN=$(echo "scale=2; $MESSAGES / 60" | bc -l)
    echo "Average rate: ${MSG_PER_MIN} messages/minute"
else
    log_warn "No messages received in the last hour"
fi

# ============================================================================
# Check 5: Kinesis Stream Health
# ============================================================================

log_section "5. Kinesis Stream Health"

STREAM_NAME="smdh-sensor-data-stream"

STREAM_STATUS=$(aws kinesis describe-stream \
    --stream-name "$STREAM_NAME" \
    --region "$AWS_REGION" \
    --query 'StreamDescription.StreamStatus' \
    --output text 2>/dev/null || echo "NOT_FOUND")

if [[ "$STREAM_STATUS" == "ACTIVE" ]]; then
    log_info "Kinesis stream: $STREAM_NAME - ${GREEN}ACTIVE${NC}"

    # Get shard count
    SHARD_COUNT=$(aws kinesis describe-stream \
        --stream-name "$STREAM_NAME" \
        --region "$AWS_REGION" \
        --query 'StreamDescription.Shards | length(@)' \
        --output text)

    echo "  Active shards: $SHARD_COUNT"

    # Get incoming records (last 5 minutes)
    INCOMING_RECORDS=$(aws cloudwatch get-metric-statistics \
        --namespace AWS/Kinesis \
        --metric-name IncomingRecords \
        --dimensions Name=StreamName,Value="$STREAM_NAME" \
        --start-time "$(date -u -d '5 minutes ago' +%Y-%m-%dT%H:%M:%S)" \
        --end-time "$(date -u +%Y-%m-%dT%H:%M:%S)" \
        --period 300 \
        --statistics Sum \
        --region "$AWS_REGION" \
        --query 'Datapoints[0].Sum' \
        --output text 2>/dev/null || echo "0")

    echo "  Incoming records (last 5 min): $INCOMING_RECORDS"
else
    log_error "Kinesis stream status: $STREAM_STATUS"
fi

# ============================================================================
# Check 6: Certificate Expiry
# ============================================================================

log_section "6. Certificate Expiry Check"

# Get certificates for tenant devices
TENANT_THINGS=$(aws iot list-things-in-thing-group \
    --thing-group-name "$TENANT_GROUP_NAME" \
    --region "$AWS_REGION" \
    --query 'things' \
    --output text 2>/dev/null || echo "")

if [[ -n "$TENANT_THINGS" ]]; then
    EXPIRING_SOON=0

    for THING in $TENANT_THINGS; do
        # Get principals (certificates) attached to thing
        PRINCIPALS=$(aws iot list-thing-principals \
            --thing-name "$THING" \
            --region "$AWS_REGION" \
            --query 'principals' \
            --output text 2>/dev/null || echo "")

        for PRINCIPAL in $PRINCIPALS; do
            # Extract certificate ID from ARN
            CERT_ID=$(echo "$PRINCIPAL" | awk -F'/' '{print $2}')

            # Get certificate details
            CERT_INFO=$(aws iot describe-certificate \
                --certificate-id "$CERT_ID" \
                --region "$AWS_REGION" \
                2>/dev/null || continue)

            EXPIRY_DATE=$(echo "$CERT_INFO" | jq -r '.certificateDescription.validity.notAfter')
            CERT_STATUS=$(echo "$CERT_INFO" | jq -r '.certificateDescription.status')

            # Calculate days until expiry
            if [[ -n "$EXPIRY_DATE" ]] && [[ "$EXPIRY_DATE" != "null" ]]; then
                EXPIRY_EPOCH=$(date -j -f "%Y-%m-%dT%H:%M:%S" "${EXPIRY_DATE%.*}" +%s 2>/dev/null || date -d "$EXPIRY_DATE" +%s)
                NOW_EPOCH=$(date +%s)
                DAYS_UNTIL_EXPIRY=$(( (EXPIRY_EPOCH - NOW_EPOCH) / 86400 ))

                if [[ $DAYS_UNTIL_EXPIRY -lt 30 ]]; then
                    ((EXPIRING_SOON++))
                    log_warn "Certificate expires soon:"
                    echo "    Thing: $THING"
                    echo "    Cert ID: $CERT_ID"
                    echo "    Status: $CERT_STATUS"
                    echo "    Expires in: $DAYS_UNTIL_EXPIRY days"
                fi
            fi
        done
    done

    if [[ $EXPIRING_SOON -eq 0 ]]; then
        log_info "All certificates valid for >30 days"
    else
        log_warn "Found $EXPIRING_SOON certificate(s) expiring within 30 days"
    fi
fi

# ============================================================================
# Check 7: CloudWatch Alarms
# ============================================================================

log_section "7. Active CloudWatch Alarms"

ALARMS=$(aws cloudwatch describe-alarms \
    --alarm-name-prefix "smdh-${TENANT_ID}" \
    --state-value ALARM \
    --region "$AWS_REGION" \
    --query 'MetricAlarms[*].{Name:AlarmName,State:StateValue,Reason:StateReason}' \
    --output json 2>/dev/null || echo "[]")

ALARM_COUNT=$(echo "$ALARMS" | jq length)

if [[ $ALARM_COUNT -gt 0 ]]; then
    log_warn "Found $ALARM_COUNT active alarm(s):"
    echo "$ALARMS" | jq -r '.[] | "  - \(.Name): \(.Reason)"'
else
    log_info "No active alarms - all metrics within thresholds"
fi

# ============================================================================
# Health Check Summary
# ============================================================================

log_section "Health Check Summary"

# Calculate overall health score
CHECKS_PASSED=0
CHECKS_TOTAL=7

# Check 1: Thing group exists
if aws iot describe-thing-group --thing-group-name "$TENANT_GROUP_NAME" --region "$AWS_REGION" &>/dev/null; then
    ((CHECKS_PASSED++))
fi

# Check 2: At least one site with devices
if [[ ${#SITE_GROUPS[@]} -gt 0 ]]; then
    ((CHECKS_PASSED++))
fi

# Check 3: No disconnected devices
if [[ -z "$DISCONNECTED_DEVICES" ]]; then
    ((CHECKS_PASSED++))
fi

# Check 4: Messages flowing
if [[ $(echo "$MESSAGES > 0" | bc -l) -eq 1 ]]; then
    ((CHECKS_PASSED++))
fi

# Check 5: Kinesis active
if [[ "$STREAM_STATUS" == "ACTIVE" ]]; then
    ((CHECKS_PASSED++))
fi

# Check 6: No expiring certificates
if [[ $EXPIRING_SOON -eq 0 ]]; then
    ((CHECKS_PASSED++))
fi

# Check 7: No alarms
if [[ $ALARM_COUNT -eq 0 ]]; then
    ((CHECKS_PASSED++))
fi

HEALTH_SCORE=$((CHECKS_PASSED * 100 / CHECKS_TOTAL))

echo "Overall Health Score: $HEALTH_SCORE% ($CHECKS_PASSED/$CHECKS_TOTAL checks passed)"

if [[ $HEALTH_SCORE -ge 85 ]]; then
    echo -e "System Status: ${GREEN}HEALTHY${NC} ✓"
    EXIT_CODE=0
elif [[ $HEALTH_SCORE -ge 60 ]]; then
    echo -e "System Status: ${YELLOW}DEGRADED${NC} ⚠"
    EXIT_CODE=1
else
    echo -e "System Status: ${RED}CRITICAL${NC} ✗"
    EXIT_CODE=2
fi

echo ""
echo "Health check completed at $(date)"

exit $EXIT_CODE
