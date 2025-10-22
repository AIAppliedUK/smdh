# Smart Manufacturing Data Hub (SMDH) - Complete Architecture Overview

## Document Information
- **Version**: 2.0
- **Date**: October 2025
- **Status**: Production-Ready Architecture
- **AWS Region**: eu-west-2 (London)

---

## Executive Summary

This document provides a comprehensive overview of the Smart Manufacturing Data Hub (SMDH) architecture, a cloud-native, multi-tenant IoT platform designed to support 30-40 small and medium-sized enterprises (SMEs) in manufacturing. The platform integrates three critical use cases while maintaining a unified, scalable infrastructure.

### Supported Use Cases

1. **Machine Utilization Analytics (MUA)** - Real-time monitoring of machine performance, energy consumption, and operational efficiency
2. **Air Quality Management Analytics (AQMA)** - Environmental monitoring to ensure worker safety and regulatory compliance
3. **Job Location Tracking** - RFID/barcode-based tracking of products through manufacturing workflows

---

## Architecture Overview

### Key Platform Metrics

| Metric | Value |
|--------|-------|
| **Data Volume** | 2.6M-3.9M rows per day |
| **Tenants** | 30-40 SME companies |
| **Concurrent Users** | 20-40 users |
| **Dashboards** | 60-120 specialized views |
| **Analytics Latency** | <5 minutes |
| **Real-time Latency** | <1 second |
| **Isolation Model** | Row-Level Security (RLS) |
| **Uptime SLA** | 99.9% |
| **Data Retention** | 90 days time travel |

---

## Data Sources Layer

The platform ingests data from multiple source types across the factory floor:

### 1. Machine Utilization Monitoring (MUA)

**Sensor Types:**
- **Power Monitoring Sensors**: Track electrical current and power consumption in real-time (1Hz frequency)
- **Machine State Sensors**: Monitor operational status, cycle counts, and downtime events (1Hz)
- **Smart Energy Meters**: Capture voltage, current, power factor, and kWh consumption (15-second intervals)

**Data Protocol:** MQTT/LoRaWAN over TLS
**Analytics Enabled:**
- Overall Equipment Effectiveness (OEE)
- Machine idle vs. operating time
- Energy cost estimation using Time-of-Use (ToU) tariffs
- Predictive maintenance alerts
- Production clustering and pattern analysis

### 2. Air Quality Management (AQMA)

**Sensor Types:**
- **CO2 Sensors**: Monitor carbon dioxide levels (1-minute intervals)
- **VOC Sensors**: Track volatile organic compounds for worker safety
- **Particulate Matter Sensors**: Measure PM1, PM2.5, PM4, and PM10 concentrations
- **Temperature/Humidity Sensors**: Environmental comfort monitoring

**Data Protocol:** MQTT/LoRaWAN
**Volume:** 10-15 sensors per facility
**Analytics Enabled:**
- Regulatory compliance tracking (HSE standards)
- Worker health and safety alerts
- Ventilation system optimization
- Trend analysis and forecasting
- Anomaly detection for air quality events

### 3. Job Location Tracking

**Data Collection:**
- **RFID Readers**: Event-driven scanning at production checkpoints
- **Barcode Scanners**: Manual and automated product tracking
- **Location Tags**: Track products through manufacturing stages

**Volume:** 500-2,000 scans per day per facility
**Data Protocol:** HTTP REST API or MQTT
**Production Locations Tracked:**
- Complete
- Punched
- Waiting
- Local Painting
- Drying
- Stored

**Analytics Enabled:**
- Production cycle time analysis
- Bottleneck identification
- Work-in-progress (WIP) tracking
- Production flow optimization
- Material inventory management

### 4. Legacy System Integration

**File Upload Support:**
- CSV and Excel files
- PDF reports
- JSON data exports
- Manual web portal uploads

**Volume:** 5-50 GB per company
**Frequency:** Weekly to monthly batch uploads

