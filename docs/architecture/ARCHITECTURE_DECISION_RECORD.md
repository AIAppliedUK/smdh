# Architecture Decision Record (ADR)

Smart Manufacturing Data Hub (SMDH) - Architecture decisions, rationale, and trade-offs.

**Date:** November 2025
**Version:** 1.0

---

## ADR-001: Snowflake as Primary Data Warehouse

**Status:** ✅ ACCEPTED & IMPLEMENTED

### Decision
Use Snowflake as the primary data warehouse instead of alternatives (Redshift, BigQuery, self-managed).

### Context
SMDH needs to support:
- 30-40 tenants (multi-tenant isolation critical)
- 2.6M-3.9M rows/day (significant data volume)
- <5 minute analytics latency
- Real-time streaming (Kinesis integration)
- Complex transformations (power, state, cost calculations)

### Options Evaluated
1. **Snowflake** - Managed data warehouse with native Kinesis integration
2. **AWS Redshift** - Managed warehouse, less dynamic table support
3. **Google BigQuery** - Managed, but AWS-only project
4. **Self-managed (Postgres/etc)** - Too much operational overhead

### Decision Rationale
✅ **Strengths:**
- **Native Kinesis Integration:** Openflow connector enables direct streaming without Lambda
- **Dynamic Tables:** Real-time aggregations with automatic refresh (1-10 min lag)
- **Streams & Tasks:** Built-in CDC and ETL orchestration (no external scheduler needed)
- **Multi-Tenancy:** Separate databases per tenant with easy isolation
- **Scalability:** On-demand scaling without capacity planning
- **Time-to-Value:** Quick setup (days vs weeks), minimal DevOps needed
- **Cost Efficiency:** Pay-as-you-go, no idle capacity costs, efficient storage

⚠️ **Trade-offs:**
- Cloud lock-in (AWS/Snowflake ecosystem)
- Not suitable for sub-second latency (but we use dynamic tables for that)
- Query costs add up at scale (mitigated by good design)

### Implementation
- Enterprise edition (required for Dynamic Tables)
- eu-west-2 region (London, close to sensors)
- On-demand warehouses (auto-suspend after 5-10 minutes)
- Infrastructure database (smdh_infrastructure) for shared metadata
- Per-tenant databases (smdh_tenant_*) for isolation

### References
- [Detailed Design](docs/detailed-design/SMDH%20AWS%20design.md)
- [Cost Analysis](docs/architecture/COST-SUMMARY-FINAL.md)
- [Snowflake Capabilities](docs/architecture/snowflake-native-capabilities-analysis.md)

---

## ADR-002: AWS IoT Core for Device Connectivity

**Status:** ✅ ACCEPTED & IMPLEMENTED

### Decision
Use AWS IoT Core (MQTT broker) as the primary device communication protocol instead of HTTP or custom solutions.

### Context
Devices need:
- Secure, low-latency connectivity
- Multi-device (gateway and leaf devices)
- Certificate-based authentication
- Efficient bandwidth (IoT sensors often on cellular)
- Device fleet management

### Options Evaluated
1. **AWS IoT Core (MQTT)** - Native AWS service, certificate-based, Kinesis routing
2. **HTTPS/REST API** - Simpler but higher overhead
3. **AWS IoT Greengrass** - Edge processing (too complex for MVP)
4. **Custom MQTT broker** - Operational complexity

### Decision Rationale
✅ **Strengths:**
- **Native AWS Integration:** Direct routing to Kinesis via Rules Engine (no Lambda needed)
- **Security:** X.509 certificate authentication (stronger than API keys)
- **Multi-Tenancy:** IoT Policies enforce topic isolation (`smdh/{tenant_id}/*`)
- **Thing Management:** Hierarchical thing groups for device organization
- **Efficiency:** MQTT protocol (lower bandwidth than REST)
- **Logging:** Full audit trail in CloudWatch

⚠️ **Trade-offs:**
- MQTT requires certificate management (mitigated by Terraform automation)
- Device firmware must support MQTT (all our sensors do)
- Port 8883 (TLS) required (firewall consideration)

