# SMDH Infrastructure Scripts

This directory contains operational scripts for managing and monitoring the SMDH platform.

## Available Scripts

### 1. System Health Check (`check_system_health.sh`)

Comprehensive health monitoring using AWS IoT Thing Groups.

**Features:**
- ✅ Thing group status overview
- ✅ Site-level device connectivity checks
- ✅ Disconnected device alerts (dynamic groups)
- ✅ MQTT message rate monitoring
- ✅ Kinesis stream health
- ✅ Certificate expiry warnings
- ✅ CloudWatch alarm status
- ✅ Overall health score

**Usage:**
```bash
# Check all sites for a tenant
./check_system_health.sh --tenant-id company_a

# Check specific site
./check_system_health.sh --tenant-id company_a --site-id site_001

# Verbose output with device-level details
./check_system_health.sh --tenant-id company_a --verbose

# Different AWS region
./check_system_health.sh --tenant-id company_a --region eu-west-1
```

**Exit Codes:**
- `0`: Healthy (≥85% health score)
- `1`: Degraded (60-84% health score)
- `2`: Critical (<60% health score)

**Example Output:**
```
========================================
SMDH System Health Check
========================================
Tenant: company_a
Region: eu-west-2
Site: ALL (tenant-wide check)

========================================
1. Thing Group Overview
========================================
[INFO] Tenant thing group found: smdh-tenant-company_a
  Total devices in tenant: 15

========================================
2. Site-Level Device Status
========================================

Site Group: smdh-company_a-site_001
----------------------------------------
  Total devices: 3
  Status Summary:
    Connected:    3 devices
    Disconnected: 0 devices
    Site Health:  100%

========================================
Health Check Summary
========================================
Overall Health Score: 100% (7/7 checks passed)
System Status: HEALTHY ✓
```

**Automation:**
```bash
# Add to cron for hourly checks
0 * * * * /path/to/check_system_health.sh --tenant-id company_a >> /var/log/smdh_health.log

# Alert on failures
./check_system_health.sh --tenant-id company_a || \
  aws sns publish --topic-arn $ALERT_TOPIC --message "Health check failed"
```

---

### 2. IoT Cost Tracking (`check_iot_costs.sh`)

Cost analysis and reporting using AWS IoT Billing Groups.

**Features:**
- ✅ Per-tenant cost breakdown
- ✅ Message, connection, and rule execution costs
- ✅ Daily and monthly projections
- ✅ Platform-wide cost summary
- ✅ Cost optimization recommendations
- ✅ CSV export for reporting
- ✅ Kinesis cost estimates

**Usage:**
```bash
# Check all tenants (last 7 days)
./check_iot_costs.sh

# Specific tenant with custom period
./check_iot_costs.sh --tenant-id company_a --period 30

# Export to CSV for reporting
./check_iot_costs.sh --tenant-id company_a --export-csv costs_report.csv

# JSON output for automation
./check_iot_costs.sh --format json
```

**Example Output:**
```
========================================
SMDH IoT Cost Tracking
========================================
Region: eu-west-2
Period: 2025-10-22 to 2025-11-21 (30 days)
Tenant: company_a (specific tenant)

========================================
IoT Cost Breakdown by Tenant
========================================

Tenant: company_a
Billing Group: smdh-billing-company_a
----------------------------------------
  Devices in billing group: 15
  Messages published: 21,600,000
  Message cost: $21.6000
  Connection minutes (estimated): 648,000
  Connection cost: $0.0518
  Rule executions: 21,600,000
  Rule cost: $3.2400

  Total estimated cost: $24.8918
  Daily average: $0.8297
  Monthly projection: $24.89

========================================
Cost Optimization Recommendations
========================================
[INFO] General Recommendations:
  • Use QoS 0 instead of QoS 1 when delivery guarantees aren't critical
  • Implement message compression for large payloads
  • Use device shadows instead of frequent polling
  • Batch multiple sensor readings into single MQTT messages
```

**Monthly Cost Reports:**
```bash
# Generate monthly reports for all tenants
for tenant in company_a company_b company_c; do
  ./check_iot_costs.sh \
    --tenant-id $tenant \
    --period 30 \
    --export-csv "reports/${tenant}_$(date +%Y%m).csv"
done
```

---

## Prerequisites

### AWS CLI Configuration

Ensure AWS CLI is configured with appropriate credentials:

```bash
aws configure
# Enter Access Key ID, Secret Access Key, Region (eu-west-2)

# Verify configuration
aws sts get-caller-identity
```

### Required AWS Permissions

The scripts require these IAM permissions:

```json
{
  "Version": "2012-10-17",
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
      "Resource": "*"
    }
  ]
}
```

### Environment Variables

Optional environment variables:

```bash
export AWS_REGION=eu-west-2
export AWS_PROFILE=smdh-admin

# Run scripts with custom AWS profile
AWS_PROFILE=smdh-prod ./check_system_health.sh --tenant-id company_a
```

---

## Integration Examples

### CI/CD Pipeline Health Checks

```yaml
# .github/workflows/health-check.yml
name: Platform Health Check

on:
  schedule:
    - cron: '0 */6 * * *'  # Every 6 hours

jobs:
  health-check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: Configure AWS
        uses: aws-actions/configure-aws-credentials@v1
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: eu-west-2
      - name: Run Health Check
        run: |
          ./infrastructure/scripts/check_system_health.sh \
            --tenant-id company_a || exit 1
```