---

## AWS Cloud Architecture

### Ingestion & Routing Layer

**AWS IoT Core**
- MQTT broker for real-time sensor data ingestion
- Device authentication using X.509 certificates
- Supports MQTT v3.1.1 and v5
- Persistent connections with automatic reconnection
- Device shadows for state management

**IoT Rules Engine**
- Message routing based on topic patterns
- Data transformation and filtering
- Error handling with Dead Letter Queue (DLQ)
- Routes data to Kinesis Data Firehose

**API Gateway**
- REST API for file uploads and manual data submission
- Request throttling and rate limiting
- Integration with Lambda for processing
- Pre-signed URL generation for large file uploads
- WebSocket support for real-time updates

**Amazon EventBridge**
- Event-driven orchestration for RFID scan events
- Scheduled batch job triggers
- Alert notification routing
- Cross-service integration hub

**AWS Glue Schema Registry**
- Schema versioning and evolution
- Data contract enforcement
- Compatibility checking
- Centralized metadata management

---

### Stream Processing Layer

**Amazon Kinesis Data Streams**
- Real-time data ingestion buffer
- Parallel shard processing
- Data retention up to 7 days

**Amazon Kinesis Data Firehose**
- Near real-time data delivery to S3
- Automatic buffering and compression
- Data transformation via Lambda

**Apache Flink on Amazon EMR**
- Real-time stream processing for MUA and AQMA use cases
- Complex event processing
- Windowed aggregations (5-minute windows)
- Stateful stream processing

**AWS Lambda Functions**
- Data transformation and enrichment
- Schema validation
- Error handling and retry logic
- Serverless execution model

**AWS Glue ETL Jobs**
- Batch processing for historical data
- Data quality checks using Great Expectations
- Partition management
- Data cataloging

---

### Data Storage Layer

**Amazon S3 (Multiple Buckets)**
- **Raw Data Bucket**: Untransformed sensor data
- **Staging Bucket**: Validated and transformed data ready for Snowflake
- **Archive Bucket**: S3 Glacier for long-term retention

**Storage Features:**
- Server-side encryption (SSE-KMS)
- Versioning enabled
- Lifecycle policies for cost optimization
- Cross-region replication for disaster recovery

**Amazon DynamoDB**
- Metadata storage for tenant configuration
- User preferences and dashboard settings
- Device registry information

**Amazon RDS Aurora PostgreSQL**
- Web portal application database
- User authentication and authorization data
- Multi-AZ deployment for high availability
- Automated backups

---

### Data Warehouse & Analytics Layer

**Snowflake Multi-Tenant Data Warehouse**
- **Architecture**: Centralized with logical separation
- **Tenant Isolation**: Row-Level Security (RLS) using tenant_id
- **Schemas**: 30-40 tenant-specific schemas
- **Virtual Warehouses**: Separate compute for different workloads
  - XS for portal queries
  - S-M for analytics
  - L for batch processing
- **Features**:
  - Time Travel (90 days)
  - Zero-copy cloning
  - Data sharing capabilities
  - Automatic scaling
  - Consumption-based pricing

**Data Pipeline:**
- Snowpipe for continuous auto-ingestion from S3
- COPY commands for batch loads
- Streams for change data capture
- Tasks for scheduled transformations

**Analytics Tools:**

1. **Amazon QuickSight**
   - Primary BI platform
   - SPICE engine for fast queries
   - Embedded dashboards in web portal
   - Row-level security integration
   - Mobile app support

2. **Grafana**
   - Real-time monitoring dashboards
   - OpenSmartMonitor integration
   - Alert visualization
   - Time-series data display

3. **Power BI Embedded**
   - Advanced analytics for power users
   - DirectQuery to Snowflake
   - Custom visualizations
   - Excel integration

4. **Amazon Athena**
   - Ad-hoc SQL queries on S3
   - Serverless query engine
   - Cost-effective for exploratory analysis