### Implementation
- 2 Thing Types: `LoRaWANGateway` and `DevTankOSM`
- Per-tenant IoT Policies (strict topic isolation)
- Automatic certificate generation via Terraform
- Rules Engine rule to route messages to Kinesis
- CloudWatch logging at DEBUG level

### References
- [Thing Groups Guide](infrastructure/terraform/THING_GROUPS_GUIDE.md)
- [IoT Architecture](docs/detailed-design/diagrams/SMDH_IoT_Core_Architecture.drawio)

---

## ADR-003: Amazon Kinesis for Data Streaming

**Status:** ✅ ACCEPTED & IMPLEMENTED

### Decision
Use Amazon Kinesis Data Streams (on-demand mode) for buffering and ordering messages from IoT Core to Snowflake.

### Context
Data flow needs:
- Buffering (temporary storage if Snowflake is down)
- Ordering (maintain sensor reading sequence)
- Durability (24-hour retention)
- Scalability (auto-scale with load)
- Low cost (on-demand better than provisioned)

### Options Evaluated
1. **Kinesis (on-demand)** - Fully managed, auto-scaling, per-request pricing
2. **Kinesis (provisioned)** - Fixed throughput (requires capacity planning)
3. **SQS** - Queue but not stream (loses ordering guarantee)
4. **Kafka (self-managed)** - Too much operational overhead
5. **Kinesis Firehose** - Only direct S3, less flexibility

### Decision Rationale
✅ **Strengths:**
- **On-Demand Mode:** Auto-scales, no capacity planning, pay-per-request
- **Ordering:** FIFO ordering per partition (by tenant_id)
- **Retention:** 24-hour default (configurable)
- **Snowflake Integration:** Openflow connector reads directly
- **Durability:** Replicated across 3 AZs
- **Monitoring:** Built-in CloudWatch metrics

⚠️ **Trade-offs:**
- On-demand pricing higher than provisioned (but cost-effective for variable load)
- 24-hour max retention (longer retention via S3 not needed for real-time)
- Partition key important for ordering (tenant_id chosen correctly)

### Implementation
- On-demand capacity mode (auto-scaling)
- 24-hour retention
- KMS encryption at rest
- CloudWatch alarms for iterator age and throughput
- Partition key: `tenant_id` (ensures all tenant data together)

### References
- [Kinesis Module](infrastructure/terraform/modules/kinesis/main.tf)
- [Cost Analysis](infrastructure/DEPLOYMENT_NOTES.md)

---

## ADR-004: Terraform for Infrastructure as Code

**Status:** ✅ ACCEPTED & IMPLEMENTED

### Decision
Use Terraform (HashiCorp) for all AWS infrastructure deployment instead of CloudFormation or CDK.

### Context
Need to:
- Manage 48+ AWS resources consistently
- Support multiple environments (dev, staging, prod)
- Enable reproducible deployments
- Maintain infrastructure version control
- Support rapid iteration

### Options Evaluated
1. **Terraform** - Open-source, multi-cloud, large ecosystem
2. **AWS CloudFormation** - Native AWS, AWS-only
3. **AWS CDK** - Infrastructure as code in Python/TypeScript
4. **Pulumi** - Similar to CDK, newer
5. **Manual AWS Console** - Not reproducible

### Decision Rationale
✅ **Strengths:**
- **Multi-Cloud:** Works with AWS, Snowflake, other providers
- **Ecosystem:** Large community, many modules, proven patterns
- **Readability:** HCL is human-readable (vs JSON CloudFormation)
- **State Management:** Explicit state file (S3 backend with DynamoDB locking)
- **Modules:** Reusable components (iot-core, kinesis, iam, etc)
- **Portability:** Same tool for AWS, Snowflake, future clouds

⚠️ **Trade-offs:**
- External tool (not native AWS)
- State file management critical (requires S3 + DynamoDB)
- Learning curve (vs point-and-click console)
- IAM permissions needed to deploy

### Implementation
- 6 modular components (iot-core, kinesis, iam, secrets, cloudwatch, tenant)
- S3 backend with DynamoDB locking for state
- Environment-specific tfvars files (dev, staging, prod)
- Terraform v1.0+ required
- AWS provider v5.0+ required

