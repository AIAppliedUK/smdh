#!/bin/bash
# ============================================================================
# SMDH IoT Cost Tracking with Billing Groups
# ============================================================================
# Purpose: Track and report AWS IoT costs per tenant using billing groups
# Usage: ./check_iot_costs.sh --tenant-id company_a [--period 7]
# Author: SMDH Platform Team
# Version: 1.0
# ============================================================================

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default values
AWS_REGION="${AWS_REGION:-eu-west-2}"
PERIOD_DAYS=7
OUTPUT_FORMAT="table"
EXPORT_CSV=false
CSV_FILE=""

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
  --tenant-id <id>     Check costs for specific tenant (optional - shows all if omitted)
  --period <days>      Number of days to analyze (default: 7)
  --region <region>    AWS region (default: eu-west-2)
  --format <fmt>       Output format: table, json, csv (default: table)
  --export-csv <file>  Export results to CSV file
  -h, --help           Show this help message

Examples:
  # Check costs for all tenants (last 7 days)
  $0

  # Check specific tenant costs (last 30 days)
  $0 --tenant-id company_a --period 30

  # Export to CSV
  $0 --tenant-id company_a --export-csv costs_report.csv

  # Get JSON output for automation
  $0 --format json
EOF
    exit 1
}

# Parse command line arguments
TENANT_ID=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --tenant-id)
            TENANT_ID="$2"
            shift 2
            ;;
        --period)
            PERIOD_DAYS="$2"
            shift 2
            ;;
        --region)
            AWS_REGION="$2"
            shift 2
            ;;
        --format)
            OUTPUT_FORMAT="$2"
            shift 2
            ;;
        --export-csv)
            EXPORT_CSV=true
            CSV_FILE="$2"
            shift 2
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

# Calculate date range
END_DATE=$(date -u +%Y-%m-%d)
START_DATE=$(date -u -d "$PERIOD_DAYS days ago" +%Y-%m-%d 2>/dev/null || date -u -v-${PERIOD_DAYS}d +%Y-%m-%d)

# ============================================================================
# Cost Tracking Start
# ============================================================================

log_section "SMDH IoT Cost Tracking"
echo "Region: $AWS_REGION"
echo "Period: $START_DATE to $END_DATE ($PERIOD_DAYS days)"
if [[ -n "$TENANT_ID" ]]; then
    echo "Tenant: $TENANT_ID (specific tenant)"
else
    echo "Tenant: ALL (platform-wide)"
fi
echo ""

# ============================================================================
# Get Billing Groups
# ============================================================================

if [[ -n "$TENANT_ID" ]]; then
    # Specific tenant
    BILLING_GROUPS=("smdh-billing-${TENANT_ID}")
else
    # All SMDH billing groups
    BILLING_GROUPS=($(aws iot list-billing-groups \
        --region "$AWS_REGION" \
        --query 'billingGroups[?starts_with(groupName, `smdh-billing-`)].groupName' \
        --output text 2>/dev/null || echo ""))
fi

