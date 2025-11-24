# SMDH Infrastructure Deployment Notes

## Deployment Record: Development Environment

**Date**: 21 November 2025
**Time**: 14:04 UTC
**Environment**: Development (dev)
**Region**: eu-west-2 (Europe - London)
**AWS Account**: 471112943820
**Deployed By**: david@aiapplied.uk

---

## Deployment Summary

### Status: ✅ Successful

**Resources Created**: 48 AWS resources
**Deployment Time**: ~5 minutes
**Terraform Version**: 1.9.7
**AWS Provider**: ~> 5.0

### Infrastructure Components

#### Core Services (22 resources)
- **IoT Core**: 2 Thing Types, 2 IAM roles, logging configuration
- **Kinesis**: 1 stream, 3 CloudWatch alarms
- **IAM**: 1 Snowflake cross-account role
- **Secrets Manager**: 2 secrets (config + private key)
- **CloudWatch**: 1 dashboard, 1 log group, 3 alarms, 1 SNS topic

#### Tenant Resources (26 resources)
- **Tenant**: test_tenant
- **Sites**: 2 (site_001, site_002)
- **Gateways**: 2 IoT Things with certificates
- **Certificates**: 2 X.509 certificates
- **Policy**: 1 IoT policy with tenant isolation
- **Rule**: 1 IoT Rules Engine rule
- **Monitoring**: 2 alarms, 1 SNS topic

---

## Configuration Details

### IoT Core

**Endpoint**: `a28fbiixmeupm0-ats.iot.eu-west-2.amazonaws.com`
**MQTT Port**: 8883 (TLS)
**Protocol**: MQTT v3.1.1

**Thing Types**:
- `LoRaWANGateway` - For Milesight UG65 gateways
- `DevTankOSM` - For DevTank OpenSmartMonitor devices

**Logging**: DEBUG level to `/aws/iot/smdh` (30-day retention)

### Kinesis Data Stream

**Name**: `smdh-sensor-data-stream`
**Mode**: ON_DEMAND (auto-scaling)
**ARN**: `arn:aws:kinesis:eu-west-2:471112943820:stream/smdh-sensor-data-stream`

**Alarms**:
- Iterator age > 60000ms
- Read throughput exceeded
- Write throughput exceeded

### IAM Roles

**Snowflake Integration Role**:
```
Name: smdh-snowflake-kinesis-role-dev
ARN: arn:aws:iam::471112943820:role/smdh-snowflake-kinesis-role-dev
Trust Policy: AWS principal (awaiting Snowflake account ID)
Permissions: Kinesis read access
```

**IoT Core Kinesis Role**:
```
Name: smdh-iot-kinesis-role-dev
Permissions: Kinesis write access
```

**IoT Core Logging Role**:
```
Name: smdh-iot-logging-role-dev
Permissions: CloudWatch Logs write access
```

### CloudWatch Monitoring

