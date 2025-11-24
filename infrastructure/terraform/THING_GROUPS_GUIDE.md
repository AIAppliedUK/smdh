# AWS IoT Thing Groups and Billing Groups Guide

## Overview

This guide explains how SMDH uses AWS IoT Thing Groups and Billing Groups to manage devices efficiently and track costs per tenant.

## Architecture

### Thing Group Hierarchy

```
SMDH Platform
├── smdh-tenant-company_a (Tenant Group)
│   ├── smdh-company_a-site_001 (Site Group)
│   │   └── smdh-gateway-company_a-site_001-gw_001 (Device)
│   ├── smdh-company_a-site_002 (Site Group)
│   │   └── smdh-gateway-company_a-site_002-gw_001 (Device)
│   └── smdh-company_a-site_003 (Site Group)
│       └── smdh-gateway-company_a-site_003-gw_001 (Device)
├── smdh-tenant-company_b (Tenant Group)
│   └── ...
└── Dynamic Groups
    ├── smdh-company_a-disconnected (Query-based)
    └── smdh-company_a-active (Query-based)
```

### Billing Groups

Each tenant has a billing group for cost tracking:
- `smdh-billing-company_a`
- `smdh-billing-company_b`
- etc.

## Benefits

### 1. Efficient Device Management

**Before Thing Groups:**
```bash
# Had to query each device individually
for device in device1 device2 device3 ...; do
  aws iot describe-thing --thing-name $device
done
```

**With Thing Groups:**
```bash
# Query entire site with one command
aws iot list-things-in-thing-group \
  --thing-group-name smdh-company_a-site_001
```

### 2. Hierarchical Monitoring

Check all devices for a tenant at once:
```bash
aws iot list-things-in-thing-group \
  --thing-group-name smdh-tenant-company_a \
  --recursive
```

Check specific site:
```bash
aws iot list-things-in-thing-group \
  --thing-group-name smdh-company_a-site_001
```

### 3. Cost Tracking

Get costs per tenant using billing groups:
```bash
# Run the cost tracking script
./infrastructure/scripts/check_iot_costs.sh --tenant-id company_a --period 30
```

### 4. Bulk Operations

Apply changes to all devices at a site:
```bash
# Rotate certificates for all devices at site_001
THINGS=$(aws iot list-things-in-thing-group \
  --thing-group-name smdh-company_a-site_001 \
  --query 'things' --output text)

for thing in $THINGS; do
  # Perform certificate rotation
  echo "Rotating certificate for $thing"
done
```

### 5. Dynamic Groups

Dynamic groups automatically track device states using queries:

**Disconnected Devices:**
```bash
# Automatically populated with disconnected devices
aws iot list-things-in-thing-group \
  --thing-group-name smdh-company_a-disconnected
```

**Active Devices:**
```bash
# Automatically populated with recently active devices
aws iot list-things-in-thing-group \
  --thing-group-name smdh-company_a-active
```

## Common Operations

### Query All Devices for a Tenant

```bash
aws iot list-things-in-thing-group \
  --thing-group-name smdh-tenant-company_a \
  --region eu-west-2
```

### Check Connectivity Status by Site

```bash
# Get all devices at a site
aws iot search-index \
  --index-name "AWS_Things" \
  --query-string "thingGroupNames:smdh-company_a-site_001 AND connectivity.connected:true" \
  --region eu-west-2
```

### Get Site Health Summary

```bash
# Use the enhanced monitoring script
./infrastructure/scripts/check_system_health.sh \
  --tenant-id company_a \
  --site-id site_001
```

### Track Costs

```bash
# Get costs for all tenants
./infrastructure/scripts/check_iot_costs.sh --period 30

# Get costs for specific tenant
./infrastructure/scripts/check_iot_costs.sh \
  --tenant-id company_a \
  --period 30 \
  --export-csv company_a_costs.csv
```

### List All Thing Groups

```bash
# List tenant-level groups
aws iot list-thing-groups \
  --region eu-west-2 \
  --query 'thingGroups[?starts_with(groupName, `smdh-tenant-`)].groupName'

# List site groups for a tenant
aws iot list-thing-groups \
  --parent-group smdh-tenant-company_a \
  --region eu-west-2
```

