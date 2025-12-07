# Known Limitations & Constraints

**Status:** Current limitations of SMDH platform (November 22, 2025)
**Version:** 1.0

This document lists known constraints, workarounds, and planned resolutions.

---

## 🔴 CRITICAL LIMITATIONS

None currently identified for the core infrastructure (AWS IoT Core + Kinesis + Snowflake).

The platform is production-ready for:
- Device connectivity (MQTT via AWS IoT Core)
- Data ingestion (Kinesis streaming)
- Data warehouse (Snowflake with multi-tenancy)
- Real-time ETL (Streams, Tasks, Dynamic Tables)

---

## 🟡 IMPORTANT LIMITATIONS

### 1. Snowflake Dynamic Tables Min Refresh Lag: 1 Minute

**Impact:** Real-time dashboards have ~1-minute latency minimum
**Affected Components:** Dashboard views, real-time aggregations
**Workaround:** Use Snowflake Streams + Tasks for sub-minute latency if needed (future)
**Resolution:** Planned for Phase 3 (advanced stream processing)

**Details:**
```
- Dynamic tables automatically refresh at intervals
- Minimum refresh interval: 1 minute
- This means dashboard data is 1-10 minutes old (depending on query)
- Acceptable for manufacturing analytics (not high-frequency trading)
- If true real-time needed: implement Flink on EMR (Phase 3)
```

### 2. Snowflake Constraint Support Limitations

**Impact:** Database constraints not enforced at data layer
**Affected Components:** Data validation
**Workaround:** Application-layer validation, procedures, and triggers

**Details:**
```sql
-- ✅ SUPPORTED
PRIMARY KEY
FOREIGN KEY (with NOT ENFORCED clause - metadata only)
NOT NULL
UNIQUE

-- ❌ NOT SUPPORTED
CHECK constraints (e.g., power_kw > 0)
```

**Solution Implemented:**
- All CHECK constraints removed from SQL
- Data validation implemented in Python procedures
- Business logic enforced at application layer
- Comments document intended constraints

