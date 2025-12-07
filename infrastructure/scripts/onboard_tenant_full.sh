#!/bin/bash
################################################################################
# SMDH Full Tenant Onboarding Automation
################################################################################
#
# Purpose: End-to-end tenant onboarding - AWS + Snowflake + Openflow
#
# Usage:
#   ./onboard_tenant_full.sh \
#     --tenant-id acme_corp \
#     --tenant-name "ACME Corporation" \
#     --num-sites 5 \
#     --contact-email ops@acme.com
#
# Prerequisites:
#   - AWS CLI configured with appropriate permissions
#   - SnowSQL installed and SNOWSQL_PWD set
#   - ACCOUNTADMIN role access in Snowflake
#
# What this script does:
#   1. Creates AWS Kinesis Data Stream for tenant
#   2. Creates IAM role for Snowflake Openflow access
#   3. Creates IoT Core rule to route tenant data
#   4. Creates Snowflake tenant database with all schemas/tables
#   5. Grants Openflow access to tenant database
#   6. Registers tenant and connector in tracking tables
#   7. Outputs next steps for Openflow UI configuration
#
################################################################################

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
SNOWFLAKE_DIR="$PROJECT_ROOT/snowflake"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Helper function for uppercase conversion (portable)
to_upper() {
    echo "$1" | tr '[:lower:]' '[:upper:]'
}

# Default configuration
AWS_REGION="${AWS_REGION:-eu-west-2}"
AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-}"
SNOWFLAKE_ACCOUNT="${SNOWFLAKE_ACCOUNT:-qqoylnv-zy42691}"
SNOWFLAKE_USER="${SNOWFLAKE_USER:-AIAPPLIED}"
SNOWFLAKE_ROLE="ACCOUNTADMIN"
KINESIS_SHARD_COUNT="${KINESIS_SHARD_COUNT:-2}"

# Logging functions
log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()  { echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; echo -e "${BLUE}▶${NC} $1"; }

# Cleanup function for rollback on failure
cleanup() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        log_error "Onboarding failed. Manual cleanup may be required."
        echo ""
        echo "Resources that may need cleanup:"
        echo "  AWS: Kinesis stream 'smdh-${TENANT_ID}-stream'"
        echo "  AWS: IAM role 'smdh-openflow-${TENANT_ID}-role'"
        echo "  AWS: IoT rule 'smdh_${TENANT_ID}_to_kinesis'"
        echo "  Snowflake: Database 'SMDH_TENANT_$(echo $TENANT_ID | tr '[:lower:]' '[:upper:]')'"
    fi
    exit $exit_code
}
trap cleanup EXIT

# Parse arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --tenant-id)       TENANT_ID="$2"; shift 2 ;;
            --tenant-name)     TENANT_NAME="$2"; shift 2 ;;
            --num-sites)       NUM_SITES="$2"; shift 2 ;;
            --contact-email)   CONTACT_EMAIL="$2"; shift 2 ;;
            --aws-region)      AWS_REGION="$2"; shift 2 ;;
            --shard-count)     KINESIS_SHARD_COUNT="$2"; shift 2 ;;
            --skip-aws)        SKIP_AWS=true; shift ;;
            --skip-snowflake)  SKIP_SNOWFLAKE=true; shift ;;
            --dry-run)         DRY_RUN=true; shift ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
}

show_help() {
    cat << EOF
SMDH Full Tenant Onboarding

Usage: $0 [OPTIONS]

Required Options:
  --tenant-id ID          Tenant identifier (lowercase, alphanumeric, underscores)
  --tenant-name NAME      Tenant display name
  --num-sites N           Number of manufacturing sites

Optional Options:
  --contact-email EMAIL   Tenant contact email
  --aws-region REGION     AWS region (default: eu-west-2)
  --shard-count N         Kinesis shard count (default: 2)
  --skip-aws              Skip AWS resource creation
  --skip-snowflake        Skip Snowflake resource creation
  --dry-run               Show what would be done without executing
  --help                  Show this help message

Environment Variables:
  AWS_REGION              AWS region (alternative to --aws-region)
  AWS_ACCOUNT_ID          AWS account ID (auto-detected if not set)
  SNOWFLAKE_ACCOUNT       Snowflake account identifier
  SNOWFLAKE_USER          Snowflake username
  SNOWSQL_PWD             Snowflake password

Examples:
  # Full onboarding
  $0 --tenant-id acme_corp --tenant-name "ACME Corp" --num-sites 3

  # Skip AWS (Snowflake only)
  $0 --tenant-id acme_corp --tenant-name "ACME Corp" --num-sites 3 --skip-aws

  # Dry run
  $0 --tenant-id acme_corp --tenant-name "ACME Corp" --num-sites 3 --dry-run
EOF
}