**Amazon SageMaker**
- Machine learning model development
- Gaussian Mixture Models (GMM) for MUA
- DBSCAN clustering for production analysis
- Anomaly detection for AQMA
- Predictive maintenance models

---

### Application & Presentation Layer

**Amazon CloudFront**
- Global content delivery network (CDN)
- HTTPS-only distribution
- Origin access control for security
- Cache optimization for static assets

**Application Load Balancer (ALB)**
- HTTPS termination
- Health checks for container instances
- Path-based routing
- WebSocket support

**AWS WAF & Shield**
- DDoS protection (Shield Standard)
- SQL injection prevention
- Cross-site scripting (XSS) protection
- Rate limiting rules
- Geo-blocking capabilities

**Amazon ECS on Fargate**
- Serverless container orchestration
- React 18+ TypeScript application
- Auto-scaling based on CPU/memory
- No infrastructure management

**Web Application Features:**
- **Material-UI (MUI)** framework
- **Dashboard Hub**: Embedded analytics from QuickSight and Power BI
- **Alert Manager**: Real-time threshold alerts and notifications
- **Report Builder**: Self-service report generation
- **Admin Console**: Tenant and user management

**Amazon Cognito**
- User authentication and authorization
- User pools for tenant users
- Single Sign-On (SSO) support
- Multi-Factor Authentication (MFA)
- Social identity provider integration
- SAML 2.0 federation

**Amazon Route 53**
- DNS management
- Health checks for failover
- Geo-routing capabilities
- Domain registration

**Notification Services:**
- **Amazon SES**: Email notifications for alerts and reports
- **Amazon SNS**: SMS and push notifications for critical alerts

---

### Security, Monitoring & Governance Layer

**Amazon CloudWatch**
- **Logs**: Centralized log aggregation from all services
- **Metrics**: Custom and default metrics monitoring
- **Alarms**: Automated alerting for threshold breaches
- **Dashboards**: Operational visibility

**AWS CloudTrail**
- API call auditing
- Compliance logging
- Security analysis
- Troubleshooting

**AWS Secrets Manager**
- Database credentials rotation
- API keys management
- Certificate storage
- Integration with RDS and ECS

**AWS Key Management Service (KMS)**
- Customer Managed Keys (CMK)
- Encryption at rest for S3, RDS, DynamoDB
- Envelope encryption
- Key rotation policies

**Amazon GuardDuty**
- Intelligent threat detection
- ML-powered security monitoring
- VPC Flow Log analysis
- DNS query log analysis

**AWS Systems Manager**
- Parameter Store for configuration
- Session Manager for secure access
- Patch management
- Maintenance windows

**AWS Config**
- Resource configuration tracking
- Compliance monitoring
- Configuration change notifications
- Remediation actions

**Great Expectations**
- Data quality validation framework
- Custom expectation suites per use case
- Integration with Glue ETL
- Data profiling and documentation

---

## Network Architecture

**VPC Configuration:**
- CIDR Block: 10.0.0.0/16
- Multi-AZ deployment across eu-west-2a and eu-west-2b

**Subnets:**

**Public Subnets** (ALB, NAT Gateways)
- 10.0.1.0/24 (AZ1)
- 10.0.2.0/24 (AZ2)

**Private Subnets** (ECS, RDS, Lambda)
- 10.0.10.0/24 (AZ1)
- 10.0.20.0/24 (AZ2)

**VPC Endpoints:**
- S3 Gateway Endpoint (no data transfer charges)
- PrivateLink to Snowflake (private connectivity)
- Interface Endpoints for AWS services

**Internet Gateway**
- Single IGW for VPC internet access

**NAT Gateways**
- One per AZ for high availability
- Outbound internet access for private subnets

---

## Use Case-Specific Architecture Details

### Machine Utilization Analytics (MUA)