**Reference:** [Snowflake README](infrastructure/snowflake/README.md#-snowflake-compatibility)

### 3. Kinesis Throughput Limits

**Impact:** Burst throughput limited in on-demand mode
**Affected Components:** Data ingestion during peak loads
**Limits:**
- Max publish rate: 4,000 records/second
- Max getRecords: 10,000 records/request
- Max connections: 2,000 concurrent

**Workaround:** For 40 tenants, this allows ~100 messages/second per tenant (sufficient)

**Details:**
```
40 tenants × 100 msg/sec = 4,000 msg/sec = within limit ✅

Peak scenario (all tenants at 1,000 msg/sec):
40,000 msg/sec would exceed limit → mitigate by:
1. Increase retention to buffer spikes
2. Add second Kinesis stream (sharding by tenant_id)
3. Upgrade to provisioned capacity
```

**Resolution:** Monitor in production; upgrade if needed (Phase 2)

### 4. IoT Core Per-Region Limits

**Impact:** Connected devices limited per region
**Affected Components:** Device management
**Limits:**
- Connected devices limit: 500,000 per region
- MQTT messages: 1 million/second per region (soft limit)

**Workaround:** For SMDH pilot (40 tenants, ~500 devices), well within limits

**Details:**
```
40 tenants × 5 sites × 5 gateways = 1,000 gateways (well below 500k limit) ✅

If scaling to 1M devices:
- Use multiple AWS regions (federation)
- Implement cross-region Kinesis replication
```

**Resolution:** Revisit if scaling to large IoT networks (Phase 3+)

### 5. Terraform Certificate Storage in State

**Impact:** Private keys visible in Terraform state file
**Affected Components:** Security, secret management
**Workaround:**
- State file stored in encrypted S3
- Access restricted via IAM
- Extract certificates to Secrets Manager after deployment
- Rotate manually as needed

**Details:**
```bash
# Certificates in state (sensitive)
terraform state show module.tenant.aws_iot_certificate.gateways

# Best practice: Extract and secure
terraform output -json tenant_certificate_pems | \
  jq -r '.["test_tenant"]["site_001"]["gw_001"]' | \
  aws secretsmanager create-secret --name iot-cert-test-tenant-site001-gw001
```

**Resolution:** Implement Secrets Manager rotation (Phase 2)

---

## 🟠 MODERATE LIMITATIONS

### 6. Streamlit Single-Threaded Application

**Impact:** Cannot handle 100+ concurrent users with single instance
**Affected Components:** Web portal scalability
**Workaround:**
- Deploy multiple Streamlit instances
- Use load balancer (AWS ALB or CloudFlare)
- Cache dashboard data (Streamlit @st.cache)
- Optimize Snowflake queries

**Details:**
```
Single Streamlit instance capacity: ~20-40 concurrent users
For 100+ users:
- Deploy on ECS with 3-5 instances
- Load balancer routes to instances
- Share session cache (Redis or DynamoDB)
```

**Resolution:** Implement load-balanced deployment (Phase 2)

### 7. No API Gateway Yet

**Impact:** Programmatic access to data not available
**Affected Components:** Third-party integrations, mobile apps
**Workaround:** Direct Snowflake JDBC/ODBC access (not recommended for public APIs)
**Resolution:** REST API Gateway (Phase 2)

**Details:**
```
Current: Dashboard → Snowflake (direct)
Future: Dashboard ← REST API → Snowflake
        Mobile App ← REST API → Snowflake
        3rd-party ← REST API → Snowflake
```

### 8. No Mobile Application Yet

**Impact:** Operators must use web portal or Snowflake SQL
**Affected Components:** Field operations
**Workaround:** Responsive web design, mobile-friendly Streamlit
**Resolution:** Native mobile app (Phase 3)

### 9. No Machine Learning Models Yet

**Impact:** Advanced analytics (anomaly detection, predictive maintenance) not available
**Affected Components:** Insights, notifications
**Workaround:** Manual analysis or third-party tools
**Resolution:** SageMaker/Snowpark ML models (Phase 3)

### 10. Snowflake Storage Costs Growing

**Impact:** Costs increase linearly with data volume
**Affected Components:** Operating budget
**Workaround:**
- Set appropriate data retention (730 days default)
- Archive old data to S3 (future)
- Compress data via native Snowflake compression
- Optimize column types (avoid VARCHAR(max))

**Details:**
```
Estimated costs for 40 tenants, 2.6M rows/day:
- 1 month: $500-800
- 1 year: $6k-10k
- Multi-year retention: Plan accordingly

Mitigation:
- Monthly cost monitoring (implemented)
- Auto-suspend warehouses (implemented)
- Resource monitors with quotas (implemented)
```

**Resolution:** Archival strategy (Phase 2-3)

---

## 🔵 MINOR LIMITATIONS

### 11. Requires eu-west-2 Region

**Impact:** Cannot deploy outside London region without changes
**Affected Components:** Geographic deployment
**Workaround:** Modify terraform.tfvars to different region
**Resolution:** Multi-region setup (Phase 3+)

### 12. Snowflake Enterprise Edition Required

**Impact:** Higher costs than Standard edition
**Affected Components:** Pricing, feature access
**Workaround:** None (Dynamic Tables require Enterprise)
**Impact:** Non-negotiable for required features

### 13. Manual External ID Generation

**Impact:** Extra step in deployment
**Affected Components:** Onboarding process
**Workaround:** Run `uuidgen` once during setup
**Resolution:** Terraform could auto-generate (minor improvement)

### 14. Sensor Data Format Rigid

**Impact:** Adding new sensor types requires schema changes
**Affected Components:** Extensibility
**Workaround:**
- Add to raw JSON payload (can be parsed in tasks)
- Extend normalized tables with new columns
- Update MART views

**Resolution:** Flexible schema design (Phase 2)

### 15. No Automated Certificate Rotation

**Impact:** Certificates never expire (AWS default)
**Affected Components:** Security best practices
**Workaround:** Manual rotation process (future automation)
**Resolution:** Implement automated rotation (Phase 2)

---

## ⚠️ PLANNED ENHANCEMENTS (Not Limitations Yet)

### Features Not Yet Implemented

These are planned but not yet built:

| Feature | Target Phase | Impact |
|---------|--------------|--------|
| REST API Gateway | Phase 2 | Needed for 3rd-party integrations |
| Mobile App | Phase 3 | Mobile field operations |
| ML Models | Phase 3 | Advanced analytics |
| Grafana Dashboards | Phase 3 | Real-time monitoring |
| Apache Flink | Phase 3 | Complex stream processing |
| QuickSight BI | Phase 3+ | Executive dashboards |
| Certificate Rotation | Phase 2 | Security best practice |
| Data Archival | Phase 2-3 | Cost optimization |
| Multi-Region | Phase 3+ | Geo-distributed deployment |

---

## ✅ WORKAROUNDS & MITIGATIONS

### For Constraints Not Enforced in Database

```sql
-- Current approach: Stored procedures with validation
CREATE OR REPLACE PROCEDURE validate_power_metrics()
RETURNS TABLE(validation_result STRING)
LANGUAGE SQL
AS
BEGIN
  SELECT 'PASSED' AS validation_result
  FROM normalized.power_metrics
  WHERE real_power_kw < 0  -- CHECK: power_kw > 0
     OR apparent_power_kva < 0
     OR power_factor < 0 OR power_factor > 1
  HAVING COUNT(*) = 0;
END;

-- Call daily
CALL validate_power_metrics();
```

### For Single-Instance Streamlit Scaling

```python
# Solution: Load-balanced deployment
# In Docker Compose or Kubernetes:
version: '3'
services:
  streamlit-1:
    image: smdh-dashboard:latest
    environment:
      REPLICA_ID: 1
    ports:
      - "8501:8501"

  streamlit-2:
    image: smdh-dashboard:latest
    environment:
      REPLICA_ID: 2
    ports:
      - "8502:8501"

  loadbalancer:
    image: nginx:latest
    ports:
      - "80:80"
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf
```

### For Certificate Management

```bash
# Best practice: Rotate certificates quarterly
# 1. Generate new certificate
# 2. Deploy to devices
# 3. Update IoT policy
# 4. Archive old certificate
# 5. Document in Secrets Manager

# Script (to be implemented):
./scripts/rotate-certificates.sh --tenant-id test_tenant --days-old 90
```

---

## 📞 Reporting Issues

If you discover additional limitations:

1. Document the limitation clearly
2. Determine the impact (critical/major/minor)
3. Propose workaround (if any)
4. Estimate resolution effort
5. Add to this document
6. Create GitHub issue for tracking

Template:
```markdown
### X. [Short Title]

**Impact:** What breaks?
**Affected Components:** Which parts?
**Workaround:** How to avoid?
**Resolution:** When will it be fixed?

**Details:**
[Detailed description]
```

---

## 🔄 Limitation Lifecycle

```
Limitation Identified
  ↓
Documented (this file)
  ↓
Evaluated for fix priority
  ↓
Placed in Feature Roadmap
  ↓
Implemented in Phase N
  ↓
Removed from Known Limitations
  ↓
Added to IMPLEMENTATION_STATUS.md (completed)
```

---

## Related Documents

- [Implementation Status](IMPLEMENTATION_STATUS.md) - What's built
- [Feature Roadmap](FEATURE_ROADMAP.md) - What's coming
- [Architecture Decisions](ARCHITECTURE_DECISION_RECORD.md) - Why decisions were made
- [Deployment Checklist](DEPLOYMENT_CHECKLIST.md) - How to deploy

---

**Last Updated:** November 22, 2025
**Maintainer:** Platform Team
**Review Frequency:** Monthly