# Validation
validate_inputs() {
    local errors=0

    if [[ -z "${TENANT_ID:-}" ]]; then
        log_error "Missing required: --tenant-id"
        errors=$((errors + 1))
    elif ! [[ $TENANT_ID =~ ^[a-z0-9_]+$ ]]; then
        log_error "Tenant ID must be lowercase alphanumeric with underscores only"
        errors=$((errors + 1))
    fi

    if [[ -z "${TENANT_NAME:-}" ]]; then
        log_error "Missing required: --tenant-name"
        errors=$((errors + 1))
    fi

    if [[ -z "${NUM_SITES:-}" ]]; then
        log_error "Missing required: --num-sites"
        errors=$((errors + 1))
    fi

    if [[ $errors -gt 0 ]]; then
        echo ""
        echo "Run with --help for usage information"
        exit 1
    fi
}

# Check prerequisites
check_prerequisites() {
    log_step "Checking Prerequisites"
    local errors=0

    # AWS CLI
    if [[ "${SKIP_AWS:-false}" != "true" ]]; then
        if command -v aws &> /dev/null; then
            log_info "✓ AWS CLI installed"

            # Get AWS account ID
            if [[ -z "${AWS_ACCOUNT_ID:-}" ]]; then
                AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")
                if [[ -n "$AWS_ACCOUNT_ID" ]]; then
                    log_info "✓ AWS Account: $AWS_ACCOUNT_ID"
                else
                    log_error "✗ Cannot determine AWS Account ID. Check AWS credentials."
                    errors=$((errors + 1))
                fi
            else
                log_info "✓ AWS Account: $AWS_ACCOUNT_ID"
            fi
        else
            log_error "✗ AWS CLI not found"
            errors=$((errors + 1))
        fi
    else
        log_warn "⊘ Skipping AWS checks (--skip-aws)"
    fi

    # SnowSQL
    if [[ "${SKIP_SNOWFLAKE:-false}" != "true" ]]; then
        if command -v snowsql &> /dev/null; then
            log_info "✓ SnowSQL installed"
        else
            log_error "✗ SnowSQL not found"
            errors=$((errors + 1))
        fi

        # Check for either password or key-pair authentication
        if [[ -n "${SNOWSQL_PWD:-}" ]]; then
            log_info "✓ SNOWSQL_PWD set (password auth)"
        elif [[ -f "$HOME/.snowsql/config" ]] && grep -q "private_key_path" "$HOME/.snowsql/config"; then
            log_info "✓ Key-pair authentication configured"
        else
            log_error "✗ No Snowflake credentials found"
            log_error "  Set SNOWSQL_PWD or configure private_key_path in ~/.snowsql/config"
            errors=$((errors + 1))
        fi
    else
        log_warn "⊘ Skipping Snowflake checks (--skip-snowflake)"
    fi

    if [[ $errors -gt 0 ]]; then
        log_error "Prerequisites check failed"
        exit 1
    fi

    log_info "All prerequisites satisfied"
}

################################################################################
# AWS Functions
################################################################################

