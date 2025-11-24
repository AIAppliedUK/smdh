#!/bin/bash

################################################################################
# SMDH Snowflake-Kinesis Integration Setup Script
#
# Purpose: Establish bidirectional connection between AWS IoT → Kinesis → Snowflake
#
# Usage:
#   ./setup_kinesis_integration.sh dev
#   ./setup_kinesis_integration.sh prod
#   ./setup_kinesis_integration.sh staging
#
# Prerequisites:
#   - AWS CLI configured with appropriate credentials
#   - SnowSQL installed and configured
#   - SNOWSQL_PWD environment variable set with Snowflake password
#   - Permissions to modify AWS IAM roles and Snowflake integrations
#
################################################################################

set -euo pipefail

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
ENVIRONMENT="${1:-dev}"
AWS_ACCOUNT_ID="471112943820"
AWS_REGION="eu-west-2"
SNOWFLAKE_ACCOUNT="qqoylnv-zy42691"
SNOWFLAKE_USER="AIAPPLIED"
KINESIS_STREAM_NAME="smdh-sensor-data-stream"

# Environment-specific configurations
case "$ENVIRONMENT" in
  dev|development)
    ENVIRONMENT="dev"
    AWS_ROLE_NAME="smdh-snowflake-kinesis-role-dev"
    SNOWFLAKE_DATABASE="SMDH_TENANT_TEST_TENANT"
    SNOWFLAKE_WAREHOUSE="COMPUTE_WH"
    INTEGRATION_NAME="smdh_kinesis_integration_dev"
    PIPE_NAME="kinesis_to_sensor_readings_dev"
    ;;
  prod|production)
    ENVIRONMENT="prod"
    AWS_ROLE_NAME="smdh-snowflake-kinesis-role-prod"
    SNOWFLAKE_DATABASE="SMDH_TENANT_PRODUCTION"
    SNOWFLAKE_WAREHOUSE="ANALYTICS_WH"
    INTEGRATION_NAME="smdh_kinesis_integration_prod"
    PIPE_NAME="kinesis_to_sensor_readings_prod"
    ;;
  staging)
    ENVIRONMENT="staging"
    AWS_ROLE_NAME="smdh-snowflake-kinesis-role-staging"
    SNOWFLAKE_DATABASE="SMDH_TENANT_STAGING"
    SNOWFLAKE_WAREHOUSE="STAGING_WH"
    INTEGRATION_NAME="smdh_kinesis_integration_staging"
    PIPE_NAME="kinesis_to_sensor_readings_staging"
    ;;
  *)
    echo -e "${RED}Error: Unknown environment '$ENVIRONMENT'${NC}"
    echo "Valid environments: dev, prod, staging"
    exit 1
    ;;
esac

# Verify prerequisites
check_prerequisites() {
  echo -e "${BLUE}Checking prerequisites...${NC}"

  if ! command -v aws &> /dev/null; then
    echo -e "${RED}✗ AWS CLI not found${NC}"
    exit 1
  fi

  if ! command -v snowsql &> /dev/null; then
    echo -e "${RED}✗ SnowSQL not found${NC}"
    exit 1
  fi

  if [ -z "${SNOWSQL_PWD:-}" ]; then
    echo -e "${RED}✗ SNOWSQL_PWD environment variable not set${NC}"
    exit 1
  fi

  echo -e "${GREEN}✓ All prerequisites met${NC}"
}

# Step 1: Create Snowflake Storage Integration
create_snowflake_integration() {
  echo ""
  echo -e "${BLUE}Step 1: Creating Snowflake Storage Integration...${NC}"

  export SNOWSQL_PWD

  # Create the integration
  snowsql -a "$SNOWFLAKE_ACCOUNT" -u "$SNOWFLAKE_USER" -r ACCOUNTADMIN << EOF
USE DATABASE $SNOWFLAKE_DATABASE;
USE WAREHOUSE $SNOWFLAKE_WAREHOUSE;

CREATE OR REPLACE STORAGE INTEGRATION $INTEGRATION_NAME
  TYPE = EXTERNAL_STAGE
  STORAGE_PROVIDER = S3
  ENABLED = TRUE
  STORAGE_AWS_ROLE_ARN = 'arn:aws:iam::${AWS_ACCOUNT_ID}:role/${AWS_ROLE_NAME}'
  STORAGE_ALLOWED_LOCATIONS = ('s3://smdh-kinesis-data/', 's3://smdh-kinesis-staging/')
  COMMENT = 'Integration for Kinesis to Snowflake data flow ($ENVIRONMENT environment)';

DESC STORAGE INTEGRATION $INTEGRATION_NAME;
EOF

  echo -e "${GREEN}✓ Storage integration created${NC}"
}