if [[ ${#BILLING_GROUPS[@]} -eq 0 ]] || [[ -z "${BILLING_GROUPS[0]}" ]]; then
    log_error "No billing groups found"
    log_warn "Run Terraform to create billing groups for tenants"
    exit 1
fi

log_info "Found ${#BILLING_GROUPS[@]} billing group(s)"

# ============================================================================
# Collect Cost Data
# ============================================================================

log_section "IoT Cost Breakdown by Tenant"

# Initialize CSV if exporting
if [[ "$EXPORT_CSV" == true ]]; then
    echo "tenant_id,billing_group,period_start,period_end,total_messages,connectivity_minutes,rule_executions,estimated_cost_usd" > "$CSV_FILE"
    log_info "Exporting to CSV: $CSV_FILE"
fi

# Cost calculation constants (AWS IoT Core pricing for eu-west-2)
COST_PER_MILLION_MESSAGES=1.00  # $1.00 per million messages
COST_PER_MILLION_MINUTES=0.08   # $0.08 per million connection-minutes
COST_PER_MILLION_RULES=0.15     # $0.15 per million rule executions

declare -A TENANT_COSTS
declare -A TENANT_MESSAGES
declare -A TENANT_CONNECTIONS

for BILLING_GROUP in "${BILLING_GROUPS[@]}"; do
    # Extract tenant ID from billing group name
    TENANT=$(echo "$BILLING_GROUP" | sed 's/smdh-billing-//')

    echo ""
    echo "Tenant: $TENANT"
    echo "Billing Group: $BILLING_GROUP"
    echo "----------------------------------------"

    # Get things in billing group
    THINGS=$(aws iot list-things-in-billing-group \
        --billing-group-name "$BILLING_GROUP" \
        --region "$AWS_REGION" \
        --query 'things' \
        --output text 2>/dev/null || echo "")

    if [[ -z "$THINGS" ]]; then
        log_warn "No devices in billing group: $BILLING_GROUP"
        continue
    fi

    THING_COUNT=$(echo "$THINGS" | wc -w | tr -d ' ')
    echo "  Devices in billing group: $THING_COUNT"

    # ========================================================================
    # Calculate Message Costs
    # ========================================================================

    # Get message count from CloudWatch metrics
    # Note: We filter by rule name associated with this tenant
    RULE_NAME="smdh_route_${TENANT//-/_}"

    MESSAGES_PUBLISHED=$(aws cloudwatch get-metric-statistics \
        --namespace AWS/IoT \
        --metric-name PublishIn.Success \
        --start-time "${START_DATE}T00:00:00Z" \
        --end-time "${END_DATE}T23:59:59Z" \
        --period $((PERIOD_DAYS * 86400)) \
        --statistics Sum \
        --region "$AWS_REGION" \
        --query 'Datapoints[0].Sum' \
        --output text 2>/dev/null || echo "0")

    if [[ "$MESSAGES_PUBLISHED" == "None" ]] || [[ -z "$MESSAGES_PUBLISHED" ]]; then
        MESSAGES_PUBLISHED=0
    fi

    MESSAGE_COST=$(echo "scale=4; $MESSAGES_PUBLISHED / 1000000 * $COST_PER_MILLION_MESSAGES" | bc -l)

    echo "  Messages published: $(printf "%'d" ${MESSAGES_PUBLISHED%.*})"
    echo "  Message cost: \$$(printf "%.4f" $MESSAGE_COST)"

    # ========================================================================
    # Calculate Connection Costs
    # ========================================================================

    # Estimate connection minutes (assumes devices are connected 24/7 for simplicity)
    # In reality, you'd track actual connection time from connection/disconnection events
    MINUTES_PER_DAY=$((24 * 60))
    TOTAL_CONNECTION_MINUTES=$((THING_COUNT * MINUTES_PER_DAY * PERIOD_DAYS))

    CONNECTION_COST=$(echo "scale=4; $TOTAL_CONNECTION_MINUTES / 1000000 * $COST_PER_MILLION_MINUTES" | bc -l)

    echo "  Connection minutes (estimated): $(printf "%'d" $TOTAL_CONNECTION_MINUTES)"
    echo "  Connection cost: \$$(printf "%.4f" $CONNECTION_COST)"

    # ========================================================================
    # Calculate Rule Execution Costs
    # ========================================================================

    RULE_EXECUTIONS=$(aws cloudwatch get-metric-statistics \
        --namespace AWS/IoT \
        --metric-name RulesExecuted \
        --dimensions Name=RuleName,Value="$RULE_NAME" \
        --start-time "${START_DATE}T00:00:00Z" \
        --end-time "${END_DATE}T23:59:59Z" \
        --period $((PERIOD_DAYS * 86400)) \
        --statistics Sum \
        --region "$AWS_REGION" \
        --query 'Datapoints[0].Sum' \
        --output text 2>/dev/null || echo "0")

    if [[ "$RULE_EXECUTIONS" == "None" ]] || [[ -z "$RULE_EXECUTIONS" ]]; then
        RULE_EXECUTIONS=0
    fi

    RULE_COST=$(echo "scale=4; $RULE_EXECUTIONS / 1000000 * $COST_PER_MILLION_RULES" | bc -l)

    echo "  Rule executions: $(printf "%'d" ${RULE_EXECUTIONS%.*})"
    echo "  Rule cost: \$$(printf "%.4f" $RULE_COST)"

    # ========================================================================
    # Total Cost
    # ========================================================================

    TOTAL_COST=$(echo "scale=4; $MESSAGE_COST + $CONNECTION_COST + $RULE_COST" | bc -l)

    echo ""
    echo -e "  ${GREEN}Total estimated cost: \$$(printf "%.4f" $TOTAL_COST)${NC}"

    # Calculate daily average
    DAILY_AVG=$(echo "scale=4; $TOTAL_COST / $PERIOD_DAYS" | bc -l)
    echo "  Daily average: \$$(printf "%.4f" $DAILY_AVG)"

    # Calculate monthly projection
    MONTHLY_PROJECTION=$(echo "scale=2; $DAILY_AVG * 30" | bc -l)
    echo "  Monthly projection: \$$(printf "%.2f" $MONTHLY_PROJECTION)"

    # Store for summary
    TENANT_COSTS[$TENANT]=$TOTAL_COST
    TENANT_MESSAGES[$TENANT]=$MESSAGES_PUBLISHED
    TENANT_CONNECTIONS[$TENANT]=$TOTAL_CONNECTION_MINUTES

    # Export to CSV if requested
    if [[ "$EXPORT_CSV" == true ]]; then
        echo "$TENANT,$BILLING_GROUP,$START_DATE,$END_DATE,$MESSAGES_PUBLISHED,$TOTAL_CONNECTION_MINUTES,$RULE_EXECUTIONS,$TOTAL_COST" >> "$CSV_FILE"
    fi
done

# ============================================================================
# Platform-Wide Summary
# ============================================================================

if [[ -z "$TENANT_ID" ]] && [[ ${#TENANT_COSTS[@]} -gt 1 ]]; then
    log_section "Platform-Wide Cost Summary"

    PLATFORM_TOTAL=0
    PLATFORM_MESSAGES=0

    for TENANT in "${!TENANT_COSTS[@]}"; do
        PLATFORM_TOTAL=$(echo "scale=4; $PLATFORM_TOTAL + ${TENANT_COSTS[$TENANT]}" | bc -l)
        PLATFORM_MESSAGES=$((PLATFORM_MESSAGES + ${TENANT_MESSAGES[$TENANT]%.*}))
    done

    echo "Total tenants: ${#TENANT_COSTS[@]}"
    echo "Total messages: $(printf "%'d" $PLATFORM_MESSAGES)"
    echo -e "${GREEN}Platform total cost: \$$(printf "%.2f" $PLATFORM_TOTAL)${NC}"

    # Monthly projection
    DAILY_AVG=$(echo "scale=4; $PLATFORM_TOTAL / $PERIOD_DAYS" | bc -l)
    MONTHLY_PROJECTION=$(echo "scale=2; $DAILY_AVG * 30" | bc -l)
    echo "Monthly projection: \$$(printf "%.2f" $MONTHLY_PROJECTION)"

    # Top cost contributors
    echo ""
    echo "Top Cost Contributors:"
    for TENANT in "${!TENANT_COSTS[@]}"; do
        COST=${TENANT_COSTS[$TENANT]}
        PCT=$(echo "scale=1; $COST / $PLATFORM_TOTAL * 100" | bc -l)
        echo "  $TENANT: \$$(printf "%.2f" $COST) ($(printf "%.1f" $PCT)%)"
    done | sort -t'$' -k2 -rn | head -5
fi

# ============================================================================
# Cost Optimization Recommendations
# ============================================================================

log_section "Cost Optimization Recommendations"

# Check for high message volumes
for TENANT in "${!TENANT_MESSAGES[@]}"; do
    MESSAGES=${TENANT_MESSAGES[$TENANT]%.*}
    DAILY_MESSAGES=$((MESSAGES / PERIOD_DAYS))

    if [[ $DAILY_MESSAGES -gt 1000000 ]]; then
        log_warn "High message volume for $TENANT:"
        echo "  • Consider message batching to reduce per-message costs"
        echo "  • Current: $(printf "%'d" $DAILY_MESSAGES) messages/day"
    fi
done

# Check for unused connections
for BILLING_GROUP in "${BILLING_GROUPS[@]}"; do
    TENANT=$(echo "$BILLING_GROUP" | sed 's/smdh-billing-//')

    # Get disconnected devices
    DISCONNECTED_COUNT=$(aws iot list-things-in-thing-group \
        --thing-group-name "smdh-${TENANT}-disconnected" \
        --region "$AWS_REGION" \
        --query 'things | length(@)' \
        --output text 2>/dev/null || echo "0")

    if [[ $DISCONNECTED_COUNT -gt 0 ]]; then
        log_warn "Tenant $TENANT has $DISCONNECTED_COUNT disconnected devices"
        echo "  • Remove or deactivate unused device certificates"
    fi
done

# General recommendations
echo ""
log_info "General Recommendations:"
echo "  • Use QoS 0 instead of QoS 1 when message delivery guarantees aren't critical"
echo "  • Implement message compression for large payloads"
echo "  • Use device shadows instead of frequent polling"
echo "  • Batch multiple sensor readings into single MQTT messages"
echo "  • Set up CloudWatch billing alarms for cost monitoring"

# ============================================================================
# Additional Cost Metrics
# ============================================================================

log_section "Additional Cost Breakdown"

echo "Kinesis Data Streams Cost (Per-Tenant Stream):"
# Per-tenant Kinesis stream: smdh-{tenant_id}-stream
KINESIS_STREAM="smdh-${TENANT_ID}-stream"

KINESIS_RECORDS=$(aws cloudwatch get-metric-statistics \
    --namespace AWS/Kinesis \
    --metric-name IncomingRecords \
    --dimensions Name=StreamName,Value="$KINESIS_STREAM" \
    --start-time "${START_DATE}T00:00:00Z" \
    --end-time "${END_DATE}T23:59:59Z" \
    --period $((PERIOD_DAYS * 86400)) \
    --statistics Sum \
    --region "$AWS_REGION" \
    --query 'Datapoints[0].Sum' \
    --output text 2>/dev/null || echo "0")

if [[ "$KINESIS_RECORDS" == "None" ]] || [[ -z "$KINESIS_RECORDS" ]]; then
    KINESIS_RECORDS=0
fi

# Kinesis On-Demand pricing: $0.04 per 1M PUT payload units
# 1 payload unit = 25KB, average sensor message ~500 bytes = 0.02 units
KINESIS_UNITS=$(echo "scale=0; $KINESIS_RECORDS * 0.02" | bc -l)
KINESIS_COST=$(echo "scale=4; $KINESIS_UNITS / 1000000 * 0.04" | bc -l)

echo "  Records ingested: $(printf "%'d" ${KINESIS_RECORDS%.*})"
echo "  Estimated cost: \$$(printf "%.4f" $KINESIS_COST)"

echo ""
echo "Snowflake Ingestion Cost:"
echo "  • Openflow connector: Included in Snowflake compute costs"
echo "  • Storage: Based on data volume (check Snowflake billing)"
echo "  • Compute: Warehouse usage during ingestion and processing"

# ============================================================================
# Cost Report Complete
# ============================================================================

echo ""
log_section "Cost Report Complete"
echo "Report generated: $(date)"

if [[ "$EXPORT_CSV" == true ]]; then
    log_info "CSV report exported to: $CSV_FILE"
    echo ""
    echo "To analyze in Excel/Google Sheets:"
    echo "  1. Open $CSV_FILE"
    echo "  2. Create pivot tables to analyze costs by tenant"
    echo "  3. Track cost trends over time"
fi

echo ""
log_info "For detailed AWS billing, visit:"
echo "  https://console.aws.amazon.com/billing/home?region=${AWS_REGION}#/"