create_kinesis_stream() {
    log_step "Creating Kinesis Data Stream"

    local stream_name="smdh-${TENANT_ID}-stream"

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY RUN] Would create Kinesis stream: $stream_name"
        return 0
    fi

    # Check if stream exists
    if aws kinesis describe-stream --stream-name "$stream_name" --region "$AWS_REGION" &>/dev/null; then
        log_warn "Kinesis stream '$stream_name' already exists"
        return 0
    fi

    # Create stream
    log_info "Creating Kinesis stream: $stream_name (${KINESIS_SHARD_COUNT} shards)"
    aws kinesis create-stream \
        --stream-name "$stream_name" \
        --shard-count "$KINESIS_SHARD_COUNT" \
        --region "$AWS_REGION" \
        --tags Key=Project,Value=SMDH Key=Tenant,Value="$TENANT_ID" Key=ManagedBy,Value=Script

    # Wait for stream to be active
    log_info "Waiting for stream to become active..."
    aws kinesis wait stream-exists \
        --stream-name "$stream_name" \
        --region "$AWS_REGION"

    # Verify
    local status
    status=$(aws kinesis describe-stream-summary \
        --stream-name "$stream_name" \
        --region "$AWS_REGION" \
        --query 'StreamDescriptionSummary.StreamStatus' \
        --output text)

    if [[ "$status" == "ACTIVE" ]]; then
        log_info "✓ Kinesis stream created and active"
        KINESIS_STREAM_ARN=$(aws kinesis describe-stream-summary \
            --stream-name "$stream_name" \
            --region "$AWS_REGION" \
            --query 'StreamDescriptionSummary.StreamARN' \
            --output text)
        log_info "  ARN: $KINESIS_STREAM_ARN"
    else
        log_error "Stream creation failed. Status: $status"
        return 1
    fi
}

create_iam_role() {
    log_step "Creating IAM Role for Openflow"

    local role_name="smdh-openflow-${TENANT_ID}-role"
    local stream_name="smdh-${TENANT_ID}-stream"

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY RUN] Would create IAM role: $role_name"
        return 0
    fi

    # Check if role exists
    if aws iam get-role --role-name "$role_name" &>/dev/null; then
        log_warn "IAM role '$role_name' already exists"
        IAM_ROLE_ARN=$(aws iam get-role --role-name "$role_name" --query 'Role.Arn' --output text)
        log_info "  ARN: $IAM_ROLE_ARN"
        return 0
    fi

    # Trust policy (placeholder - updated after Snowflake Openflow setup)
    local trust_policy=$(cat << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "AWS": "arn:aws:iam::${AWS_ACCOUNT_ID}:root"
            },
            "Action": "sts:AssumeRole",
            "Condition": {}
        }
    ]
}
EOF
)

    # Create role
    log_info "Creating IAM role: $role_name"
    aws iam create-role \
        --role-name "$role_name" \
        --assume-role-policy-document "$trust_policy" \
        --description "IAM role for Snowflake Openflow to access ${TENANT_ID} Kinesis stream" \
        --tags Key=Project,Value=SMDH Key=Tenant,Value="$TENANT_ID" Key=ManagedBy,Value=Script

    # Permissions policy
    local permissions_policy=$(cat << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "KinesisReadAccess",
            "Effect": "Allow",
            "Action": [
                "kinesis:GetShardIterator",
                "kinesis:GetRecords",
                "kinesis:DescribeStream",
                "kinesis:DescribeStreamSummary",
                "kinesis:ListShards",
                "kinesis:SubscribeToShard"
            ],
            "Resource": "arn:aws:kinesis:${AWS_REGION}:${AWS_ACCOUNT_ID}:stream/${stream_name}"
        },
        {
            "Sid": "DynamoDBCheckpointing",
            "Effect": "Allow",
            "Action": [
                "dynamodb:CreateTable",
                "dynamodb:DescribeTable",
                "dynamodb:GetItem",
                "dynamodb:PutItem",
                "dynamodb:UpdateItem",
                "dynamodb:DeleteItem",
                "dynamodb:Scan"
            ],
            "Resource": "arn:aws:dynamodb:${AWS_REGION}:${AWS_ACCOUNT_ID}:table/smdh-openflow-*"
        }
    ]
}
EOF
)

    # Attach policy
    aws iam put-role-policy \
        --role-name "$role_name" \
        --policy-name "KinesisOpenflowAccess" \
        --policy-document "$permissions_policy"

    IAM_ROLE_ARN=$(aws iam get-role --role-name "$role_name" --query 'Role.Arn' --output text)
    log_info "✓ IAM role created"
    log_info "  ARN: $IAM_ROLE_ARN"
}