### References
- [Terraform README](infrastructure/terraform/README.md)
- [Root Configuration](infrastructure/terraform/main.tf)
- [Module Structure](infrastructure/terraform/modules/)

---

## ADR-005: Streamlit for Analytics Dashboard

**Status:** ✅ DESIGN COMPLETE, 🚧 IMPLEMENTATION IN PROGRESS

### Decision
Use Streamlit for the manufacturing analytics web portal instead of React/Vue or other frameworks.

### Context
Dashboard needs:
- Fast development (weeks, not months)
- Data scientist friendly (Python-based)
- Low infrastructure footprint
- Integration with Python ML models
- Multiple analytics pages (8 dashboards)
- Self-service UI customization

### Options Evaluated
1. **Streamlit** - Python-based, rapid prototyping, minimal DevOps
2. **React + REST API** - Flexible but requires backend development
3. **Power BI/Tableau** - Powerful but vendor lock-in
4. **Grafana** - Great for metrics, less suitable for business dashboards
5. **Django/Flask** - More control but slower development

### Decision Rationale
✅ **Strengths:**
- **Fast Development:** Dashboard features in hours vs days
- **Python Native:** Seamless integration with pandas, Snowpark, ML models
- **Minimal Backend:** No need for separate API (queries Snowflake directly)
- **Reactive UI:** Automatic data refresh on parameter changes
- **Caching:** Built-in @st.cache for performance
- **No Frontend Build:** Write Python, ship production app

⚠️ **Trade-offs:**
- Less flexible UI (compared to React)
- Scaling to 100+ concurrent users needs load balancing
- Mobile experience less polished
- Not suitable for highly customized UIs

### Implementation
- Streamlit 1.29+ with Snowflake connector
- 8 analytics dashboard pages
- Home/overview page with KPI summary
- Snowflake connection pooling for performance
- Docker containerization for deployment
- Deploy to AWS (ECS, Lambda, or managed app service)

### References
- [Streamlit Guide](applications/web-portal/STREAMLIT_DASHBOARD_GUIDE.md)
- [Dashboard Pages Design](applications/web-portal/STREAMLIT_DASHBOARD_PAGES.md)

---

## ADR-006: Multi-Tenant Isolation Strategy

**Status:** ✅ ACCEPTED & IMPLEMENTED

### Decision
Use database-level isolation for tenants (separate Snowflake databases per tenant) with policy enforcement at three layers (IoT, Kinesis, Snowflake).

### Context
Platform supports 30-40 tenants with strict requirements:
- Tenant data must be isolated (regulatory, security)
- Noisy neighbor problem (one tenant's load shouldn't affect others)
- Different retention policies per tenant
- Audit trail per tenant
- Different hardware (warehouse sizes) per tenant

### Options Evaluated
1. **Database-Level** - Separate DB per tenant (chosen)
2. **Schema-Level** - Shared DB, separate schemas per tenant
3. **Row-Level Security** - Single schema with RLS (complex, slower)
4. **Application-Level** - Enforce in app code (risky, no DB enforcement)

### Decision Rationale
✅ **Chosen: Database-Level**
- **Strong Isolation:** Complete separation at database level
- **Audit Trail:** Separate tables per tenant for compliance
- **Performance:** No row filtering overhead
- **Cost Control:** Per-tenant warehouse sizing
- **Compliance:** GDPR/data residency easier to prove
- **Recovery:** Can restore single tenant without affecting others

⚠️ **Trade-offs:**
- More databases to manage (mitigated by automation)
- Higher Snowflake costs vs shared model (but cleaner security)

### Implementation
- `smdh_infrastructure` shared database (metadata only)
- `smdh_tenant_{id}` dedicated database per tenant
- IoT policies enforce topic isolation (`smdh/{tenant_id}/*`)
- Kinesis partition key = tenant_id (ensures data stays together)
- Snowflake pipes configured per tenant
- RBAC roles per tenant database

### References
- [Snowflake Setup](infrastructure/snowflake/README.md)
- [Tenant Module](infrastructure/terraform/modules/tenant/main.tf)
- [Multi-Tenancy Architecture](docs/detailed-design/diagrams/SMDH_Multi_Tenancy_Architecture.drawio)

