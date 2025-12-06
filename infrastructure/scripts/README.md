# SMDH Infrastructure Scripts

This directory contains operational scripts for managing and monitoring the SMDH platform.

---

## Complete Environment Setup Guide

This guide walks through setting up the SMDH platform from scratch.

### Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           SMDH DATA FLOW                                    │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  IoT Devices ──MQTT──► AWS IoT Core ──IoT Rule──► Kinesis ──Openflow──► Snowflake
│                                                                             │
│  Per Tenant:                                                                │
│  ┌─────────┐     ┌──────────────┐     ┌──────────────────┐    ┌──────────┐ │
│  │Gateway/ │     │smdh/{tenant}/│     │smdh-{tenant}-    │    │SMDH_     │ │
│  │ChirpSt. │────►│+/sensor-data │────►│stream            │───►│TENANT_X  │ │
│  └─────────┘     └──────────────┘     └──────────────────┘    └──────────┘ │
│                       MQTT Topic        Per-Tenant Stream     Per-Tenant DB│
└─────────────────────────────────────────────────────────────────────────────┘

IMPORTANT: Per-tenant Kinesis streams are REQUIRED.
Snowflake Openflow cannot filter records from a shared stream.
```

### PrerequisitesScotgovRock

Before starting, ensure you have:

1. **AWS CLI** configured with appropriate permissions

   ```bash
   aws sts get-caller-identity  # Verify AWS access
   ```

2. **Terraform** v1.0+ installed

   ```bash
   terraform version
   ```

3. **SnowSQL** installed and configured

   ```bash
   snowsql --version
   ```

4. **Snowflake credentials** (ACCOUNTADMIN role required for initial setup)
   ```bash
   export SNOWSQL_PWD='your-password'
   # OR configure key-pair auth in ~/.snowsql/config
   ```

---

### Phase 1: Core Snowflake Setup (One-Time)

Run these SQL scripts in order to set up the Snowflake foundation.

```bash
cd infrastructure/snowflake/sql/core

# 1. Prerequisites check
snowsql -a <account> -u <user> -f 00_prerequisites.sql

# 2. Create infrastructure database and tenant registry
snowsql -a <account> -u <user> -f 01_infrastructure_setup.sql

# 3. Create shared warehouse and roles
snowsql -a <account> -u <user> -f 02_shared_resources.sql

# 4. Configure Openflow (network rules, roles, integrations)
snowsql -a <account> -u <user> -f 03_openflow_connector.sql
```

**What gets created:**
| Script | Creates |
|--------|---------|
| `00_prerequisites.sql` | Validates account, region, permissions |
| `01_infrastructure_setup.sql` | `smdh_infrastructure` database, tenant registry tables |
| `02_shared_resources.sql` | `SMDH_WH` warehouse, operator/engineer/analytics roles |
| `03_openflow_connector.sql` | `OPENFLOW_ADMIN`, `OPENFLOW_RUNTIME_ROLE_KINESIS`, network rules |

**Manual Step Required (Snowsight UI):**

After running `03_openflow_connector.sql`, create the Openflow Deployment and Runtime:

1. Open **Snowsight** → **Data** → **Openflow**
2. Click **Create Deployment** → Name: `smdh-openflow-deployment`
3. In the deployment, click **Create Runtime**:
   - Name: `smdh-kinesis-runtime`
   - Role: `OPENFLOW_RUNTIME_ROLE_KINESIS`
   - Warehouse: `SMDH_WH`
   - External Access: `OPENFLOW_AWS_EAI`

---

### Phase 2: Core AWS Setup (Terraform)

Deploy the core AWS infrastructure using Terraform.

```bash
cd infrastructure/terraform

# 1. Initialize Terraform
terraform init

# 2. Review what will be created
terraform plan -var-file=environments/dev/terraform.tfvars