create_iot_rule() {
    log_step "Creating IoT Core Rule"

    local rule_name="smdh_${TENANT_ID}_to_kinesis"
    local stream_name="smdh-${TENANT_ID}-stream"

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY RUN] Would create IoT rule: $rule_name"
        return 0
    fi

    # Check if rule exists
    if aws iot get-topic-rule --rule-name "$rule_name" --region "$AWS_REGION" &>/dev/null; then
        log_warn "IoT rule '$rule_name' already exists"
        return 0
    fi

    # Check for IoT-Kinesis role (should be created by Terraform)
    local iot_kinesis_role="smdh-iot-kinesis-role"
    if ! aws iam get-role --role-name "$iot_kinesis_role" &>/dev/null; then
        log_warn "IoT Kinesis role '$iot_kinesis_role' not found. Creating basic role..."

        # Create basic IoT role if it doesn't exist
        local iot_trust_policy=$(cat << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {"Service": "iot.amazonaws.com"},
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF
)
        aws iam create-role \
            --role-name "$iot_kinesis_role" \
            --assume-role-policy-document "$iot_trust_policy" \
            --description "Role for IoT Core to write to Kinesis streams" \
            --tags Key=Project,Value=SMDH Key=ManagedBy,Value=Script

        # Attach Kinesis write policy
        local iot_kinesis_policy=$(cat << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": ["kinesis:PutRecord", "kinesis:PutRecords"],
            "Resource": "arn:aws:kinesis:${AWS_REGION}:${AWS_ACCOUNT_ID}:stream/smdh-*"
        }
    ]
}
EOF
)
        aws iam put-role-policy \
            --role-name "$iot_kinesis_role" \
            --policy-name "KinesisWriteAccess" \
            --policy-document "$iot_kinesis_policy"

        # Wait for role to propagate
        sleep 10
    fi

    # Create IoT rule
    log_info "Creating IoT rule: $rule_name"
    local rule_payload=$(cat << EOF
{
    "sql": "SELECT *, topic(2) as tenant_id, topic(3) as entity_type, topic(4) as entity_id, timestamp() as iot_timestamp FROM 'smdh/${TENANT_ID}/+/+'",
    "description": "Route ${TENANT_ID} sensor data to dedicated Kinesis stream",
    "actions": [
        {
            "kinesis": {
                "streamName": "${stream_name}",
                "partitionKey": "\${topic(3)}_\${topic(4)}",
                "roleArn": "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${iot_kinesis_role}"
            }
        }
    ],
    "ruleDisabled": false,
    "awsIotSqlVersion": "2016-03-23"
}
EOF
)

    aws iot create-topic-rule \
        --rule-name "$rule_name" \
        --topic-rule-payload "$rule_payload" \
        --region "$AWS_REGION"

    log_info "✓ IoT rule created"
    log_info "  Topic pattern: smdh/${TENANT_ID}/+/+"
}

################################################################################
# Snowflake Functions
################################################################################

run_snowsql() {
    local sql="$1"
    snowsql -a "$SNOWFLAKE_ACCOUNT" -u "$SNOWFLAKE_USER" \
        -r "$SNOWFLAKE_ROLE" -w "SMDH_WH" \
        -o output_format=plain -o header=false -o timing=false \
        -q "$sql" 2>&1
}

run_snowsql_query() {
    local sql="$1"
    snowsql -a "$SNOWFLAKE_ACCOUNT" -u "$SNOWFLAKE_USER" \
        -r "$SNOWFLAKE_ROLE" -w "SMDH_WH" \
        -o output_format=tsv -o header=false -o timing=false \
        -q "$sql" 2>/dev/null | head -1
}

