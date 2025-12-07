#!/bin/bash
################################################################################
# SMDH Tenant Validation Script
################################################################################
#
# Purpose: Validate tenant setup across AWS and Snowflake
#
# Usage:
#   ./validate_tenant.sh --tenant-id acme_corp
#   ./validate_tenant.sh --tenant-id acme_corp --send-test-message
#
################################################################################

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
AWS_REGION="${AWS_REGION:-eu-west-2}"
SNOWFLAKE_ACCOUNT="${SNOWFLAKE_ACCOUNT:-qqoylnv-zy42691}"
SNOWFLAKE_USER="${SNOWFLAKE_USER:-AIAPPLIED}"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --tenant-id)         TENANT_ID="$2"; shift 2 ;;
        --send-test-message) SEND_TEST=true; shift ;;
        --aws-region)        AWS_REGION="$2"; shift 2 ;;
        --help)
            echo "Usage: $0 --tenant-id <tenant_id> [--send-test-message] [--aws-region <region>]"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

if [[ -z "${TENANT_ID:-}" ]]; then
    echo "Error: --tenant-id required"
    exit 1
fi

echo ""
echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║   SMDH Tenant Validation: ${TENANT_ID}${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

ERRORS=0
WARNINGS=0

check_pass() { echo -e "${GREEN}✓${NC} $1"; }
check_fail() { echo -e "${RED}✗${NC} $1"; ERRORS=$((ERRORS + 1)); }
check_warn() { echo -e "${YELLOW}⚠${NC} $1"; WARNINGS=$((WARNINGS + 1)); }

################################################################################
# AWS Validation
################################################################################

echo -e "${BLUE}━━━ AWS Resources ━━━${NC}"

# Kinesis Stream
STREAM_NAME="smdh-${TENANT_ID}-stream"
if aws kinesis describe-stream-summary --stream-name "$STREAM_NAME" --region "$AWS_REGION" &>/dev/null; then
    STATUS=$(aws kinesis describe-stream-summary --stream-name "$STREAM_NAME" --region "$AWS_REGION" \
        --query 'StreamDescriptionSummary.StreamStatus' --output text)
    SHARDS=$(aws kinesis describe-stream-summary --stream-name "$STREAM_NAME" --region "$AWS_REGION" \
        --query 'StreamDescriptionSummary.OpenShardCount' --output text)
    if [[ "$STATUS" == "ACTIVE" ]]; then
        check_pass "Kinesis Stream: $STREAM_NAME (${SHARDS} shards, $STATUS)"
    else
        check_warn "Kinesis Stream: $STREAM_NAME ($STATUS - not active)"
    fi
else
    check_fail "Kinesis Stream: $STREAM_NAME (not found)"
fi

# IAM Role
ROLE_NAME="smdh-openflow-${TENANT_ID}-role"
if aws iam get-role --role-name "$ROLE_NAME" &>/dev/null; then
    check_pass "IAM Role: $ROLE_NAME"

    # Check policies
    POLICIES=$(aws iam list-role-policies --role-name "$ROLE_NAME" --query 'PolicyNames' --output text 2>/dev/null || echo "")
    if [[ -n "$POLICIES" ]]; then
        check_pass "  Inline policies: $POLICIES"
    else
        check_warn "  No inline policies attached"
    fi
else
    check_fail "IAM Role: $ROLE_NAME (not found)"
fi

# IoT Rule
RULE_NAME="smdh_${TENANT_ID}_to_kinesis"
if aws iot get-topic-rule --rule-name "$RULE_NAME" --region "$AWS_REGION" &>/dev/null; then
    DISABLED=$(aws iot get-topic-rule --rule-name "$RULE_NAME" --region "$AWS_REGION" \
        --query 'rule.ruleDisabled' --output text)
    if [[ "$DISABLED" == "False" ]]; then
        check_pass "IoT Rule: $RULE_NAME (enabled)"
    else
        check_warn "IoT Rule: $RULE_NAME (disabled)"
    fi

    SQL=$(aws iot get-topic-rule --rule-name "$RULE_NAME" --region "$AWS_REGION" \
        --query 'rule.sql' --output text)
    echo -e "        Topic: ${CYAN}smdh/${TENANT_ID}/+/+${NC}"
else
    check_fail "IoT Rule: $RULE_NAME (not found)"
fi

################################################################################
# Snowflake Validation
################################################################################

echo ""
echo -e "${BLUE}━━━ Snowflake Resources ━━━${NC}"

run_snowsql() {
    snowsql -a "$SNOWFLAKE_ACCOUNT" -u "$SNOWFLAKE_USER" \
        -r ACCOUNTADMIN -w SMDH_WH \
        -o output_format=plain -o header=false -o timing=false \
        -q "$1" 2>/dev/null | tr -d '[:space:]'
}

run_snowsql_output() {
    snowsql -a "$SNOWFLAKE_ACCOUNT" -u "$SNOWFLAKE_USER" \
        -r ACCOUNTADMIN -w SMDH_WH \
        -o output_format=plain -o header=false -o timing=false \
        -q "$1" 2>/dev/null
}

# Check if SNOWSQL_PWD is set
if [[ -z "${SNOWSQL_PWD:-}" ]]; then
    check_warn "SNOWSQL_PWD not set - skipping Snowflake validation"
else
    # Database
    DB_NAME="SMDH_TENANT_${TENANT_ID^^}"
    DB_EXISTS=$(run_snowsql "SELECT COUNT(*) FROM INFORMATION_SCHEMA.DATABASES WHERE DATABASE_NAME = '${DB_NAME}';")
    if [[ "$DB_EXISTS" == "1" ]]; then
        check_pass "Database: $DB_NAME"

        # Schemas
        for SCHEMA in RAW NORMALIZED AGGREGATED ANALYTICS; do
            SCHEMA_EXISTS=$(run_snowsql "SELECT COUNT(*) FROM ${DB_NAME}.INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME = '${SCHEMA}';")
            if [[ "$SCHEMA_EXISTS" == "1" ]]; then
                check_pass "  Schema: ${SCHEMA}"
            else
                check_fail "  Schema: ${SCHEMA} (not found)"
            fi
        done

        # Sensor readings table
        TABLE_EXISTS=$(run_snowsql "SELECT COUNT(*) FROM ${DB_NAME}.INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA = 'RAW' AND TABLE_NAME = 'SENSOR_READINGS';")
        if [[ "$TABLE_EXISTS" == "1" ]]; then
            ROW_COUNT=$(run_snowsql "SELECT COUNT(*) FROM ${DB_NAME}.RAW.SENSOR_READINGS;")
            check_pass "  Table: RAW.SENSOR_READINGS (${ROW_COUNT} rows)"
        else
            check_fail "  Table: RAW.SENSOR_READINGS (not found)"
        fi
    else
        check_fail "Database: $DB_NAME (not found)"
    fi

    # Tenant Registry
    TENANT_EXISTS=$(run_snowsql "SELECT COUNT(*) FROM SMDH_INFRASTRUCTURE.TENANT_CONFIGS.TENANTS WHERE TENANT_ID = '${TENANT_ID}';")
    if [[ "$TENANT_EXISTS" == "1" ]]; then
        TENANT_STATUS=$(run_snowsql "SELECT STATUS FROM SMDH_INFRASTRUCTURE.TENANT_CONFIGS.TENANTS WHERE TENANT_ID = '${TENANT_ID}';")
        check_pass "Tenant Registry: ${TENANT_ID} (status: ${TENANT_STATUS})"
    else
        check_fail "Tenant Registry: ${TENANT_ID} (not registered)"
    fi

    # Openflow Connector Registration
    CONNECTOR_EXISTS=$(run_snowsql "SELECT COUNT(*) FROM SMDH_INFRASTRUCTURE.TENANT_CONFIGS.OPENFLOW_CONNECTORS WHERE TENANT_ID = '${TENANT_ID}';")
    if [[ "$CONNECTOR_EXISTS" -ge "1" ]]; then
        CONNECTOR_STATUS=$(run_snowsql "SELECT STATUS FROM SMDH_INFRASTRUCTURE.TENANT_CONFIGS.OPENFLOW_CONNECTORS WHERE TENANT_ID = '${TENANT_ID}' LIMIT 1;")
        check_pass "Openflow Connector: registered (status: ${CONNECTOR_STATUS})"
    else
        check_warn "Openflow Connector: not registered in tracking table"
    fi

    # Openflow Role Grants
    echo ""
    echo -e "${BLUE}━━━ Openflow Permissions ━━━${NC}"

    GRANTS=$(run_snowsql_output "SHOW GRANTS TO ROLE OPENFLOW_RUNTIME_ROLE_KINESIS;" 2>/dev/null | grep -i "${DB_NAME}" || echo "")
    if [[ -n "$GRANTS" ]]; then
        check_pass "OPENFLOW_RUNTIME_ROLE_KINESIS has grants on ${DB_NAME}"
    else
        check_fail "OPENFLOW_RUNTIME_ROLE_KINESIS missing grants on ${DB_NAME}"
        echo "        Run: CALL smdh_infrastructure.tenant_configs.sp_grant_openflow_tenant_access('${TENANT_ID}');"
    fi
fi

################################################################################
# Optional: Send Test Message
################################################################################

if [[ "${SEND_TEST:-false}" == "true" ]]; then
    echo ""
    echo -e "${BLUE}━━━ Sending Test Message ━━━${NC}"

    PAYLOAD=$(cat << EOF
{
    "deviceId": "validation_test",
    "siteId": "TEST_SITE",
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%S.000Z)",
    "sensorType": "temperature",
    "value": 25.5,
    "unit": "celsius",
    "validation_run": "$(date +%s)"
}
EOF
)

    TOPIC="smdh/${TENANT_ID}/TEST_SITE/validation_test"

    if aws iot-data publish \
        --topic "$TOPIC" \
        --payload "$PAYLOAD" \
        --region "$AWS_REGION" 2>/dev/null; then
        check_pass "Published test message to: $TOPIC"
        echo ""
        echo "Verify data arrival in Snowflake (wait 1-2 minutes):"
        echo "  SELECT * FROM ${DB_NAME}.RAW.SENSOR_READINGS"
        echo "  WHERE payload:validation_run IS NOT NULL"
        echo "  ORDER BY ingestion_timestamp DESC LIMIT 5;"
    else
        check_fail "Failed to publish test message"
    fi
fi

################################################################################
# Summary
################################################################################

echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

if [[ $ERRORS -eq 0 && $WARNINGS -eq 0 ]]; then
    echo -e "${GREEN}✓ All checks passed!${NC}"
elif [[ $ERRORS -eq 0 ]]; then
    echo -e "${YELLOW}⚠ Validation completed with ${WARNINGS} warning(s)${NC}"
else
    echo -e "${RED}✗ Validation failed: ${ERRORS} error(s), ${WARNINGS} warning(s)${NC}"
fi

echo ""
exit $ERRORS
