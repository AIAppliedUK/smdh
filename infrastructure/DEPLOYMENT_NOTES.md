# SMDH Infrastructure Deployment Notes

## Deployment Record: Development Environment

**Date:** December 1, 2025
**Time:** 08:36 UTC
**Environment:** Development (dev)
**Region:** eu-west-2 (Europe - London)
**AWS Account:** 471112943820
**Deployed By:** david@aiapplied.uk

---

## Deployment Summary

### Status: ✅ Successful

**Resources Created:** 63 AWS resources
**Deployment Time:** ~10 minutes
**Terraform Version:** 1.5.7
**AWS Provider:** ~> 5.0

## Infrastructure Components

### Core Services (27 resources)
- **IoT Core:** 10 Thing Types, 2 IAM roles, logging configuration
- **Kinesis:** 1 stream, 3 CloudWatch alarms
- **IAM:** 1 Snowflake cross-account role
- **Secrets Manager:** 2 secrets (config + private key)
- **CloudWatch:** 1 dashboard, 1 log group, 3 alarms, 1 SNS topic

### Tenant Resources (36 resources)
- **Tenant:** test_tenant
- **Deployment Mode:** gateway (Milesight UG65 with built-in NS)
- **Sites:** 2 (site_001, site_002)
- **Gateways:** 2 IoT Things with certificates
- **Certificates:** 2 X.509 certificates
- **Policy:** 1 IoT policy with tenant isolation
- **Rule:** 1 IoT Rules Engine rule
- **Thing Groups:** 5 (1 tenant, 2 sites, 2 dynamic groups)
- **Monitoring:** 3 alarms, 1 SNS topic

---

## Configuration Details

### IoT Core

**Endpoint:** `a28fbiixmeupm0-ats.iot.eu-west-2.amazonaws.com`
**MQTT Port:** 8883 (TLS)
**Protocol:** MQTT v3.1.1

**Thing Types (10):**
- `LoRaWANGateway` - For Milesight UG65 gateways
- `NetworkServer` - For ChirpStack or similar network servers
- `DevTankOSM` - For DevTank OpenSmartMonitor devices
- `AirQualitySensor` - Air quality monitoring sensors
- `PowerEnergySensor` - Power/energy consumption sensors
- `WaterSensor` - Water flow/quality sensors
- `GasSensor` - Gas detection sensors
- `EnvironmentalSensor` - Temperature/humidity sensors
- `AcousticSensor` - Noise level sensors
- `LightSensor` - Light level sensors

**Logging:** DEBUG level to `/aws/iot/smdh` (30-day retention)

### Thing Group Hierarchy

```
smdh-tenant-test_tenant (Tenant Group)
├── smdh-test_tenant-site_001 (Site Group)
│   └── smdh-gateway-test_tenant-site_001-gw_001
├── smdh-test_tenant-site_002 (Site Group)
│   └── smdh-gateway-test_tenant-site_002-gw_001
├── smdh-test_tenant-active (Dynamic - Active Devices)
└── smdh-test_tenant-disconnected (Dynamic - Disconnected Devices)
```

### Kinesis Data Stream

**Name:** `smdh-sensor-data-stream`
**Mode:** ON_DEMAND (auto-scaling)
**ARN:** `arn:aws:kinesis:eu-west-2:471112943820:stream/smdh-sensor-data-stream`

**Alarms:**
- Iterator age > 300000ms
- Read throughput exceeded
- Write throughput exceeded

### IAM Roles

**Snowflake Integration Role:**
```
Name: smdh-snowflake-kinesis-role-dev
ARN: arn:aws:iam::471112943820:role/smdh-snowflake-kinesis-role-dev
Trust Policy: AWS principal (awaiting Snowflake account ID)
Permissions: Kinesis read access
```

**IoT Core Kinesis Role:**
```
Name: smdh-iot-kinesis-role-dev
Permissions: Kinesis write access
```

**IoT Core Logging Role:**
```
Name: smdh-iot-logging-role-dev
Permissions: CloudWatch Logs write access
```

### CloudWatch Monitoring