**Data Flow:**
1. Power sensors collect current/voltage data at 1Hz
2. Data transmitted via MQTT to AWS IoT Core
3. IoT Rules Engine routes to Kinesis Data Streams
4. Flink processes stream for:
   - State classification (idle vs. operating)
   - Energy consumption calculation
   - OEE metrics computation
5. Results written to S3 staging
6. Snowpipe loads into Snowflake
7. QuickSight dashboards display KPIs

**Machine Learning Pipeline:**
- Gaussian Mixture Model (GMM) for automatic threshold detection
- DBSCAN clustering for production pattern analysis
- Training on 2+ weeks of historical data
- Model versioning in SageMaker

**Key Dashboards:**
- Real-time machine status
- Energy consumption by shift/day
- OEE trending
- Cost analysis with ToU tariffs
- Maintenance prediction alerts

### Air Quality Management Analytics (AQMA)

**Data Flow:**
1. Environmental sensors collect air quality data (1-minute intervals)
2. Data transmitted via MQTT/LoRaWAN to IoT Core
3. Real-time processing checks against thresholds
4. EventBridge triggers alerts if thresholds exceeded
5. Historical data aggregated in Snowflake
6. Grafana displays real-time monitoring
7. QuickSight provides compliance reports

**Alert Thresholds (Configurable):**
- CO2: >1000 ppm (warning), >5000 ppm (critical)
- PM2.5: >35 μg/m³ (warning), >150 μg/m³ (critical)
- VOC: >220 ppb (warning), >660 ppb (critical)
- Temperature: <16°C or >30°C (warning)

**Compliance Reporting:**
- HSE (Health and Safety Executive) standards
- Workplace Exposure Limits (WELs)
- Indoor air quality guidelines
- Automated monthly reports

### Job Location Tracking

**Data Flow:**
1. RFID readers/barcode scanners capture location events
2. REST API call to API Gateway
3. EventBridge processes event
4. Lambda enriches with product metadata
5. DynamoDB stores real-time WIP status
6. Historical events written to S3 and Snowflake
7. Custom dashboards show production flow

**Analytics:**
- Cycle time calculation between locations
- Bottleneck identification (waiting/drying stages)
- Production throughput by product type
- Material requirements planning
- Inventory tracking

**Visualizations:**
- Sankey diagrams for production flow
- Heatmaps for location dwell times
- Gantt charts for job progression
- Real-time WIP counts by location

---

## Multi-Tenancy Implementation

### Tenant Isolation Strategy

**Data Layer:**
- Snowflake RLS using `tenant_id` column
- Separate schemas per tenant with shared tables
- Views with RLS policies enforced
- Cross-tenant queries explicitly disabled

**Application Layer:**
- Cognito user groups per tenant
- API Gateway authorizers validate tenant scope
- ECS tasks receive tenant context in headers
- DynamoDB uses composite keys (tenant_id + item_id)

**Dashboard Layer:**
- QuickSight row-level security rules
- Power BI RLS roles per tenant
- Grafana organization separation
- Embedded URLs with tenant parameters

### Tenant Onboarding Process

1. **Tenant Registration**
   - Admin creates tenant in portal
   - Snowflake schema provisioned
   - Cognito user pool group created
   - S3 bucket prefix allocated

2. **Device Registration**
   - IoT Core thing provisioned
   - X.509 certificate generated
   - MQTT topic permissions set
   - Device shadow initialized

3. **User Provisioning**
   - Users invited via email
   - Cognito accounts created
   - Role-based access control (RBAC) assigned
   - Dashboard access configured

4. **Dashboard Configuration**
   - Template dashboards cloned
   - Tenant-specific customizations applied
   - Alert thresholds configured
   - Report schedules set up

---

## Security Architecture

### Encryption

**In Transit:**
- TLS 1.2+ for all API communications
- MQTT over TLS for IoT devices
- HTTPS-only for web traffic
- PrivateLink for Snowflake (no internet exposure)