check_openflow_prerequisites() {
    log_step "Checking Openflow Prerequisites"

    local errors=0

    # Check for External Access Integration
    log_info "Checking for OPENFLOW_AWS_EAI integration..."
    local eai_check
    eai_check=$(run_snowsql_query "SELECT COUNT(*) FROM INFORMATION_SCHEMA.INTEGRATIONS WHERE INTEGRATION_NAME = 'OPENFLOW_AWS_EAI';" 2>/dev/null || echo "0")
    eai_check=$(echo "$eai_check" | head -1 | tr -d '[:space:]')

    if [[ "$eai_check" == "1" ]]; then
        log_info "✓ External Access Integration exists"
    else
        log_warn "✗ External Access Integration not found"
        log_info "  Creating OPENFLOW_AWS_EAI..."
        run_snowsql "
            USE ROLE ACCOUNTADMIN;
            CREATE OR REPLACE EXTERNAL ACCESS INTEGRATION OPENFLOW_AWS_EAI
                ALLOWED_NETWORK_RULES = (OPENFLOW.OPENFLOW.OPENFLOW_AWS_EU_WEST_2_RULE)
                ENABLED = TRUE
                COMMENT = 'External access integration for Openflow AWS connectivity';
        "
        log_info "✓ External Access Integration created"
    fi

    # Check for Openflow roles
    log_info "Checking for OPENFLOW_RUNTIME_ROLE_KINESIS role..."
    local role_check
    role_check=$(run_snowsql_query "SELECT COUNT(*) FROM INFORMATION_SCHEMA.APPLICABLE_ROLES WHERE ROLE_NAME = 'OPENFLOW_RUNTIME_ROLE_KINESIS';" 2>/dev/null || echo "0")
    role_check=$(echo "$role_check" | head -1 | tr -d '[:space:]')

    if [[ "$role_check" == "1" ]]; then
        log_info "✓ Openflow runtime role exists"
    else
        log_warn "✗ Openflow runtime role not found"
        log_info "  Run 03_openflow_connector.sql first to create required roles"
        errors=$((errors + 1))
    fi

    # Check for SMDH_WH warehouse
    log_info "Checking for SMDH_WH warehouse..."
    local wh_check
    wh_check=$(run_snowsql_query "SELECT COUNT(*) FROM INFORMATION_SCHEMA.WAREHOUSES WHERE WAREHOUSE_NAME = 'SMDH_WH';" 2>/dev/null || echo "0")
    wh_check=$(echo "$wh_check" | head -1 | tr -d '[:space:]')

    if [[ "$wh_check" == "1" ]]; then
        log_info "✓ SMDH_WH warehouse exists"
    else
        log_warn "✗ SMDH_WH warehouse not found"
        log_info "  Run 02_shared_resources.sql first to create warehouse"
        errors=$((errors + 1))
    fi

    if [[ $errors -gt 0 ]]; then
        log_error "Openflow prerequisites not met. Run core SQL scripts first:"
        echo "  cd infrastructure/snowflake/sql/core"
        echo "  snowsql -f 02_shared_resources.sql"
        echo "  snowsql -f 03_openflow_connector.sql"
        exit 1
    fi

    log_info "All Openflow prerequisites satisfied"
}

create_snowflake_tenant() {
    log_step "Creating Snowflake Tenant Database"

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY RUN] Would run Snowflake tenant onboarding scripts"
        return 0
    fi

    # Check if existing onboard script exists and run it
    local onboard_script="$SNOWFLAKE_DIR/scripts/onboard_tenant.sh"

    if [[ -f "$onboard_script" ]]; then
        log_info "Running Snowflake tenant onboarding script..."
        bash "$onboard_script" \
            --tenant-id "$TENANT_ID" \
            --tenant-name "$TENANT_NAME" \
            --num-sites "$NUM_SITES" \
            --snowflake-account "$SNOWFLAKE_ACCOUNT" \
            --snowflake-user "$SNOWFLAKE_USER"
    else
        log_warn "Onboard script not found. Running inline SQL..."

        # Create basic database and schemas
        run_snowsql "
            USE ROLE ACCOUNTADMIN;
            USE WAREHOUSE SMDH_WH;

            CREATE DATABASE IF NOT EXISTS SMDH_TENANT_$(to_upper $TENANT_ID)
                DATA_RETENTION_TIME_IN_DAYS = 7
                COMMENT = 'SMDH Tenant Database for ${TENANT_NAME}';

            USE DATABASE SMDH_TENANT_$(to_upper $TENANT_ID);

            CREATE SCHEMA IF NOT EXISTS RAW COMMENT = 'Raw sensor data ingestion';
            CREATE SCHEMA IF NOT EXISTS NORMALIZED COMMENT = 'Normalized data';
            CREATE SCHEMA IF NOT EXISTS AGGREGATED COMMENT = 'Aggregated metrics';
            CREATE SCHEMA IF NOT EXISTS ANALYTICS COMMENT = 'Analytics views';

            -- Create raw sensor readings table
            CREATE TABLE IF NOT EXISTS RAW.SENSOR_READINGS (
                reading_id VARCHAR(255) DEFAULT UUID_STRING(),
                tenant_id VARCHAR(100) NOT NULL,
                sensor_id VARCHAR(100) NOT NULL,
                site_id VARCHAR(100),
                device_id VARCHAR(100),
                timestamp TIMESTAMP_NTZ NOT NULL,
                ingestion_timestamp TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
                iot_timestamp TIMESTAMP_NTZ,
                payload VARIANT NOT NULL,
                source_system VARCHAR(50) DEFAULT 'kinesis',
                mqtt_topic VARCHAR(500),
                message_id VARCHAR(255),
                PRIMARY KEY (reading_id)
            )
            CLUSTER BY (tenant_id, DATE_TRUNC('day', timestamp))
            COMMENT = 'Raw sensor readings ingested from Kinesis via Openflow';
        "
    fi

    log_info "✓ Snowflake tenant database created"
}