# 3. Apply the configuration
terraform apply -var-file=environments/dev/terraform.tfvars
```

**What gets created:**
| Module | Resources |
|--------|-----------|
| `iot-core` | Thing types, IoT logging, Kinesis write role |
| `iam` | Snowflake cross-account role for Openflow |
| `secrets-manager` | Snowflake credentials storage |
| `cloudwatch` | Log groups, dashboards, alarms |
| `tenant` (per tenant) | **Per-tenant Kinesis stream**, IoT things, certificates, policies, rules |

**Key Outputs:**

```bash
# Get IoT endpoint for device configuration
terraform output iot_endpoint

# Get Snowflake IAM role ARN (needed for Openflow)
terraform output -raw snowflake_iam_role_arn

# Get per-tenant Kinesis stream info
terraform output tenant_kinesis_streams
```

---

### Phase 3: Tenant Onboarding

#### Option A: Terraform-Managed Tenants (Recommended)

Add tenants to `environments/dev/terraform.tfvars`:

```hcl
tenants = {
  acme_corp = {
    name          = "ACME Corporation"
    num_sites     = 3
    contact_email = "ops@acme.com"
  }
  globex = {
    name          = "Globex Industries"
    num_sites     = 5
    contact_email = "iot@globex.com"
  }
}
```

Then apply:

```bash
terraform apply -var-file=environments/dev/terraform.tfvars
```

After Terraform creates AWS resources, run Snowflake tenant setup:

```bash
cd ../snowflake/scripts
./onboard_tenant.sh \
  --tenant-id acme_corp \
  --tenant-name "ACME Corporation" \
  --num-sites 3 \
  --snowflake-account <account> \
  --snowflake-user <user>
```

#### Option B: Full Script-Based Onboarding

Use for tenants managed outside Terraform:

```bash
cd infrastructure/scripts
./onboard_tenant_full.sh \
  --tenant-id acme_corp \
  --tenant-name "ACME Corporation" \
  --num-sites 3 \
  --contact-email ops@acme.com
```

This creates both AWS and Snowflake resources in one command.

---

### Phase 4: Connect Openflow to Tenant Stream

**For EACH tenant**, add a Kinesis connector in Snowsight:

1. Open **Snowsight** → **Data** → **Openflow**
2. Select `smdh-openflow-deployment` → `smdh-kinesis-runtime`
3. Click **Add Connector** → **Amazon Kinesis**
4. Configure:

   | Field            | Value                                         |
   | ---------------- | --------------------------------------------- |
   | **SOURCE**       |                                               |
   | AWS Region       | `eu-west-2`                                   |
   | Stream Name      | `smdh-{tenant_id}-stream`                     |
   | Application Name | `smdh-openflow-{tenant_id}`                   |
   | Initial Position | `LATEST`                                      |
   | Message Format   | `JSON`                                        |
   | **DESTINATION**  |                                               |
   | Database         | `SMDH_TENANT_{TENANT_ID}`                     |
   | Schema           | `RAW`                                         |
   | Role             | `OPENFLOW_RUNTIME_ROLE_KINESIS`               |
   | Warehouse        | `SMDH_WH`                                     |
   | **MAPPING**      |                                               |
   | Stream → Table   | `smdh-{tenant_id}-stream` → `SENSOR_READINGS` |

5. Click **Create** → **Start**

---

### Phase 5: Test Data Flow

#### 1. Send Test MQTT Message

```bash
# Replace {tenant_id} with your tenant
aws iot-data publish \
  --topic "smdh/{tenant_id}/site_001/sensor-data" \
  --payload '{"sensor_id":"TEMP_001","value":25.5,"unit":"celsius","timestamp":"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}' \
  --region eu-west-2
```

#### 2. Verify Kinesis Receipt

```bash
# Check stream has data
aws kinesis describe-stream-summary \
  --stream-name smdh-{tenant_id}-stream \
  --region eu-west-2