**At Rest:**
- S3 server-side encryption (SSE-KMS)
- RDS encryption with KMS
- DynamoDB encryption
- EBS volume encryption
- Snowflake encryption (customer-managed keys)

### Authentication & Authorization

**Identity Management:**
- AWS Cognito for user authentication
- SAML 2.0 for enterprise SSO
- MFA required for admin accounts
- Password policies enforced

**Access Control:**
- IAM roles with least privilege principle
- Service-to-service authentication via IAM roles
- API Gateway authorizers for tenant validation
- Resource-based policies for S3, DynamoDB

### Network Security

**Perimeter Security:**
- WAF rules for common attack patterns
- Shield Standard for DDoS protection
- Security groups with minimal required access
- Network ACLs for subnet-level control

**Internal Security:**
- Private subnets for application and data tiers
- No public IPs on ECS tasks or RDS
- VPC endpoints to avoid internet routing
- Flow logs enabled for traffic analysis

### Compliance & Auditing

**Audit Trails:**
- CloudTrail logging all API calls
- S3 access logs
- VPC Flow Logs
- Application-level audit logs in CloudWatch

**Compliance Standards:**
- GDPR considerations for data privacy
- ISO 27001 alignment
- SOC 2 Type II readiness
- UK data residency (eu-west-2)

---

## Operational Excellence

### Monitoring & Observability

**Key Metrics Tracked:**
- IoT message ingestion rate
- Kinesis stream lag
- Flink job latency
- S3 bucket size and object count
- Snowflake query performance
- ECS task CPU/memory utilization
- API Gateway latency and error rates
- CloudFront cache hit ratio

**Alerting:**
- Critical: PagerDuty integration for on-call
- High: Email to ops team
- Medium: Slack notifications
- Low: Dashboard indicators only

**Distributed Tracing:**
- AWS X-Ray for request tracing
- CloudWatch ServiceLens for service maps
- Custom instrumentation in application code

### Backup & Disaster Recovery

**RTO/RPO Targets:**
- Recovery Time Objective (RTO): 4 hours
- Recovery Point Objective (RPO): 15 minutes

**Backup Strategy:**
- RDS automated backups (daily, 35-day retention)
- S3 cross-region replication to eu-west-1
- Snowflake Time Travel (90 days)
- DynamoDB point-in-time recovery
- Infrastructure as Code (IaC) in Git

**Disaster Recovery Plan:**
- Multi-AZ deployment for HA
- CloudFormation/Terraform for rapid rebuild
- Runbooks for common failure scenarios
- Quarterly DR testing

### Cost Optimization

**Cost Allocation:**
- Tagging strategy by tenant and use case
- Cost Explorer reports by tag
- Budgets with alerts at 80% and 100%
- Monthly cost review meetings

**Optimization Strategies:**
- Snowflake warehouse auto-suspend/auto-resume
- S3 lifecycle policies for archival
- Reserved Instances for predictable workloads
- Spot Instances for Flink/EMR clusters
- CloudFront caching to reduce origin load
- QuickSight SPICE to reduce Snowflake queries

**Estimated Monthly Costs (30 tenants):**
- AWS IoT Core: £500
- Kinesis: £800
- EMR/Flink: £1,200
- S3 Storage: £400
- Snowflake: £2,500
- ECS Fargate: £600
- RDS Aurora: £400
- CloudFront: £200
- Other AWS Services: £800
- **Total: ~£7,400/month (~£250/tenant)**

---

## Performance Optimization

### Real-Time Processing

**Target Latencies:**
- IoT Core to Kinesis: <100ms
- Kinesis to Flink: <1 second
- Flink processing: <3 seconds
- Write to S3: <1 second
- **End-to-End: <5 seconds for real-time dashboards**

**Optimization Techniques:**
- Kinesis shard scaling based on throughput
- Flink parallelism tuning
- CloudWatch Logs Insights for bottleneck detection

### Analytics Query Performance