# Step 2: Get Snowflake IAM User details
get_snowflake_iam_details() {
  echo ""
  echo -e "${BLUE}Step 2: Retrieving Snowflake IAM details...${NC}"

  # Get integration details using SQL query
  cat > /tmp/get_integration_details.sql << EOF
USE DATABASE $SNOWFLAKE_DATABASE;
DESC STORAGE INTEGRATION $INTEGRATION_NAME;
EOF

  INTEGRATION_DETAILS=$(snowsql -a "$SNOWFLAKE_ACCOUNT" -u "$SNOWFLAKE_USER" -r ACCOUNTADMIN -f /tmp/get_integration_details.sql 2>&1)

  # Extract IAM User ARN and External ID - parse the tabular output
  # The values come after the property name column in the DESC output
  SNOWFLAKE_IAM_USER_ARN=$(echo "$INTEGRATION_DETAILS" | grep "STORAGE_AWS_IAM_USER_ARN" | sed 's/.*STORAGE_AWS_IAM_USER_ARN *| *String *| *\([^ ]*\) .*/\1/')
  SNOWFLAKE_EXTERNAL_ID=$(echo "$INTEGRATION_DETAILS" | grep "STORAGE_AWS_EXTERNAL_ID" | sed 's/.*STORAGE_AWS_EXTERNAL_ID *| *String *| *\([^ ]*\) .*/\1/')

  if [ -z "$SNOWFLAKE_IAM_USER_ARN" ] || [ -z "$SNOWFLAKE_EXTERNAL_ID" ]; then
    echo -e "${YELLOW}⚠ Could not automatically extract IAM details. You may need to set them manually.${NC}"
    echo ""
    echo "Run this command in Snowflake to get details:"
    echo "  USE DATABASE $SNOWFLAKE_DATABASE;"
    echo "  DESC STORAGE INTEGRATION $INTEGRATION_NAME;"
    echo ""
    echo "Then look for these properties:"
    echo "  - STORAGE_AWS_IAM_USER_ARN (e.g., arn:aws:iam::123456789012:user/...)"
    echo "  - STORAGE_AWS_EXTERNAL_ID (e.g., ABCD1234...)"
    echo ""
    echo "Full DESC output for reference:"
    echo "$INTEGRATION_DETAILS"
    return 1
  fi

  echo -e "${GREEN}✓ Retrieved Snowflake IAM details:${NC}"
  echo "  IAM User ARN: $SNOWFLAKE_IAM_USER_ARN"
  echo "  External ID: $SNOWFLAKE_EXTERNAL_ID"

  # Save for later use
  echo "$SNOWFLAKE_IAM_USER_ARN" > /tmp/snowflake_iam_user_arn.txt
  echo "$SNOWFLAKE_EXTERNAL_ID" > /tmp/snowflake_external_id.txt
}

# Step 3: Update AWS IAM Role Trust Policy
update_aws_trust_policy() {
  echo ""
  echo -e "${BLUE}Step 3: Updating AWS IAM Role Trust Policy...${NC}"

  SNOWFLAKE_IAM_USER_ARN=$(cat /tmp/snowflake_iam_user_arn.txt)
  SNOWFLAKE_EXTERNAL_ID=$(cat /tmp/snowflake_external_id.txt)

  # Create trust policy document
  TRUST_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "$SNOWFLAKE_IAM_USER_ARN"
      },
      "Action": "sts:AssumeRole",
      "Condition": {
        "StringEquals": {
          "sts:ExternalId": "$SNOWFLAKE_EXTERNAL_ID"
        }
      }
    }
  ]
}
EOF
)

  # Save trust policy to file
  echo "$TRUST_POLICY" > /tmp/trust_policy_${ENVIRONMENT}.json

  # Update the role
  aws iam update-assume-role-policy \
    --role-name "$AWS_ROLE_NAME" \
    --policy-document file:///tmp/trust_policy_${ENVIRONMENT}.json

  echo -e "${GREEN}✓ AWS IAM role trust policy updated${NC}"
}

# Step 4: Create Snowflake Pipe for Data Ingestion
create_snowflake_pipe() {
  echo ""
  echo -e "${BLUE}Step 4: Creating Snowflake Pipe for Data Ingestion...${NC}"

  snowsql -a "$SNOWFLAKE_ACCOUNT" -u "$SNOWFLAKE_USER" -r ACCOUNTADMIN << EOF
USE DATABASE $SNOWFLAKE_DATABASE;
USE WAREHOUSE $SNOWFLAKE_WAREHOUSE;

-- Create the pipe to ingest from Kinesis
CREATE PIPE IF NOT EXISTS raw.$PIPE_NAME
  AUTO_INGEST = TRUE
  AS
  COPY INTO raw.clamp_sensor_readings (
    reading_id, tenant_id, machine_id, sensor_id, timestamp,
    current_phase_a, current_phase_b, current_phase_c, current_rms,
    voltage_phase_a, voltage_phase_b, voltage_phase_c,
    power_factor, frequency, raw_payload
  )
  FROM '@$INTEGRATION_NAME/$KINESIS_STREAM_NAME'
  FILE_FORMAT = (TYPE = 'JSON', COMPRESSION = 'AUTO')
  ON_ERROR = 'CONTINUE';

-- Show pipe status
SHOW PIPES IN raw;
EOF

  echo -e "${GREEN}✓ Snowflake pipe created${NC}"
}

