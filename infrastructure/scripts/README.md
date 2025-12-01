 SMDH Infrastructure Scripts

This directory contains operational scripts for managing and monitoring the SMDH platform.

 Available Scripts

 . System Health Check (`check_system_health.sh`)

Comprehensive health monitoring using AWS IoT Thing Groups.

Features:
-  Thing group status overview
-  Site-level device connectivity checks
-  Disconnected device alerts (dynamic groups)
-  MQTT message rate monitoring
-  Kinesis stream health
-  Certificate expiry warnings
-  CloudWatch alarm status
-  Overall health score

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
-  Per-tenant cost breakdown
-  Message, connection, and rule execution costs
-  Daily and monthly projections
-  Platform-wide cost summary
-  Cost optimization recommendations
-  CSV export for reporting
-  Kinesis cost estimates

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
- Certificate expiry within  days

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

 Related Documentation

- [Thing Groups and Billing Groups Guide](../terraform/THING_GROUPS_GUIDE.md)
- [Terraform Module Documentation](../terraform/README.md)
- [SMDH Implementation Plan](../SMDH_Implementation_Plan.md)