**Target Latencies:**
- Dashboard load time: <2 seconds
- Ad-hoc queries: <10 seconds
- Complex reports: <30 seconds

**Optimization Techniques:**
- Snowflake query result caching
- QuickSight SPICE incremental refresh
- Materialized views for common queries
- Clustering keys on large tables
- Partition pruning on date columns

### Web Application Performance

**Target Metrics:**
- Time to First Byte (TTFB): <200ms
- First Contentful Paint (FCP): <1 second
- Largest Contentful Paint (LCP): <2.5 seconds
- Time to Interactive (TTI): <3 seconds

**Optimization Techniques:**
- React code splitting and lazy loading
- CloudFront edge caching
- Asset compression (gzip/brotli)
- CDN for static assets
- Service worker for offline capability

---

## Future Enhancements

### Planned Capabilities

1. **Advanced Analytics**
   - Predictive quality analytics
   - Supply chain optimization
   - Energy forecasting models
   - Production scheduling AI

2. **Additional Use Cases**
   - Vibration monitoring for predictive maintenance
   - Computer vision for quality inspection
   - Employee tracking for labor optimization
   - Environmental monitoring (water, waste)

3. **Platform Improvements**
   - GraphQL API for flexible querying
   - Real-time collaboration features
   - Mobile native apps (iOS/Android)
   - Voice assistant integration (Alexa, Google)

4. **Data Science Features**
   - Jupyter notebook integration
   - AutoML capabilities via SageMaker Autopilot
   - Feature store for ML
   - Model serving with real-time inference

5. **Integration Ecosystem**
   - ERP system connectors (SAP, Oracle)
   - MES integration (Siemens, Rockwell)
   - PLM integration (Autodesk, PTC)
   - Marketplace for third-party apps

---

## Conclusion

The Smart Manufacturing Data Hub architecture provides a robust, scalable, and secure foundation for supporting multiple manufacturing use cases. By leveraging AWS cloud services and Snowflake's data warehouse capabilities, the platform delivers:

✅ **Multi-tenant isolation** with strong security boundaries  
✅ **Real-time and batch processing** for diverse data patterns  
✅ **Flexible analytics** supporting multiple BI tools  
✅ **Scalable infrastructure** that grows with tenant needs  
✅ **Cost-effective operations** with consumption-based pricing  
✅ **High availability** with 99.9% uptime SLA  
✅ **Compliance-ready** with comprehensive auditing  

The architecture successfully supports all three initial use cases (MUA, AQMA, Job Tracking) while providing a foundation for future expansion. The unified platform approach reduces operational complexity, enables cross-use-case insights, and delivers superior value to SME tenants compared to standalone solutions.

---

## Appendix: Quick Reference

### Key AWS Services Used

| Service | Purpose | Use Case |
|---------|---------|----------|
| IoT Core | MQTT broker | MUA, AQMA |
| Kinesis | Stream processing | All |
| EMR (Flink) | Real-time analytics | MUA, AQMA |
| S3 | Data lake storage | All |
| Lambda | Serverless compute | All |
| API Gateway | REST API | Job Tracking, File Upload |
| EventBridge | Event routing | Job Tracking |
| ECS Fargate | Container hosting | Web Portal |
| RDS Aurora | Application DB | Web Portal |
| QuickSight | BI dashboards | All |
| Cognito | Authentication | Web Portal |
| CloudWatch | Monitoring | All |
| KMS | Encryption | All |

### Key Snowflake Features Used

- Row-Level Security (RLS)
- Virtual Warehouses
- Snowpipe (auto-ingestion)
- Time Travel
- Zero-Copy Cloning
- Secure Data Sharing
- Multi-cluster Warehouses

### Support Contacts

- **AWS Support**: Enterprise Support Plan
- **Snowflake Support**: Business Critical Plan
- **Platform Team**: smdh-support@example.com
- **On-Call**: PagerDuty escalation

---

**Document End**