```

#### 3. Verify Snowflake Ingestion

```sql
-- Check raw data arrived
USE DATABASE SMDH_TENANT_{TENANT_ID};
SELECT * FROM RAW.SENSOR_READINGS
ORDER BY ingestion_timestamp DESC
LIMIT 5;

-- Check Openflow connector status
SELECT * FROM smdh_infrastructure.monitoring.v_openflow_connector_status
WHERE tenant_id = '{tenant_id}';
```

---

### Quick Reference Commands

```bash
# Check Terraform state
cd infrastructure/terraform
terraform state list | grep tenant

# View tenant Kinesis streams
terraform output tenant_kinesis_streams

# Check IoT rules
aws iot list-topic-rules --region eu-west-2

# Get IoT rule details
aws iot get-topic-rule --rule-name smdh_route_{tenant_id} --region eu-west-2

# Check Kinesis stream status
aws kinesis describe-stream-summary --stream-name smdh-{tenant_id}-stream --region eu-west-2

# Snowflake health check
snowsql -q "CALL smdh_tenant_{tenant_id}.analytics.sp_health_check();"
```

---

## Available Scripts

### 0. Full Tenant Onboarding (`onboard_tenant_full.sh`)

Complete end-to-end tenant provisioning for AWS and Snowflake.

**Features:**

- Creates AWS Kinesis stream per tenant
- Creates AWS IAM role for Openflow access
- Creates AWS IoT Rule for MQTT → Kinesis routing
- Creates Snowflake tenant database and schemas
- Grants Openflow access to tenant database
- Registers connector in tracking table

**Usage:**

```bash
# Full onboarding (AWS + Snowflake)
./onboard_tenant_full.sh \
  --tenant-id acme_corp \
  --tenant-name "ACME Corporation" \
  --num-sites 5 \
  --contact-email ops@acme.com

# Dry run (see what would happen)
./onboard_tenant_full.sh \
  --tenant-id acme_corp \
  --tenant-name "ACME Corporation" \
  --num-sites 5 \
  --dry-run

# Skip AWS (Snowflake only)
./onboard_tenant_full.sh --tenant-id acme_corp --tenant-name "ACME" --num-sites 2 --skip-aws

# Skip Snowflake (AWS only)
./onboard_tenant_full.sh --tenant-id acme_corp --tenant-name "ACME" --num-sites 2 --skip-snowflake
```

**Post-Script Manual Step (Snowsight UI):**

After running the script, you must add the Kinesis connector in Snowsight:

1. Open **Snowsight** → **Ingestion** → **Openflow** → **Runtimes**
2. Click on `smdh-kinesis-runtime`
3. Click **Add Connector** → **Amazon Kinesis**
4. Configure with values shown in script output
5. Click **Create** → **Start**

> **Note:** This manual step is required due to a Snowflake platform limitation - Openflow connectors cannot be created via SQL.

**Prerequisites:**

- AWS CLI configured with appropriate permissions
- SnowSQL configured with key-pair or password authentication
- Openflow deployment and runtime already created (one-time setup)

---

### 1. System Health Check (`check_system_health.sh`)

Comprehensive health monitoring using AWS IoT Thing Groups.

Features:

- Thing group status overview
- Site-level device connectivity checks
- Disconnected device alerts (dynamic groups)
- MQTT message rate monitoring
- Kinesis stream health
- Certificate expiry warnings
- CloudWatch alarm status
- Overall health score

Usage:

```bash
 Check all sites for a tenant
./check_system_health.sh --tenant-id company_a

 Check specific site
./check_system_health.sh --tenant-id company_a --site-id site_

 Verbose output with device-level details
./check_system_health.sh --tenant-id company_a --verbose

 Different AWS region
./check_system_health.sh --tenant-id company_a --region eu-west-
```

Exit Codes:

- ``: Healthy (≥% health score)
- ``: Degraded (-% health score)
- ``: Critical (<% health score)

Example Output:

```
========================================
SMDH System Health Check
========================================
Tenant: company_a
Region: eu-west-
Site: ALL (tenant-wide check)