**Dashboard**: [smdh-platform-dev](https://console.aws.amazon.com/cloudwatch/home?region=eu-west-2#dashboards:name=smdh-platform-dev)

**Metrics Tracked**:
- IoT Core: Message publish success/failure, connection success/failure
- Kinesis: Iterator age, incoming records, incoming bytes
- Device connectivity: Active connections, ping success

**Alarms**:
- Connection failures > 5 in 5 minutes
- Publish failures > 10 in 5 minutes
- No data received for 30 minutes

**SNS Topics**:
- `smdh-platform-alarms-dev` - Platform-level alerts
- `smdh-alerts-test_tenant` - Tenant-specific alerts

### Tenant: test_tenant

**Configuration**:
```
Tenant ID: test_tenant
Tenant Name: Test Tenant Ltd
Sites: 2
Sensors per site: 5
Retention: 90 days
Warehouse size: XSMALL
Contact: test@yourcompany.com
```

**IoT Resources**:
```
Policy Name: smdh-policy-test_tenant
Rule Name: smdh_route_test_tenant
Topic Pattern: smdh/test_tenant/+/sensor-data
Partition Key: test_tenant
```

**Gateways**:
1. `smdh-gateway-test_tenant-site_001-gw_001`
   - Certificate: `ae01f13c8f09f7f8618dc1f06b6780a9da06cc067b98f6bc0b1f0115bab2e4f1`
   - Site: site_001

2. `smdh-gateway-test_tenant-site_002-gw_001`
   - Certificate: `286ca0f732edbb0346a0cccb92170c4515d6b72a4da2951ae0849e41fb412079`
   - Site: site_002

---

## Tagging Strategy

All resources are tagged with:

### Mandatory Tags
- **Project**: smdh
- **Environment**: dev
- **ManagedBy**: Terraform
- **Repository**: smdh
- **Owner**: Platform-Team
- **CostCenter**: ENG-SMDH-001

### Operational Tags
- **DeployedAt**: 2025-11-21T14:04:55Z
- **DeployedBy**: david@aiapplied.uk
- **GitCommit**: (current commit hash)
- **GitRepo**: smdh

### Compliance Tags
- **DataClassification**: Internal
- **Compliance**: None (dev environment)
- **BackupPolicy**: Daily

### Component-Specific Tags
- **Component**: IoT-Core / Kinesis / CloudWatch / Tenant-Resources
- **Service**: AWS-IoT / AWS-Kinesis / AWS-CloudWatch
- **TenantId**: test_tenant (for tenant resources)
- **BillingTenant**: test_tenant (for cost allocation)

---

## Issues Encountered and Resolutions

### Issue 1: IoT Rule SQL Syntax Error
**Error**: `SqlParseException: Expected a comparison operation: timestamp IS NOT NULL`

**Cause**: IoT Rules SQL doesn't support WHERE clauses on built-in functions like `timestamp()`.

**Resolution**: Removed `WHERE timestamp IS NOT NULL` from the SQL query. The `timestamp()` function always generates a value, so validation is unnecessary.

**Fixed Code**:
```sql
SELECT *,
  topic(2) as tenant_id,
  topic(3) as site_id,
  timestamp() as iot_timestamp,
  clientId() as device_id
FROM 'smdh/test_tenant/+/sensor-data'
```

### Issue 2: IAM Dynamic Block Syntax Error
**Error**: `Cannot use a set of string value in for_each. An iterable collection is required`

**Cause**: Dynamic blocks in IAM policy documents have restrictions on `for_each` usage within data sources.

**Resolution**: Created separate policy documents for cases with and without External ID, then used conditional logic to select the appropriate one.

**Fixed Code**:
```hcl
data "aws_iam_policy_document" "snowflake_assume_base" {
  # Policy without External ID
}

data "aws_iam_policy_document" "snowflake_assume_with_external_id" {
  # Policy with External ID condition
}

locals {
  snowflake_assume_policy = var.snowflake_external_id != "" ?
    data.aws_iam_policy_document.snowflake_assume_with_external_id.json :
    data.aws_iam_policy_document.snowflake_assume_base.json
}
```

### Issue 3: AWS Provider Default Tags Inconsistency
**Error**: `Provider produced inconsistent final plan` for IoT Policy tags

**Cause**: Known AWS provider bug with `default_tags` feature on certain IoT resources.

**Impact**: None - all resources created successfully despite error messages

**Workaround**: Error is cosmetic and can be ignored. Running `terraform refresh` syncs state correctly.

---

## Post-Deployment Actions

### Completed
- ✅ S3 backend created: `smdh-terraform-state`
- ✅ DynamoDB lock table created: `smdh-terraform-locks`
- ✅ Terraform state initialized and synced
- ✅ All 48 resources provisioned successfully
- ✅ IoT endpoint verified and accessible
- ✅ Kinesis stream active and ready
- ✅ CloudWatch dashboard created
- ✅ SNS topics created (pending email confirmation)

### Pending
- ⏳ Confirm SNS subscription emails (sent to david@aiapplied.uk and test@yourcompany.com)
- ⏳ Update Snowflake account ID in terraform.tfvars
- ⏳ Generate and set Snowflake external ID
- ⏳ Extract device certificates from Terraform state
- ⏳ Configure physical gateway devices with certificates
- ⏳ Test MQTT connectivity
- ⏳ Configure Snowflake database and schemas
- ⏳ Set up Snowflake Openflow connector
- ⏳ Test end-to-end data flow

---

## Terraform State

**Backend**: S3
**Bucket**: `smdh-terraform-state`
**Key**: `infrastructure/terraform.tfstate`
**Region**: eu-west-2
**Encryption**: Enabled (AES256)
**Lock Table**: `smdh-terraform-locks` (DynamoDB)

**State File Size**: ~15KB
**Last Modified**: 2025-11-21 14:04:55 UTC

---

## Cost Estimation

Based on current deployment:

### AWS Monthly Costs (Development)

| Service | Usage | Monthly Cost |
|---------|-------|-------------|
| IoT Core | ~1000 messages/day | ~$0.08 |
| Kinesis | On-demand stream | ~$2.50 |
| CloudWatch | 1GB logs/month | ~$0.50 |
| Secrets Manager | 2 secrets | ~$0.80 |
| SNS | <1000 notifications | ~$0.00 |
| IAM | No charge | $0.00 |
| **Total** | | **~$3.88/month** |

### Expected Production Costs (30 Tenants)

| Service | Usage | Monthly Cost |
|---------|-------|-------------|
| IoT Core | 26M messages/day | ~$130 |
| Kinesis | On-demand | ~$18 |
| CloudWatch | 200GB logs | ~$100 |
| Secrets Manager | 30 secrets | ~$12 |
| SNS | 10K notifications | ~$2 |
| **Total** | | **~$262/month** |

---

## Next Steps

### Immediate (Within 24 hours)
1. Confirm SNS email subscriptions
2. Document certificate extraction procedure
3. Test IoT endpoint connectivity with MQTT client
4. Verify CloudWatch dashboard displays metrics

### Short-term (Within 1 week)
1. Configure Snowflake account integration
2. Set up first production tenant
3. Deploy certificates to test gateway device
4. Validate end-to-end data flow
5. Create runbook for tenant onboarding

### Medium-term (Within 1 month)
1. Deploy production environment via Terraform
2. Migrate test_tenant to production
3. Onboard first customer tenant
4. Set up billing alerts and cost tracking
5. Document disaster recovery procedures

---

## References

- [Terraform Configuration](terraform/README.md)
- [Tagging Strategy](terraform/TAGGING_STRATEGY.md)
- [Implementation Guide](SMDH_Infrastructure_Implementation.md)
- [AWS Design Document](../docs/detailed-design/SMDH%20AWS%20design.md)
- [Deployment Guide](../docs/deployment/)

---

**Last Updated**: 2025-11-21 14:30 UTC
**Maintained By**: Platform Team