# Step 5: Verify Kinesis Stream Access
verify_kinesis_access() {
  echo ""
  echo -e "${BLUE}Step 5: Verifying Kinesis Stream Access...${NC}"

  # Check if stream exists
  STREAM_INFO=$(aws kinesis describe-stream \
    --stream-name "$KINESIS_STREAM_NAME" \
    --region "$AWS_REGION" 2>&1)

  if [ $? -eq 0 ]; then
    STREAM_STATUS=$(echo "$STREAM_INFO" | jq -r '.StreamDescription.StreamStatus')
    SHARD_COUNT=$(echo "$STREAM_INFO" | jq '.StreamDescription.Shards | length')

    echo -e "${GREEN}✓ Kinesis stream accessible${NC}"
    echo "  Stream: $KINESIS_STREAM_NAME"
    echo "  Status: $STREAM_STATUS"
    echo "  Shards: $SHARD_COUNT"
  else
    echo -e "${RED}✗ Could not access Kinesis stream${NC}"
    echo "Ensure the stream exists and your AWS credentials have access"
    return 1
  fi
}

# Step 6: Test Connection
test_connection() {
  echo ""
  echo -e "${BLUE}Step 6: Testing Connection...${NC}"

  # Test Snowflake connectivity
  snowsql -a "$SNOWFLAKE_ACCOUNT" -u "$SNOWFLAKE_USER" -r ACCOUNTADMIN << EOF
USE DATABASE $SNOWFLAKE_DATABASE;
SELECT CURRENT_TIMESTAMP() AS connection_test;
EOF

  echo -e "${GREEN}✓ Connection test successful${NC}"
}

# Step 7: Display Summary
display_summary() {
  echo ""
  echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${BLUE}║   Integration Setup Complete - $ENVIRONMENT Environment         ║${NC}"
  echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
  echo ""
  echo "Configuration Summary:"
  echo "  Environment:         $ENVIRONMENT"
  echo "  AWS Account:         $AWS_ACCOUNT_ID"
  echo "  AWS Region:          $AWS_REGION"
  echo "  IAM Role:            $AWS_ROLE_NAME"
  echo "  Snowflake Account:   $SNOWFLAKE_ACCOUNT"
  echo "  Snowflake Database:  $SNOWFLAKE_DATABASE"
  echo "  Snowflake Warehouse: $SNOWFLAKE_WAREHOUSE"
  echo "  Integration Name:    $INTEGRATION_NAME"
  echo "  Pipe Name:           raw.$PIPE_NAME"
  echo "  Kinesis Stream:      $KINESIS_STREAM_NAME"
  echo ""
  echo "Data Flow:"
  echo "  AWS IoT Core → Kinesis Stream → Snowflake Pipe → $SNOWFLAKE_DATABASE.raw.clamp_sensor_readings"
  echo ""
  echo "Next Steps:"
  echo "  1. Verify data is flowing from IoT Core to Kinesis"
  echo "  2. Monitor pipe status: SHOW PIPES IN raw;"
  echo "  3. Check ingestion progress: SELECT COUNT(*) FROM raw.clamp_sensor_readings;"
  echo ""
  echo "Useful Commands:"
  echo "  # Check pipe status"
  echo "  snowsql -a $SNOWFLAKE_ACCOUNT -u $SNOWFLAKE_USER << 'SQL'"
  echo "  USE DATABASE $SNOWFLAKE_DATABASE;"
  echo "  SHOW PIPES IN raw;"
  echo "  SELECT SYSTEM\$PIPE_STATUS('raw.$PIPE_NAME');"
  echo "  SQL"
  echo ""
  echo "  # Monitor data ingestion"
  echo "  snowsql -a $SNOWFLAKE_ACCOUNT -u $SNOWFLAKE_USER << 'SQL'"
  echo "  USE DATABASE $SNOWFLAKE_DATABASE;"
  echo "  SELECT COUNT(*) as record_count FROM raw.clamp_sensor_readings;"
  echo "  SQL"
  echo ""
}

# Step 8: Cleanup temporary files
cleanup() {
  rm -f /tmp/trust_policy_${ENVIRONMENT}.json
  rm -f /tmp/snowflake_iam_user_arn.txt
  rm -f /tmp/snowflake_external_id.txt
}

# Main execution
main() {
  echo -e "${YELLOW}╔════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${YELLOW}║   SMDH Snowflake-Kinesis Integration Setup ($ENVIRONMENT)         ║${NC}"
  echo -e "${YELLOW}╚════════════════════════════════════════════════════════════╝${NC}"
  echo ""

  check_prerequisites

  # Ask for confirmation
  echo ""
  echo -e "${YELLOW}⚠  This will modify AWS IAM roles and create Snowflake integrations.${NC}"
  echo -e "${YELLOW}⚠  Environment: $ENVIRONMENT${NC}"
  read -p "Continue? (y/n) " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Setup cancelled"
    exit 0
  fi

  # Run setup steps
  create_snowflake_integration
  get_snowflake_iam_details || exit 1
  update_aws_trust_policy
  create_snowflake_pipe
  verify_kinesis_access
  test_connection
  display_summary
  cleanup

  echo -e "${GREEN}✓ Setup completed successfully!${NC}"
}

# Run main function
main "$@"