========================================
. Thing Group Overview
========================================
[INFO] Tenant thing group found: smdh-tenant-company_a
  Total devices in tenant:

========================================
. Site-Level Device Status
========================================

Site Group: smdh-company_a-site_
----------------------------------------
  Total devices:
  Status Summary:
    Connected:     devices
    Disconnected:  devices
    Site Health:  %

========================================
Health Check Summary
========================================
Overall Health Score: % (/ checks passed)
System Status: HEALTHY
```

Automation:

```bash
 Add to cron for hourly checks
     /path/to/check_system_health.sh --tenant-id company_a >> /var/log/smdh_health.log

 Alert on failures
./check_system_health.sh --tenant-id company_a || \
  aws sns publish --topic-arn $ALERT_TOPIC --message "Health check failed"
```

---

. IoT Cost Tracking (`check_iot_costs.sh`)

Cost analysis and reporting using AWS IoT Billing Groups.

Features:

- Per-tenant cost breakdown
- Message, connection, and rule execution costs
- Daily and monthly projections
- Platform-wide cost summary
- Cost optimization recommendations
- CSV export for reporting
- Kinesis cost estimates

Usage:

```bash
 Check all tenants (last  days)
./check_iot_costs.sh

 Specific tenant with custom period
./check_iot_costs.sh --tenant-id company_a --period

 Export to CSV for reporting
./check_iot_costs.sh --tenant-id company_a --export-csv costs_report.csv

 JSON output for automation
./check_iot_costs.sh --format json
```

Example Output:

```
========================================
SMDH IoT Cost Tracking
========================================
Region: eu-west-
Period: -- to -- ( days)
Tenant: company_a (specific tenant)

========================================
IoT Cost Breakdown by Tenant
========================================

Tenant: company_a
Billing Group: smdh-billing-company_a
----------------------------------------
  Devices in billing group:
  Messages published: ,,
  Message cost: $.
  Connection minutes (estimated): ,
  Connection cost: $.
  Rule executions: ,,
  Rule cost: $.

  Total estimated cost: $.
  Daily average: $.
  Monthly projection: $.

========================================
Cost Optimization Recommendations
========================================
[INFO] General Recommendations:
  • Use QoS  instead of QoS  when delivery guarantees aren't critical
  • Implement message compression for large payloads
  • Use device shadows instead of frequent polling
  • Batch multiple sensor readings into single MQTT messages
```

Monthly Cost Reports:

```bash
 Generate monthly reports for all tenants
for tenant in company_a company_b company_c; do
  ./check_iot_costs.sh \
    --tenant-id $tenant \
    --period  \
    --export-csv "reports/${tenant}_$(date +%Y%m).csv"
done
```

---

Prerequisites

AWS CLI Configuration

Ensure AWS CLI is configured with appropriate credentials:

```bash
aws configure
 Enter Access Key ID, Secret Access Key, Region (eu-west-)

 Verify configuration
aws sts get-caller-identity
```

Required AWS Permissions

The scripts require these IAM permissions:

```json
{
  "Version": "--",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "iot:DescribeThingGroup",
        "iot:ListThingGroups",
        "iot:ListThingsInThingGroup",
        "iot:ListBillingGroups",
        "iot:ListThingsInBillingGroup",
        "iot:DescribeThing",
        "iot:ListThingPrincipals",
        "iot:DescribeCertificate",
        "iot:SearchIndex",
        "kinesis:DescribeStream",
        "cloudwatch:GetMetricStatistics",
        "cloudwatch:DescribeAlarms"
      ],
      "Resource": ""
    }
  ]
}
```

Environment Variables

Optional environment variables:

```bash
export AWS_REGION=eu-west-
export AWS_PROFILE=smdh-admin

 Run scripts with custom AWS profile