---

## ADR-007: Snowflake Dynamic Tables for Real-Time Aggregations

**Status:** ✅ ACCEPTED & IMPLEMENTED (Partially)

### Decision
Use Snowflake Dynamic Tables (automatic refresh) for real-time aggregations instead of manual tasks or external schedulers.

### Context
Dashboard needs:
- Fresh data (<5 minute latency for analytics)
- Real-time views (<1 second ideal)
- Automatic refresh without manual intervention
- No complex scheduling logic

### Options Evaluated
1. **Dynamic Tables** - Auto-refresh with refresh lag guarantee (chosen)
2. **Scheduled Tasks** - Manual scheduling with cron-like syntax
3. **External Scheduler** - Airflow, Dagster (too complex for MVP)
4. **Materialized Views** - Manual refresh via triggers
5. **Transient Tables** - No refresh, manual rebuild

### Decision Rationale
✅ **Strengths:**
- **Automatic Refresh:** Snowflake manages refresh automatically
- **Lazy Evaluation:** Only refreshes if source data changes
- **Guaranteed Lag:** Specify maximum lag (e.g., 5 minutes)
- **Dependencies:** Automatic DAG detection (no manual ordering)
- **Efficient:** Only updates changed rows
- **Simple:** No complex scheduling logic

⚠️ **Trade-offs:**
- Requires Enterprise edition
- Not available for all operations (CTEs, external functions)
- Minimum 1-minute refresh lag (but acceptable for analytics)

### Implementation
- 6+ dynamic tables for dashboard data
- 1-10 minute refresh lag (depending on use case)
- Automatic dependency detection
- Dashboard queries read from dynamic tables
- Cost: Compute only on refresh (minimal compared to task queues)