grant_openflow_access() {
    log_step "Granting Openflow Access to Tenant Database"

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY RUN] Would grant Openflow access"
        return 0
    fi

    log_info "Calling sp_grant_openflow_tenant_access..."
    local result
    result=$(run_snowsql "CALL smdh_infrastructure.tenant_configs.sp_grant_openflow_tenant_access('${TENANT_ID}');")

    if echo "$result" | grep -q "Granted"; then
        log_info "✓ $result"
    else
        log_warn "Grant procedure returned: $result"
    fi
}

register_tenant_and_connector() {
    log_step "Registering Tenant and Connector"

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY RUN] Would register tenant in tracking tables"
        return 0
    fi

    local stream_name="smdh-${TENANT_ID}-stream"
    local database_name="SMDH_TENANT_$(to_upper $TENANT_ID)"

    # Update tenant with Kinesis details
    log_info "Updating tenant registry with Kinesis stream details..."
    run_snowsql "
        UPDATE smdh_infrastructure.tenant_configs.tenants
        SET
            kinesis_stream_name = '${stream_name}',
            status = 'active',
            activated_date = CURRENT_TIMESTAMP(),
            updated_date = CURRENT_TIMESTAMP()
        WHERE tenant_id = '${TENANT_ID}';
    "

    # Register Openflow connector
    log_info "Registering Openflow connector..."
    run_snowsql "
        INSERT INTO smdh_infrastructure.tenant_configs.openflow_connectors (
            tenant_id,
            connector_name,
            target_database,
            target_schema,
            target_table,
            kinesis_stream_name,
            kinesis_stream_arn,
            aws_region,
            runtime_name,
            status
        )
        SELECT
            '${TENANT_ID}',
            'kinesis-${TENANT_ID}',
            '${database_name}',
            'RAW',
            'SENSOR_READINGS',
            '${stream_name}',
            '${KINESIS_STREAM_ARN:-}',
            '${AWS_REGION}',
            'smdh-kinesis-runtime',
            'pending'
        WHERE NOT EXISTS (
            SELECT 1 FROM smdh_infrastructure.tenant_configs.openflow_connectors
            WHERE tenant_id = '${TENANT_ID}'
        );
    "

    log_info "✓ Tenant and connector registered"
}

################################################################################
# Main
################################################################################