AWS_PROFILE=smdh-prod ./check_system_health.sh --tenant-id company_a
```

---

Integration Examples

CI/CD Pipeline Health Checks

```yaml
 .github/workflows/health-check.yml
name: Platform Health Check

on:
  schedule:
    - cron: ' /   '   Every  hours

jobs:
  health-check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v
      - name: Configure AWS
        uses: aws-actions/configure-aws-credentials@v
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: eu-west-
      - name: Run Health Check
        run: |
          ./infrastructure/scripts/check_system_health.sh \
            --tenant-id company_a || exit
```

Slack Notifications

```bash
!/bin/bash
 health-check-with-slack.sh

TENANT_ID="company_a"
SLACK_WEBHOOK="https://hooks.slack.com/services/YOUR/WEBHOOK/URL"

 Run health check
OUTPUT=$(./check_system_health.sh --tenant-id $TENANT_ID >&)
EXIT_CODE=$?

 Extract health score
HEALTH_SCORE=$(echo "$OUTPUT" | grep "Overall Health Score" | awk '{print $}')

 Send to Slack if degraded or critical
if [ $EXIT_CODE -ne  ]; then
  curl -X POST $SLACK_WEBHOOK -H 'Content-Type: application/json' -d "{
    \"text\": \" SMDH Health Alert for ${TENANT_ID}\",
    \"attachments\": [{
      \"color\": \"danger\",
      \"fields\": [{
        \"title\": \"Health Score\",
        \"value\": \"${HEALTH_SCORE}\",
        \"short\": true
      }],
      \"text\": \"\`\`\`${OUTPUT}\`\`\`\"
    }]
  }"
fi
```

CloudWatch Events

```bash
!/bin/bash
 Publish health metrics to CloudWatch

TENANT_ID="company_a"

 Run health check and capture output
OUTPUT=$(./check_system_health.sh --tenant-id $TENANT_ID >&)
EXIT_CODE=$?

 Extract metrics
HEALTH_SCORE=$(echo "$OUTPUT" | grep "Overall Health Score" | awk '{print $}' | tr -d '%')

 Publish to CloudWatch
aws cloudwatch put-metric-data \
  --namespace SMDH/Health \
  --metric-name HealthScore \
  --dimensions TenantId=$TENANT_ID \
  --value $HEALTH_SCORE \
  --unit Percent
```

Cost Budget Alerts

```bash
!/bin/bash
 alert-on-cost-threshold.sh

TENANT_ID="company_a"
THRESHOLD=.   Alert if monthly projection exceeds $

 Get cost projection
OUTPUT=$(./check_iot_costs.sh --tenant-id $TENANT_ID --period )
MONTHLY_PROJECTION=$(echo "$OUTPUT" | grep "Monthly projection" | awk '{print $}' | tr -d '$')

 Compare with threshold
if (( $(echo "$MONTHLY_PROJECTION > $THRESHOLD" | bc -l) )); then
  echo "ALERT: ${TENANT_ID} projected monthly cost (\$${MONTHLY_PROJECTION}) exceeds threshold (\$${THRESHOLD})"

   Send alert (SNS, email, Slack, etc.)
  aws sns publish \
    --topic-arn arn:aws:sns:eu-west-::smdh-cost-alerts \
    --subject "Cost Alert: ${TENANT_ID}" \
    --message "Projected monthly cost: \$${MONTHLY_PROJECTION}"
fi
```

---

Troubleshooting

Script Permission Denied

```bash
chmod +x infrastructure/scripts/.sh
```

AWS CLI Not Found

```bash
 Install AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x_.zip" -o "awscliv.zip"