### Get Thing Group Attributes

```bash
aws iot describe-thing-group \
  --thing-group-name smdh-company_a-site_001 \
  --region eu-west-2
```

## CloudWatch Integration

### Site-Level Metrics

Create CloudWatch dashboards per site using thing groups:

```bash
# Get all devices in a site for dashboard widget
DEVICES=$(aws iot list-things-in-thing-group \
  --thing-group-name smdh-company_a-site_001 \
  --query 'things' \
  --output json)

# Use in CloudWatch dashboard definition
```

### Alarms Based on Thing Groups

Create alarms that trigger when all devices at a site go offline:

```bash
# Example: Alert if site has 0 connected devices
aws cloudwatch put-metric-alarm \
  --alarm-name "smdh-company_a-site_001-all-offline" \
  --alarm-description "Alert when all devices at site_001 are offline" \
  --metric-name ConnectedDeviceCount \
  --namespace SMDH/Sites \
  --statistic Sum \
  --period 300 \
  --evaluation-periods 2 \
  --threshold 0 \
  --comparison-operator LessThanOrEqualToThreshold
```

## Terraform Integration

### Creating Thing Groups

Thing groups are automatically created by Terraform when you provision a tenant:

```hcl
module "tenant_company_a" {
  source = "./modules/tenant"

  tenant_id   = "company_a"
  tenant_name = "Company A Ltd"
  num_sites   = 5

  # Thing groups created automatically:
  # - smdh-tenant-company_a (tenant-level)
  # - smdh-company_a-site_001 through site_005 (site-level)
  # - smdh-company_a-disconnected (dynamic)
  # - smdh-company_a-active (dynamic)
  # - smdh-billing-company_a (billing group)
}
```

### Accessing Thing Group Outputs

After `terraform apply`, access thing group information:

```bash
# Get tenant thing group name
terraform output -json | jq '.tenants.value.company_a.tenant_thing_group_name'

# Get all site thing groups
terraform output -json | jq '.tenants.value.company_a.site_thing_group_names'

# Get billing group
terraform output -json | jq '.tenants.value.company_a.billing_group_name'
```

## Cost Tracking Details

### How Billing Groups Track Costs

AWS IoT Core charges based on:
1. **Messages published** ($1.00 per million messages)
2. **Connection minutes** ($0.08 per million connection-minutes)
3. **Rule executions** ($0.15 per million rule executions)

Billing groups associate all these charges with a specific tenant.

### Cost Report Example

```bash
$ ./infrastructure/scripts/check_iot_costs.sh --tenant-id company_a --period 7

========================================
SMDH IoT Cost Tracking
========================================
Region: eu-west-2
Period: 2025-11-14 to 2025-11-21 (7 days)
Tenant: company_a (specific tenant)

========================================
IoT Cost Breakdown by Tenant
========================================

Tenant: company_a
Billing Group: smdh-billing-company_a
----------------------------------------
  Devices in billing group: 15
  Messages published: 5,040,000
  Message cost: $5.0400
  Connection minutes (estimated): 151,200
  Connection cost: $0.0121
  Rule executions: 5,040,000
  Rule cost: $0.7560

  Total estimated cost: $5.8081
  Daily average: $0.8297
  Monthly projection: $24.89
```

## Monitoring Script Usage

### Check System Health

```bash
# Check all sites for a tenant
./infrastructure/scripts/check_system_health.sh --tenant-id company_a

# Check specific site
./infrastructure/scripts/check_system_health.sh \
  --tenant-id company_a \
  --site-id site_001

# Verbose output with device details
./infrastructure/scripts/check_system_health.sh \
  --tenant-id company_a \
  --verbose
```

### Automated Health Checks

Add to cron for regular monitoring:

```bash
# Check health every hour
0 * * * * /path/to/check_system_health.sh --tenant-id company_a >> /var/log/smdh_health.log 2>&1

# Daily cost report
0 0 * * * /path/to/check_iot_costs.sh --tenant-id company_a --export-csv /var/log/costs_$(date +\%Y\%m\%d).csv
```