print_banner() {
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║   SMDH Full Tenant Onboarding Automation                       ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_summary() {
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║   Tenant Onboarding Complete!                                  ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "Tenant Details:"
    echo "  • Tenant ID: $TENANT_ID"
    echo "  • Tenant Name: $TENANT_NAME"
    echo "  • AWS Region: $AWS_REGION"
    echo ""

    if [[ "${SKIP_AWS:-false}" != "true" ]]; then
        echo "AWS Resources Created:"
        echo "  ✓ Kinesis Stream: smdh-${TENANT_ID}-stream"
        echo "  ✓ IAM Role: smdh-openflow-${TENANT_ID}-role"
        echo "  ✓ IoT Rule: smdh_${TENANT_ID}_to_kinesis"
        echo "    Topic: smdh/${TENANT_ID}/+/+"
        echo ""
    fi

    if [[ "${SKIP_SNOWFLAKE:-false}" != "true" ]]; then
        echo "Snowflake Resources Created:"
        echo "  ✓ Database: SMDH_TENANT_$(to_upper $TENANT_ID)"
        echo "  ✓ Schemas: RAW, NORMALIZED, AGGREGATED, ANALYTICS"
        echo "  ✓ Openflow access granted"
        echo "  ✓ Connector registered (status: pending)"
        echo ""
    fi

    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}  REMAINING STEP: Add Kinesis Connector in Snowsight${NC}"
    echo -e "${YELLOW}  (This is the ONLY manual step - Snowflake limitation)${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "ONE-TIME SETUP (if not done already):"
    echo "  1. Snowsight → Data → Openflow → Create Deployment"
    echo "     Name: smdh-openflow-deployment"
    echo "  2. In deployment → Create Runtime"
    echo "     Name: smdh-kinesis-runtime"
    echo "     Role: OPENFLOW_RUNTIME_ROLE_KINESIS"
    echo "     Warehouse: SMDH_WH"
    echo "     External Access: OPENFLOW_AWS_EAI"
    echo ""
    echo "PER-TENANT CONNECTOR:"
    echo "  In 'smdh-kinesis-runtime' → Add Connector → Amazon Kinesis"
    echo ""
    echo "   ┌─────────────────────────────────────────────────────────────┐"
    echo "   │ SOURCE                                                      │"
    echo "   │   AWS Region:        ${AWS_REGION}"
    echo "   │   Stream Name:       smdh-${TENANT_ID}-stream"
    echo "   │   Application Name:  smdh-openflow-${TENANT_ID}"
    echo "   │   Initial Position:  LATEST"
    echo "   │   Message Format:    JSON"
    echo "   ├─────────────────────────────────────────────────────────────┤"
    echo "   │ DESTINATION                                                 │"
    echo "   │   Database:          SMDH_TENANT_$(to_upper $TENANT_ID)"
    echo "   │   Schema:            RAW"
    echo "   │   Role:              OPENFLOW_RUNTIME_ROLE_KINESIS"
    echo "   │   Warehouse:         SMDH_WH"
    echo "   ├─────────────────────────────────────────────────────────────┤"
    echo "   │ MAPPING                                                     │"
    echo "   │   smdh-${TENANT_ID}-stream → SENSOR_READINGS                │"
    echo "   └─────────────────────────────────────────────────────────────┘"
    echo ""
    echo "Click Create → Start"
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  TEST DATA FLOW${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "Send test message:"
    echo "  aws iot-data publish \\"
    echo "    --topic \"smdh/${TENANT_ID}/site_001/sensor\" \\"
    echo "    --payload '{\"sensor_id\":\"TEMP_001\",\"value\":25.5,\"unit\":\"celsius\",\"timestamp\":\"'\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"'\"}' \\"
    echo "    --region ${AWS_REGION}"
    echo ""
    echo "Verify in Snowflake:"
    echo "  SELECT * FROM SMDH_TENANT_$(to_upper $TENANT_ID).RAW.SENSOR_READINGS ORDER BY ingestion_timestamp DESC LIMIT 5;"
    echo ""
}

main() {
    parse_args "$@"
    print_banner
    validate_inputs

    echo "Configuration:"
    echo "  Tenant ID:    $TENANT_ID"
    echo "  Tenant Name:  $TENANT_NAME"
    echo "  Num Sites:    $NUM_SITES"
    echo "  AWS Region:   $AWS_REGION"
    echo "  Skip AWS:     ${SKIP_AWS:-false}"
    echo "  Skip SF:      ${SKIP_SNOWFLAKE:-false}"
    echo "  Dry Run:      ${DRY_RUN:-false}"

    check_prerequisites

    # AWS Resources
    if [[ "${SKIP_AWS:-false}" != "true" ]]; then
        create_kinesis_stream
        create_iam_role
        create_iot_rule
    fi

    # Snowflake Resources
    if [[ "${SKIP_SNOWFLAKE:-false}" != "true" ]]; then
        check_openflow_prerequisites
        create_snowflake_tenant
        grant_openflow_access
        register_tenant_and_connector
    fi

    print_summary
}

main "$@"