unzip awscliv.zip
sudo ./aws/install
```

Thing Group Not Found

Ensure Terraform has been applied:

```bash
cd infrastructure/terraform
terraform plan
terraform apply
```

No Metrics Data

CloudWatch metrics may have a delay. Try:
. Increase the period: `--period ` instead of `--period `
. Check if devices are actually sending data
. Verify IoT Rules are enabled

Permission Denied Errors

Ensure your AWS IAM user/role has the required permissions (see Prerequisites above).

---

Best Practices

. Regular Health Checks
Run health checks at least every hour for critical tenants:

```bash
 crontab -e
     /path/to/check_system_health.sh --tenant-id company_a >> /var/log/smdh_health.log
```

. Daily Cost Reports
Generate daily cost reports for trending:

```bash
     /path/to/check_iot_costs.sh --export-csv /var/log/costs_$(date +\%Y\%m\%d).csv
```

. Alert on Anomalies
Set up alerts for:

- Health score drops below %
- More than % of devices disconnected
- Daily costs exceed expected thresholds
- Certificate expiry within days

. Archive Reports
Keep historical data for analysis:

```bash
 Archive monthly reports
mkdir -p /var/log/smdh/archive/$(date +%Y)
mv /var/log/smdh/costs_.csv /var/log/smdh/archive/$(date +%Y)/
```

---

Development

Adding New Checks

To add new health checks to `check_system_health.sh`:

. Add a new section after existing checks:

```bash
log_section ". Your New Check"

 Perform check
RESULT=$(your_command_here)

 Update health score logic
if [[ condition ]]; then
  ((CHECKS_PASSED++))
fi
```

. Update `CHECKS_TOTAL` in the summary section

. Document the new check in this README

Testing

Test scripts in development:

```bash
 Dry run with verbose output
./check_system_health.sh --tenant-id test_tenant --verbose

 Test cost tracking without actual billing data
./check_iot_costs.sh --tenant-id test_tenant --period
```

---

Support

For issues or feature requests:
. Check this README and the Thing Groups Guide
. Review script output with `--verbose` flag
. Check CloudWatch Logs for detailed metrics
. Contact the SMDH platform team

---

## E2E Pipeline Testing

For end-to-end pipeline testing (IoT Core → Kinesis → Openflow → Snowflake), see the **tests** folder:

```bash
cd tests/
```

**Available test scripts:**

| Script | Purpose |
|--------|---------|
| `device-simulators/ug65_e2e_test.py` | MQTT test with UG65 LoRaWAN message format |
| `device-simulators/realistic_facility_simulator.py` | Full facility simulation via MQTT |
| `device-simulators/test-iot-transmission.py` | Generic IoT device simulator |

**Quick MQTT E2E test:**

```bash
cd tests/device-simulators

# Send 5 UG65-formatted messages via MQTT
python ug65_e2e_test.py \
  --tenant-id test_tenant \
  --site-id SITE_001 \
  --count 5
```

**Verify data in Snowflake:**

```sql
USE DATABASE SMDH_TENANT_TEST_TENANT;

-- Check typed tables have data
SELECT 'sensor_readings' AS tbl, COUNT(*) FROM RAW.SENSOR_READINGS
UNION ALL SELECT 'environmental', COUNT(*) FROM RAW.ENVIRONMENTAL_READINGS
UNION ALL SELECT 'vibration', COUNT(*) FROM RAW.VIBRATION_READINGS
UNION ALL SELECT 'clamp', COUNT(*) FROM RAW.CLAMP_SENSOR_READINGS
UNION ALL SELECT 'device_status', COUNT(*) FROM RAW.DEVICE_STATUS;
```

See `tests/README.md` for full documentation on all test methods.

---

Related Documentation

- [Thing Groups and Billing Groups Guide](../terraform/THING_GROUPS_GUIDE.md)
- [Terraform Module Documentation](../terraform/README.md)
- [SMDH Implementation Plan](../SMDH_Implementation_Plan.md)
- [Openflow Kinesis Configuration Guide](docs/deployment/Openflow_Kinesis_Configuration_Guide.md)