### References
- [Dynamic Tables SQL](infrastructure/snowflake/tenant/15_create_dynamic_tables.sql)
- [Snowflake Documentation](https://docs.snowflake.com/en/user-guide/dynamic-tables-about.html)

---

## ADR-008: SSL/TLS Certificates via Terraform

**Status:** ✅ ACCEPTED & IMPLEMENTED

### Decision
Generate X.509 certificates automatically via Terraform (using AWS IoT Core) instead of manual certificate management.

### Context
Each gateway device needs:
- X.509 certificate (for MQTT authentication)
- Private key (stored securely)
- Certificate distribution to devices
- Certificate rotation strategy

### Options Evaluated
1. **AWS IoT Core Auto-Generate** - Terraform creates via aws_iot_certificate (chosen)
2. **Manual Generation** - Openssl commands (error-prone)
3. **Self-Signed** - Simpler but less secure
4. **Third-Party CA** - Overkill for internal devices

### Decision Rationale
✅ **Strengths:**
- **Automatic:** Generated as part of Terraform apply
- **Integrated:** Direct AWS IoT Core certificates
- **Secure:** AWS manages private keys initially
- **Reproducible:** Same process every time
- **Scalable:** Create 100 devices in seconds

⚠️ **Trade-offs:**
- Certificates stored in Terraform state (sensitive)
- Must protect state file (S3 + encryption + IAM)
- Manual secret rotation needed (future enhancement)

### Implementation
- `aws_iot_certificate` resource generates certificates
- Private key extracted to Secrets Manager or local secure storage
- Certificate distributed to devices during provisioning
- Rotation via separate process (future)
- Test certificates included for testing

### References
- [Tenant Module](infrastructure/terraform/modules/tenant/main.tf)
- [Certificate Helper Script](tests/scripts/cert-helper.sh)

---

## ADR-009: on-demand Kinesis vs Provisioned Capacity

**Status:** ✅ ACCEPTED & IMPLEMENTED

### Decision
Use Kinesis on-demand mode (auto-scaling) instead of provisioned capacity.

### Context
Data volume varies:
- Peak: 3.9M messages/day (peak hours)
- Valley: 2.6M messages/day (quiet hours)
- Cannot predict exact throughput (new tenants, seasonal patterns)

### Options Evaluated
1. **On-Demand Mode** - Auto-scale, per-request pricing (chosen)
2. **Provisioned Mode** - Fixed throughput, hourly pricing
3. **Auto-Scaling (Provisioned)** - Hybrid, still requires planning

### Decision Rationale
✅ **Strengths:**
- **Predictability:** No capacity planning needed
- **Cost Efficiency:** Only pay for what you use
- **Automatic Scale:** Handles spikes without intervention
- **No Throttling:** No fear of exhausting capacity

⚠️ **Trade-offs:**
- Per-request pricing higher than provisioned (for steady loads)
- Publish quota: 4,000 records/second (sufficient for 40 tenants)
- GetRecords limit: 10,000 records/request

### Implementation
- StreamSpecification: ON_DEMAND mode
- Retention period: 24 hours
- Shard auto-adjustment: Automatic
- No manual scaling policies needed

### References
- [Kinesis Module](infrastructure/terraform/modules/kinesis/main.tf)
- [AWS Kinesis Pricing](https://aws.amazon.com/kinesis/data-streams/pricing/)

---

## ADR-010: Secrets Manager for Credential Storage

**Status:** ✅ ACCEPTED & IMPLEMENTED

### Decision
Use AWS Secrets Manager for storing Snowflake credentials and sensitive configuration instead of environment variables or Terraform state.

### Context
Platform needs to:
- Store Snowflake private key securely
- Manage API credentials
- Rotate secrets automatically
- Audit credential access

### Options Evaluated
1. **Secrets Manager** - Managed secret storage with rotation (chosen)
2. **Parameter Store** - SSM parameter storage (simpler but less features)
3. **Environment Variables** - Simple but exposed in logs
4. **Terraform State** - Not secure (state contains secrets)
5. **Encrypted Files** - Manual management

### Decision Rationale
✅ **Strengths:**
- **Encryption:** AES-256 encryption at rest
- **Rotation:** Automatic rotation capabilities
- **Audit Trail:** CloudTrail logs all access
- **Lambda Integration:** Easy retrieval in serverless functions
- **Database Credentials:** Built-in support for Snowflake/RDS secrets

⚠️ **Trade-offs:**
- Small monthly cost per secret ($0.40)
- Additional API calls to retrieve secrets (minimal overhead)
- Rotation lambda needed for auto-rotation

### Implementation
- Secret: Snowflake private key (smdh-snowflake-private-key)
- Secret: Snowflake connection config (smdh-snowflake-config)
- KMS encryption (default AWS key)
- 30-day recovery window on deletion
- Rotation disabled initially (future enhancement)

### References
- [Secrets Manager Module](infrastructure/terraform/modules/secrets-manager/main.tf)

---

## Summary of Key Decisions

| Component | Choice | Alternative | Reason |
|-----------|--------|------------|--------|
| Data Warehouse | Snowflake | Redshift, BigQuery | Kinesis native integration, Dynamic Tables |
| Device Protocol | MQTT (IoT Core) | HTTPS | Certificate security, efficiency, Rules Engine routing |
| Streaming | Kinesis (on-demand) | Kafka, SQS | AWS native, auto-scaling, Snowflake integration |
| IaC Tool | Terraform | CloudFormation, CDK | Multi-cloud, ecosystem, readability |
| Dashboard | Streamlit | React, Power BI | Fast development, Python-native, minimal backend |
| Isolation | Database-level | Row-level | Stronger security, better performance, simpler compliance |
| Real-time | Dynamic Tables | Scheduled Tasks | Automatic refresh, self-managing, efficient |
| Certificates | Terraform Auto-Gen | Manual | Reproducible, scalable, integrated |

---

## How to Use This Document

1. **For New Team Members:** Review this document to understand why architectural decisions were made
2. **For Architecture Reviews:** Use as reference for consistent decision-making
3. **For Alternatives:** If considering replacing a component, review the ADR first
4. **For Documentation:** Keep updated as new decisions are made

---

## How to Add New ADRs

When making significant architectural decisions:

1. Create a new ADR-### section
2. Include: Decision, Context, Options, Rationale, Trade-offs, Implementation
3. Add to summary table at bottom
4. Update date and version
5. Reference implementation in code comments

---

**Maintainers:** Platform Team
**Last Updated:** November 22, 2025