### Slack Notifications

```bash
#!/bin/bash
# health-check-with-slack.sh

TENANT_ID="company_a"
SLACK_WEBHOOK="https://hooks.slack.com/services/YOUR/WEBHOOK/URL"

# Run health check
OUTPUT=$(./check_system_health.sh --tenant-id $TENANT_ID 2>&1)
EXIT_CODE=$?

# Extract health score
HEALTH_SCORE=$(echo "$OUTPUT" | grep "Overall Health Score" | awk '{print $4}')

# Send to Slack if degraded or critical
if [ $EXIT_CODE -ne 0 ]; then
  curl -X POST $SLACK_WEBHOOK -H 'Content-Type: application/json' -d "{
    \"text\": \"⚠️ SMDH Health Alert for ${TENANT_ID}\",
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

### CloudWatch Events

```bash
#!/bin/bash
# Publish health metrics to CloudWatch

TENANT_ID="company_a"

# Run health check and capture output
OUTPUT=$(./check_system_health.sh --tenant-id $TENANT_ID 2>&1)
EXIT_CODE=$?

# Extract metrics
HEALTH_SCORE=$(echo "$OUTPUT" | grep "Overall Health Score" | awk '{print $4}' | tr -d '%')

# Publish to CloudWatch
aws cloudwatch put-metric-data \
  --namespace SMDH/Health \
  --metric-name HealthScore \
  --dimensions TenantId=$TENANT_ID \
  --value $HEALTH_SCORE \
  --unit Percent
```

### Cost Budget Alerts

```bash
#!/bin/bash
# alert-on-cost-threshold.sh

TENANT_ID="company_a"
THRESHOLD=50.00  # Alert if monthly projection exceeds $50

# Get cost projection
OUTPUT=$(./check_iot_costs.sh --tenant-id $TENANT_ID --period 30)
MONTHLY_PROJECTION=$(echo "$OUTPUT" | grep "Monthly projection" | awk '{print $3}' | tr -d '$')

# Compare with threshold
if (( $(echo "$MONTHLY_PROJECTION > $THRESHOLD" | bc -l) )); then
  echo "ALERT: ${TENANT_ID} projected monthly cost (\$${MONTHLY_PROJECTION}) exceeds threshold (\$${THRESHOLD})"

  # Send alert (SNS, email, Slack, etc.)
  aws sns publish \
    --topic-arn arn:aws:sns:eu-west-2:123456789012:smdh-cost-alerts \
    --subject "Cost Alert: ${TENANT_ID}" \
    --message "Projected monthly cost: \$${MONTHLY_PROJECTION}"
fi
```

---

## Troubleshooting

### Script Permission Denied

```bash
chmod +x infrastructure/scripts/*.sh
```

### AWS CLI Not Found

```bash
# Install AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
```

### Thing Group Not Found

Ensure Terraform has been applied:
```bash
cd infrastructure/terraform
terraform plan
terraform apply
```

### No Metrics Data

CloudWatch metrics may have a delay. Try:
1. Increase the period: `--period 30` instead of `--period 7`
2. Check if devices are actually sending data
3. Verify IoT Rules are enabled

### Permission Denied Errors

Ensure your AWS IAM user/role has the required permissions (see Prerequisites above).

---

## Best Practices

### 1. Regular Health Checks
Run health checks at least every hour for critical tenants:
```bash
# crontab -e
0 * * * * /path/to/check_system_health.sh --tenant-id company_a >> /var/log/smdh_health.log
```

### 2. Daily Cost Reports
Generate daily cost reports for trending:
```bash
0 0 * * * /path/to/check_iot_costs.sh --export-csv /var/log/costs_$(date +\%Y\%m\%d).csv
```

### 3. Alert on Anomalies
Set up alerts for:
- Health score drops below 80%
- More than 20% of devices disconnected
- Daily costs exceed expected thresholds
- Certificate expiry within 30 days

### 4. Archive Reports
Keep historical data for analysis:
```bash
# Archive monthly reports
mkdir -p /var/log/smdh/archive/$(date +%Y)
mv /var/log/smdh/costs_*.csv /var/log/smdh/archive/$(date +%Y)/
```

---

## Development

### Adding New Checks

To add new health checks to `check_system_health.sh`:

1. Add a new section after existing checks:
```bash
log_section "8. Your New Check"

# Perform check
RESULT=$(your_command_here)

# Update health score logic
if [[ condition ]]; then
  ((CHECKS_PASSED++))
fi
```

2. Update `CHECKS_TOTAL` in the summary section

3. Document the new check in this README

### Testing

Test scripts in development:
```bash
# Dry run with verbose output
./check_system_health.sh --tenant-id test_tenant --verbose

# Test cost tracking without actual billing data
./check_iot_costs.sh --tenant-id test_tenant --period 1
```

---

## Support

For issues or feature requests:
1. Check this README and the Thing Groups Guide
2. Review script output with `--verbose` flag
3. Check CloudWatch Logs for detailed metrics
4. Contact the SMDH platform team

## Related Documentation

- [Thing Groups and Billing Groups Guide](../terraform/THING_GROUPS_GUIDE.md)
- [Terraform Module Documentation](../terraform/README.md)
- [SMDH Implementation Plan](../SMDH_Implementation_Plan.md)