## Best Practices

### 1. Use Thing Groups for Queries
❌ **Don't:**
```bash
# Inefficient - queries each device individually
for device in $(cat device_list.txt); do
  aws iot describe-thing --thing-name $device
done
```

✅ **Do:**
```bash
# Efficient - single query for entire site
aws iot list-things-in-thing-group --thing-group-name smdh-company_a-site_001
```

### 2. Leverage Dynamic Groups for Monitoring
```bash
# Automatically get disconnected devices
DISCONNECTED=$(aws iot list-things-in-thing-group \
  --thing-group-name smdh-company_a-disconnected)

if [[ $(echo "$DISCONNECTED" | jq '. | length') -gt 0 ]]; then
  # Send alert
  echo "ALERT: Disconnected devices detected"
fi
```

### 3. Use Billing Groups for Showback/Chargeback
```bash
# Generate monthly cost reports per tenant
for tenant in company_a company_b company_c; do
  ./check_iot_costs.sh \
    --tenant-id $tenant \
    --period 30 \
    --export-csv "${tenant}_monthly_costs.csv"
done
```

### 4. Tag Thing Groups Appropriately
All thing groups include these tags:
- `TenantId`: For filtering and cost allocation
- `SiteId`: For site-specific queries (site groups only)
- `Purpose`: Description of the group's function
- `ManagedBy`: "terraform" to indicate IaC management

### 5. Update Attributes for Metadata
Thing groups can store metadata:
```bash
aws iot update-thing-group \
  --thing-group-name smdh-company_a-site_001 \
  --attribute-payload '{"attributes": {"location": "London Factory", "contact": "site-manager@company-a.com"}}'
```

## Troubleshooting

### Thing Not Appearing in Group

Check thing group membership:
```bash
aws iot list-thing-groups-for-thing \
  --thing-name smdh-gateway-company_a-site_001-gw_001
```

Add thing to group manually if needed:
```bash
aws iot add-thing-to-thing-group \
  --thing-name smdh-gateway-company_a-site_001-gw_001 \
  --thing-group-name smdh-company_a-site_001
```

### Billing Group Shows Zero Cost

Ensure things are attached to billing group:
```bash
aws iot list-things-in-billing-group \
  --billing-group-name smdh-billing-company_a

# If empty, attach things
aws iot add-thing-to-billing-group \
  --thing-name <thing-name> \
  --billing-group-name smdh-billing-company_a
```

### Dynamic Group Not Populating

Dynamic groups require IoT Search index to be enabled:
```bash
aws iot describe-index --index-name "AWS_Things"
```

If not enabled, it can take up to 24 hours for dynamic groups to populate after creation.

## Security Considerations

### Least Privilege Access

Grant users access to specific thing groups:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "iot:ListThingsInThingGroup",
        "iot:DescribeThingGroup"
      ],
      "Resource": "arn:aws:iot:eu-west-2:*:thinggroup/smdh-company_a-*"
    }
  ]
}
```

### Audit Trail

All thing group operations are logged in CloudTrail:
```bash
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=ResourceName,AttributeValue=smdh-company_a-site_001
```

## Performance Tips

1. **Use `--recursive` flag** for tenant-wide queries to include nested groups
2. **Cache thing group memberships** if querying frequently
3. **Use IoT Search index** for complex queries (connectivity, attributes, etc.)
4. **Batch operations** when adding/removing multiple things from groups

## Additional Resources

- [AWS IoT Thing Groups Documentation](https://docs.aws.amazon.com/iot/latest/developerguide/thing-groups.html)
- [AWS IoT Billing Groups Documentation](https://docs.aws.amazon.com/iot/latest/developerguide/billing-groups.html)
- [AWS IoT Core Pricing](https://aws.amazon.com/iot-core/pricing/)
- [IoT Search Query Syntax](https://docs.aws.amazon.com/iot/latest/developerguide/query-syntax.html)

## Support

For issues with thing groups or billing groups:
1. Check this guide first
2. Run monitoring scripts with `--verbose` flag
3. Review CloudTrail logs for recent changes
4. Contact the SMDH platform team