**Dashboard:** [smdh-platform-dev](https://console.aws.amazon.com/cloudwatch/home?region=eu-west-2#dashboards:name=smdh-platform-dev)

**Metrics Tracked:**
- IoT Core: Message publish success/failure, connection success/failure
- Kinesis: Iterator age, incoming records, incoming bytes
- Device connectivity: Active connections, ping success

**Alarms:**
- Connection failures > 5 in 5 minutes
- Publish failures > 10 in 5 minutes
- No data received for 30 minutes

**SNS Topics:**
- `smdh-platform-alarms-dev` - Platform-level alerts
- `smdh-alerts-test_tenant` - Tenant-specific alerts

### Tenant: test_tenant

**Configuration:**
```
Tenant ID: test_tenant
Tenant Name: Test Tenant Ltd
Deployment Mode: gateway
Sites: 2
Sensors per site: 5
Retention: 90 days
Warehouse size: XSMALL
Contact: david@aiapplied.uk
```

**IoT Resources:**
```
Policy Name: smdh-policy-test_tenant
Rule Name: smdh_route_test_tenant
Topic Pattern: smdh/test_tenant/+/sensor-data
Partition Key: test_tenant
```

**Gateways:**
1. `smdh-gateway-test_tenant-site_001-gw_001`
   - Certificate: `c0265d11b6017521ca500c346669aea8c048e9c1633a111f472ecfab59690aa1`
   - Site: site_001
   - Thing Group: smdh-test_tenant-site_001

2. `smdh-gateway-test_tenant-site_002-gw_001`
   - Certificate: `64932de89b8c4114695dca0ea8ad7336f601c8e21f5fc0552d964462bc672da9`
   - Site: site_002
   - Thing Group: smdh-test_tenant-site_002

---

## Snowflake Infrastructure

**Deployed via:** `validate_setup.sh test_tenant`

### Databases Created
- `smdh_infrastructure` - Platform shared resources
- `smdh_tenant_test_tenant` - Tenant-specific database

### Warehouses
- `SMDH_WH` - General purpose warehouse (SMALL, auto-suspend 60s)

### Roles
- `SMDH_INFRASTRUCTURE_ADMIN` - Platform administration
- `SMDH_MONITORING` - Read-only monitoring access
- `SMDH_TENANT_OPERATOR` - Tenant lifecycle management
- `SMDH_DATA_ENGINEER` - ETL pipeline management
- `SMDH_ANALYTICS_USER` - Analytics base role
- `SMDH_TENANT_TEST_TENANT_ADMIN` - Tenant admin
- `SMDH_TENANT_TEST_TENANT_USER` - Tenant user
- `SMDH_TENANT_TEST_TENANT_READONLY` - Tenant read-only

### Schemas (per tenant)
- `RAW` - Ingested data from Kinesis
- `NORMALIZED` - Validated and flattened data
- `AGGREGATED` - Pre-computed metrics
- `ANALYTICS` - Views and dashboards

---

## Tagging Strategy

All resources are tagged with:

### Mandatory Tags
- Project: smdh
- Environment: dev
- ManagedBy: Terraform
- Repository: smdh
- Owner: Platform-Team
- CostCenter: ENG-SMDH-001

### Operational Tags
- DeployedAt: 2025-12-01T08:36:52Z
- DeployedBy: david@aiapplied.uk
- GitRepo: smdh

### Compliance Tags
- DataClassification: Internal
- Compliance: None (dev environment)
- BackupPolicy: Daily

### Component-Specific Tags
- Component: IoT-Core / Kinesis / CloudWatch / Tenant-Resources
- Service: AWS-IoT / AWS-Kinesis / AWS-CloudWatch
- TenantId: test_tenant (for tenant resources)
- BillingTenant: test_tenant (for cost allocation)

---

## Deployment Modes

The infrastructure now supports two deployment modes per tenant:

### Gateway Mode (Default)
- One Milesight UG65 gateway per site with built-in Network Server
- Each gateway connects directly to AWS IoT Core
- Creates one IoT Thing per site

### Network Server Mode
- One centralized ChirpStack (or similar) Network Server per tenant
- Network Server connects to AWS IoT Core
- Creates one IoT Thing for the entire tenant
- Multiple gateways connect to the Network Server (managed externally)

---

## Post-Deployment Status

### Completed
- ✅ S3 backend created: `smdh-terraform-state`
- ✅ DynamoDB lock table created: `smdh-terraform-locks`
- ✅ Terraform state initialized and synced
- ✅ All 63 AWS resources provisioned successfully
- ✅ 10 IoT Thing Types created
- ✅ Thing Group hierarchy established
- ✅ IoT endpoint verified and accessible
- ✅ Kinesis stream active and ready
- ✅ CloudWatch dashboard created
- ✅ SNS topics created
- ✅ Snowflake infrastructure database created
- ✅ Snowflake tenant database created
- ✅ Snowflake roles and warehouses configured

### Pending
- ⏳ Configure Snowflake Openflow connector with actual AWS IAM credentials
- ⏳ Update AWS IAM trust policy with Snowflake principal
- ⏳ Extract device certificates from Terraform state
- ⏳ Configure physical gateway devices with certificates
- ⏳ Test MQTT connectivity
- ⏳ Test end-to-end data flow (IoT → Kinesis → Snowflake)

---

## Useful Commands

### Check Disconnected Devices
```bash
aws iot list-things-in-thing-group --thing-group-name smdh-test_tenant-disconnected --region eu-west-2
```

### List All Tenant Devices
```bash
aws iot list-things-in-thing-group --thing-group-name smdh-tenant-test_tenant --recursive --region eu-west-2
```

### List All Thing Groups
```bash
aws iot list-thing-groups --region eu-west-2
```

### Check System Health
```bash
cd infrastructure/scripts && ./check_system_health.sh --tenant-id test_tenant
```

### Sync AWS IoT Metadata to Snowflake
```bash
cd infrastructure/snowflake/scripts && ./sync_aws_iot_metadata.sh --tenant-id test_tenant
```

---

## Terraform State

**Backend:** S3
**Bucket:** `smdh-terraform-state`
**Key:** `infrastructure/terraform.tfstate`
**Region:** eu-west-2
**Encryption:** Enabled (AES-256)
**Lock Table:** `smdh-terraform-locks` (DynamoDB)

---

## Cost Estimation

Based on current deployment:

### AWS Monthly Costs (Development)

| Service | Usage | Monthly Cost |
|---------|-------|-------------|
| IoT Core | ~1000 messages/day | ~$0.10 |
| Kinesis | On-demand stream | ~$0.50 |
| CloudWatch | 1GB logs/month | ~$0.50 |
| Secrets Manager | 2 secrets | ~$0.80 |
| SNS | <100 notifications | ~$0.01 |
| IAM | No charge | $0.00 |
| **Total** | | **~$2.00/month** |

### Expected Production Costs (10 Tenants)

| Service | Usage | Monthly Cost |
|---------|-------|-------------|
| IoT Core | 1M messages/day | ~$100 |
| Kinesis | On-demand | ~$50 |
| CloudWatch | 50GB logs | ~$25 |
| Secrets Manager | 20 secrets | ~$8 |
| SNS | 10K notifications | ~$1 |
| **Total** | | **~$185/month** |

---

## Next Steps

### Immediate (Within 24 hours)
1. Configure Snowflake Openflow connector with AWS credentials
2. Document certificate extraction procedure
3. Test IoT endpoint connectivity with MQTT client
4. Verify CloudWatch dashboard displays metrics

### Short-term (Within 1 week)
1. Update AWS IAM trust policy for Snowflake
2. Deploy certificates to test gateway device
3. Validate end-to-end data flow
4. Create runbook for tenant onboarding
5. Test network_server deployment mode

### Medium-term (Within 1 month)
1. Deploy staging environment via Terraform
2. Migrate test_tenant to staging
3. Onboard first customer tenant
4. Set up billing alerts and cost tracking
5. Document disaster recovery procedures

---

## References

- [Terraform Configuration](terraform/README.md)
- [Tagging Strategy](terraform/TAGGING_STRATEGY.md)
- [Thing Groups Guide](terraform/THING_GROUPS_GUIDE.md)
- [Implementation Guide](SMDH_Infrastructure_Implementation.md)
- [Implementation Plan](SMDH_Implementation_Plan.md)
- [Snowflake Setup Guide](snowflake/README.md)
- [Deployment Checklist](../DEPLOYMENT_CHECKLIST.md)

---

**Last Updated:** 2025-12-01 08:36 UTC
**Maintained By:** Platform Team
