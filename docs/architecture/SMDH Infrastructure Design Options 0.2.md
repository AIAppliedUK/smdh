
| Document Version | 0.2 Draft |
| --- | --- |
| Date | 31st October 2024 |
| Status | For Review |
| Classification | Internal Use |
| Author | David McNabb |
| Intended Audience | Technical Architects and Project Stakeholders |


# Executive Summary

This document presents a comprehensive analysis of four distinct architectural approaches for the Smart Manufacturing Data Hub (SMDH) platform. The SMDH is designed as a cloud-native, multi-tenant Internet of Things (IoT) platform that empowers small and medium-sized manufacturing enterprises with real-time visibility into their operations.

## Document Purpose

The purpose of this document is to provide both technical architects and business stakeholders with a clear understanding of four viable architecture options for the SMDH platform. Each option has been analysed in detail, considering factors such as cost implications, technical complexity, performance characteristics, scalability, implementation timelines and operational considerations.

## Architecture Options


| Criteria | Option A: Flink | Option B: Snowflake | Option C: SiteWise | Option D: Timestream |
| --- | --- | --- | --- | --- |
| Monthly Cost (30 tenants) | £2,400-3,100 | £2,200-3,000 | £2,500 | £1,500-2,000* |
| Complexity | Very High | Low | Medium-High | Medium |
| Timeline | 24 weeks | 20 weeks | 28 weeks | 22 weeks |
| Best Suited For | Sub-second latency required | Most scenarios (Recommended) | SiteWise expertise available | AWS-native mandate |

**\* Option D Note:** Cost estimate is conservative pending verification. Detailed calculation shows £796/month, but this requires investigation to ensure all services are accounted for. Using £1,500-2,000/month as prudent estimate.


## Recommended Approach

For most manufacturing IoT scenarios, Option B (Snowflake) provides the best balance of:

- Lowest cost: £2,200-3,000/month (est. £73-100/tenant for 30 tenants)

- Lowest complexity: Only 5 core services to manage

- Fastest time-to-market: 20 weeks to production

- SQL-first development: Familiar to most engineering teams

- Native multi-tenancy: Secure row-level security built-in

- Proven in manufacturing: Used by major industrial companies

The default configuration provides 60-65 second dashboard update latency, which can be improved to <5 seconds for critical alerts by adding a Lambda "fast-path" (additional £100-150/month and 2 weeks implementation).

## Alternative Options

Whilst Option B is recommended as the default choice, the other options may be preferable in specific circumstances:

Option A (Flink-Based): Provides advanced stream processing but requires Flink expertise and accepts highest complexity. Cost: £2,400-3,100/month.

Option C (SiteWise): Provides managed asset modelling but requires custom dashboard development. Cost: £2,500/month.

Option D (AWS-Native): Provides excellent multi-tenancy, Grafana dashboards and unified time-series storage. Cost: £1,500-2,000/month* (conservative estimate pending verification).

## How to Use This Document

This document is structured to support both detailed technical review and high-level business decision-making:

- Technical Architects: Review the four architecture options (Options A-D) for detailed component descriptions, data flows, and technical trade-offs

- Project Stakeholders: Focus on this Executive Summary, the Architecture Comparison section, and the Recommendations section

- Decision-Makers: Review the comparison matrices and decision framework in the Architecture Comparison section

- Refer to the Glossary for explanations of technical terms. Terms are explained in plain English throughout the document.

# Operations & Disaster Recovery

This section addresses operational considerations including recovery objectives, data replay strategies, schema evolution, and tenant off-boarding procedures.

## RPO/RTO Targets

All options meet the NFR-4 requirement of RPO ≤5 minutes and RTO ≤30 minutes:

- Option A: RPO ≤5 min (Kinesis retention), RTO ≤30 min (EMR cluster restart)

- Option B: RPO ≤5 min (Kinesis retention), RTO ≤20 min (Snowflake always-on)

- Option C: RPO ≤5 min (S3 archival + replay), RTO ≤30 min (SiteWise regional failover)

- Option D: RPO ≤5 min (Kinesis retention), RTO ≤25 min (Timestream multi-AZ)

## Replay & Backfill Strategy

All options support idempotent replay using structured event IDs:

- Event ID format: {device_id}_{timestamp_ms}_{sequence_number}

- Kinesis retention: 7 days (configurable to 365 days)

- Deduplication: Processing layers check for existing event_id before insert

- Backfill window: Up to 7 days without S3 archival, unlimited with S3 backup

## Schema Evolution

Schema changes are managed through staged rollouts:

- Snowflake (A & B): VARIANT column for flexible JSON, ALTER TABLE for new columns

- SiteWise (C): Asset model versioning with backward compatibility

- Timestream (D): Schema-on-write, ALTER TABLE for new measures

- Backward compatibility: Old devices continue sending v1 schema during migration

- Migration window: 30-day dual-schema support for gradual device updates

## Tenant Off-Boarding

Tenant removal follows secure data lifecycle procedures:

- Contract End: 30-day notice period before data deletion

- Data Export: Tenant receives full data extract (CSV/Parquet)

- Device Revocation: IoT certificates revoked immediately

- Logical Delete: Tenant_id marked as deleted (soft delete for 90 days)

- Physical Purge: Data physically deleted after 90-day retention

- Audit Retention: Access logs retained for 7 years (compliance)

## Decision Flow Framework

Updated Decision Flow (v0.2): This framework now includes skills constraint assessment and latency tolerance branches to better match organizational capabilities with option selection.

- Step 1 - Skills Constraint: Assess team capabilities (React/Flink/Java vs SQL-focused)
- Step 2 - Vendor Policy: Determine if Snowflake licensing is acceptable
- Step 3 - Latency Tolerance: Confirm if 60-second dashboard refresh is acceptable
- Step 4 - Niche Cases: Evaluate SiteWise expertise for <10 tenant scenarios

# Security Control Matrix

This section details security controls including tenant isolation mechanisms, encryption/key management, audit trails, and GDPR compliance.

## Tenant Isolation

Multi-tenant data isolation methods by option:

• Option A/B: Native (RLS) - Snowflake Row-Level Security, database-enforced, excellent security
• Option C: Tags (App-enforced) - SiteWise tags with application filtering, moderate security, higher risk
• Option D: Partitions (DB-enforced) - Timestream partition keys, database-enforced, good security

## Encryption & Key Management

All options use AWS KMS with tenant-specific envelope keys:

• Encryption at rest: AES-256 with AWS KMS
• Encryption in transit: TLS 1.2+ for all connections
• Key hierarchy: Master key per environment + envelope key per tenant
• Key rotation: Automatic 365-day rotation for envelope keys
• Customer-managed keys: Optional BYOK for enterprise customers

## Audit Trail & Immutability

All data access is logged for compliance:

• Audit scope: Every query, dashboard view, data export logged with user/tenant context
• Immutability: Audit logs written to S3 with Object Lock (WORM mode)
• Retention: 7 years (GDPR/SOC 2 requirement)
• Access: Audit logs queryable via Amazon Athena

## GDPR & Data Subject Rights

GDPR compliance requires data subject request (DSR) handling:

• Right to Access: Export all data for a given user_id/device_id (CSV/JSON)
• Right to Erasure: Delete all personal data within 30 days of request
• Data minimization: No PII stored in time-series data (device_id only)
• Breach notification: Incident response plan with 72-hour notification SLA
• DSR processing time: 5-10 days depending on option (automated via API)

# Portal Assumptions

This document explicitly excludes the customer access portal implementation, but assumes the following authentication and authorization model:

## Authentication (AuthN)

• Amazon Cognito User Pools: Managed authentication service
• OIDC Integration: Support for SSO with customer IdPs (Azure AD, Okta)
• MFA: Optional 2FA via SMS or TOTP authenticator
• Session duration: 8-hour token expiry with refresh tokens (30 days)
• Password policy: 12+ characters, complexity rules, rotation optional

## Role-Based Access Control (RBAC)

Four-tier role model:

• Org Admin: Full access to all sites, devices, users within organization
• Site Admin: Manage devices and users for assigned sites
• Operator: View dashboards and acknowledge alerts for assigned sites
• Read-Only: View dashboards only, no alert ACK or configuration

## Dashboard Embedding Strategy

• Option A/B (QuickSight): QuickSight embedding SDK, $0.30/session, Cognito JWT → QS session
• Option C (Custom React): Direct API calls, included in dev cost, Cognito JWT → REST API
• Option D (Grafana): Grafana iframe embedding, free (included in Pro tier), Cognito JWT → Grafana API token

# System Overview and Requirements

## What is the Smart Manufacturing Data Hub?

The Smart Manufacturing Data Hub (SMDH) is a cloud-based software platform designed to help small and medium-sized manufacturing enterprises (SMEs) monitor and analyse their operations in real-time. This centralised "command centre" where data from factory equipment, environmental sensors, energy metres and tracking systems flows together to provide actionable insights.

Unlike traditional manufacturing systems that require extensive IT infrastructure and expertise, SMDH is designed as a self-service platform. Companies can independently register, configure their equipment and start viewing data—all through an intuitive web interface without requiring specialised technical knowledge.

### How It Works (Simplified)

The platform operates through a straightforward workflow:

1. Company Registration: Manufacturing companies create accounts through a self-service portal. They provide basic information about their organisation and can immediately begin setup.

2. Site and Device Configuration: Companies register their manufacturing facilities (sites) and the equipment they want to monitor. A guided wizard helps configure sensors, metres and tracking devices with minimal technical input.

3. Automatic Data Collection: Once configured, sensors begin sending data automatically. Machine status, environmental readings, energy consumption and job locations flow continuously into the platform.

4. Data Processing and Storage: The system receives, validates and stores data securely. Each company's data is completely isolated from others. Historical data is retained according to compliance requirements.

5. Real-Time Dashboards: Pre-built dashboards automatically display relevant information based on the types of equipment registered. Users see real-time status, historical trends and analytics.

6. Alerts and Notifications: The system monitors data against configurable thresholds. When issues arise (equipment failure, poor air quality, excessive energy use), users receive immediate notifications via email or SMS.

## Key System Requirements

### Data Volume and Performance Requirements

The platform must handle significant data volumes whilst maintaining responsive performance:


| Requirement | Target Specification |
| --- | --- |
| Daily data ingestion | 2.6 to 3.9 million data points per day |
| Real-time monitoring latency | Under 1 second for dashboard updates |
| Alert notification time | Under 10 seconds from trigger event to notification |
| Dashboard query response | Under 5 seconds for complex analytics queries |
| System availability | 99.9% uptime (maximum 8.76 hours downtime per year) |


These requirements ensure users have immediate visibility into their operations. A machine failure or air quality issue must be detected and escalated within seconds, not minutes, to enable timely response.

### Multi-Tenancy and Data Isolation

As a Software-as-a-Service (SaaS) platform serving multiple manufacturing companies simultaneously, the SMDH must provide absolute data isolation. This is non-negotiable for several reasons:

- Security: Company A must never access Company B's data under any circumstances

- Compliance: GDPR and industry regulations require strict data segregation

- Intellectual Property: Manufacturing data often contains trade secrets and proprietary processes

- Performance: One company's heavy usage must not impact another company's performance

- Scalability: The system must efficiently serve 30-40 companies initially, scaling to 100+ over time

Technical Implementation:

Multi-tenancy can be implemented in several ways, and this is a key differentiator between the four architecture options:

• Row-Level Security (RLS): Database-enforced filtering that automatically restricts queries to authorised data. Used in Options A and B with Snowflake. Most secure.

• Partition Keys: Physical data separation using tenant identifiers as partition keys. Used in Option D with Timestream. Good security with performance benefits.

• Tag-Based Filtering: Application-layer filtering using metadata tags. Used in Option C with SiteWise. Requires careful implementation to avoid data leakage.

### Cost Considerations

The platform has a consumption-based cost model to ensure economic viability for SMEs, with target costs of £200-300 per tenant per month.

For an initial deployment of 30 manufacturing companies, this translates to:


| Cost Component | Amount |
| --- | --- |
| Total Monthly Infrastructure Cost | £6,000 - £9,000 (30 tenants) |
| Per-Tenant Cost Target | £200 - £300 |
| Annual Infrastructure Cost | £72,000 - £108,000 |


## Use Cases Supported

The SMDH platform must support diverse monitoring scenarios across manufacturing environments. Each use case has distinct characteristics and requirements described in the following subsections.

### Use Case 1: Machine Utilisation Monitoring

Business Objective: Track how efficiently manufacturing equipment is being used to identify bottlenecks, reduce downtime and improve overall equipment effectiveness (OEE).

How It Works:

Sensors attached to manufacturing equipment (CNC machines, lathes, presses, mills) collect data every second about the machine's operational state:

- State: Running, Idle or Offline

- Cycle count: Number of production cycles completed

- Performance: Actual vs expected production rate

- Downtime events: When and why machines stop

- Error codes: Specific failure conditions

Technical Specifications:


| Specification | Value |
| --- | --- |
| Data frequency | 1 Hz (one reading per second) |
| Sensors per site | 30-45 machines typically |
| Communication protocol | LoRaWAN or MQTT |
| Daily data volume | ~2.6 million readings per site per day |
| Latency requirement | <1 second (immediate status visibility required) |


Key Metrics Calculated:

- Overall Equipment Effectiveness (OEE): Industry-standard metric combining availability, performance, and quality (target: >85% world-class)

- Availability: Percentage of scheduled time the machine is operational

- Performance: Actual production rate vs ideal production rate

- Utilisation: Percentage of time machines are actively producing

- Mean Time Between Failures (MTBF): Reliability metric

- Mean Time To Repair (MTTR): Maintenance efficiency metric

### Use Case 2: Air Quality Management

Business Objective: Monitor environmental conditions in manufacturing facilities to ensure worker health and safety, regulatory compliance and optimal working conditions.

How It Works:

Environmental sensors positioned throughout the facility continuously monitor air quality parameters:

- CO₂ levels: Carbon dioxide concentration (target: <1000 ppm for good ventilation)

- VOCs: Volatile Organic Compounds from paints, solvents, adhesives

- Particulate Matter: PM1, PM2.5, PM4, PM10 (from grinding, cutting, welding)

- Temperature: Workspace thermal comfort

- Humidity: Moisture levels affecting comfort and processes

- Atmospheric Pressure: Baseline environmental measurement

Technical Specifications:


| Specification | Value |
| --- | --- |
| Data frequency | 1-minute intervals |
| Sensors per site | 10-15 sensors (distributed across facility) |
| Communication protocol | MQTT over WiFi/Ethernet |
| Daily data volume | ~200,000 readings per site per day |
| Alert requirement | <10 seconds for dangerous conditions (e.g., CO₂ >5000 ppm) |


Regulatory Compliance:

The platform must support compliance with:

- UK Health and Safety Executive (HSE) Workplace Exposure Limits (WELs)

- European Union Occupational Safety and Health Directives

- ISO 45001 Occupational Health and Safety Management

- COSHH (Control of Substances Hazardous to Health) Regulations

### Use Case 3: Energy Monitoring and Optimisation

Business Objective: Track electrical consumption to identify energy waste, reduce costs and meet sustainability goals. Manufacturing typically represents 30-50% of operational costs for energy-intensive facilities.

How It Works:

Energy monitoring devices (installed at circuit breaker panels or on individual equipment) measure electrical parameters in real-time:

- Voltage: Electrical potential (V) - indicates power quality

- Current: Electrical flow (A) - indicates load

- Power Factor: Efficiency of electricity usage (target: >0.95)

- Real Power: Actual energy consumed (kW)

- Apparent Power: Total power drawn (kVA)

- Cumulative Consumption: Total kilowatt-hours (kWh) over time

- Cost Estimate: Energy cost based on tariff rates

Technical Specifications:


| Specification | Value |
| --- | --- |
| Data frequency | 15-second intervals |
| Monitors per site | 10-20 monitoring points (circuits + individual equipment) |
| Communication protocol | Modbus TCP or MQTT |
| Daily data volume | ~600,000 readings per site per day |
| Accuracy requirement | ±1% for billing-grade monitoring |


Key Analytics:

- Baseline Consumption: Establish normal usage patterns

- Peak Demand Analysis: Identify when and where peak usage occurs (affects tariffs)

- Power Factor Correction Opportunities: Improve efficiency and reduce reactive power charges

- Equipment Efficiency Comparison: Compare energy use across similar machines

- Cost Allocation: Distribute energy costs across departments or products

- Carbon Footprint Calculation: Convert kWh to CO₂ emissions for sustainability reporting

### Use Case 4: Job Location Tracking

Business Objective: Provide real-time visibility of work-in-progress (WIP) locations throughout the factory floor. Prevents lost jobs, reduces search time and enables accurate delivery commitments.

How It Works:

Jobs are tagged with RFID tags or printed barcodes. As jobs move through the manufacturing process, workers or automated scanners record each movement:

- Job Start: When work begins on an order

- Station Arrival: Job reaches a workstation (e.g., "Welding Station 3")

- Station Completion: Work at that station finishes

- Quality Check: Inspection points

- Job Completion: Final product ready for shipping

- Exception Events: Holds, rework required, quality failures

Technical Specifications:


| Specification | Value |
| --- | --- |
| Event type | Discrete events (not continuous time-series) |
| Event frequency | 500-2,000 scans per site per day |
| Scanners per site | 5-15 RFID readers or barcode scanners |
| Communication protocol | HTTP REST API or MQTT |
| Data structure | Event-based with rich metadata (job ID, location, operator, timestamp) |


Key Capabilities:

- Real-Time Location: "Where is Job #12345 right now?"

- Job History: Complete audit trail of movements

- Dwell Time Analysis: How long jobs spend at each station (identifies bottlenecks)

- Exception Alerting: Jobs stuck at one location beyond expected time

- Delivery Estimates: Predict completion time based on current location and historical data

- Throughput Metrics: Jobs completed per hour/day by station

Important Architectural Consideration:

Job tracking events have fundamentally different characteristics than continuous sensor data. They are discrete, irregular, and event-driven rather than time-series. This impacts architecture choice:

- Options A, B, D: Handle job tracking naturally alongside time-series data

- Option C (SiteWise): SiteWise is designed for continuous time-series, not discrete events. Requires separate Timestream database, increasing complexity.

# Option A: Flink-Based AWS Architecture

## Overview and Summary


| Characteristic | Details |
| --- | --- |
| Monthly Cost (30 tenants) | £2,400 - 3,100 |
| estimated monthly cost | £80 - 103 |
| Complexity Level | Very High (15+ AWS services) |
| Implementation Timeline | 24 weeks |
| Team Size & Skills | 3-4 engineers (Flink, Java/Scala, AWS, data engineering) |
| Best Suited For | Sub-second latency legally required; advanced ML needed |


Option A represents the most technically sophisticated architecture, leveraging Apache Flink for advanced stream processing. This approach provides unparalleled real-time capabilities with sub-second latency but comes with significant operational complexity.

## Architecture Diagram

## Core Components

### Ingestion Layer

AWS IoT Core: MQTT broker receiving 1Hz sensor data from 30-45 machines per site. Handles device authentication via X.509 certificates. Provides device shadows for configuration.

IoT Rules Engine: Routes messages based on content. Enriches data with tenant metadata. Filters invalid messages. SQL-based routing rules.

Kinesis Data Firehose: Buffers data in 10MB or 60-second batches. Compresses to Parquet format. Invokes Lambda for transformation. Delivers to S3.

Lambda Transformation: Validates sensor ranges, converts units, enriches with lookup data. Python or Node.js. Scales automatically.

S3 Data Lake: Stores Parquet files partitioned by tenant/date. Lifecycle policies for archival. Enables historical analysis and recovery.

### Stream Processing Layer (Apache Flink)

Apache Flink is an advanced distributed stream processing framework. Unlike simpler alternatives, Flink provides:

- Sub-second latency: Process and respond to events in <1 second

- Exactly-once semantics: Guarantees no data loss or duplication

- Complex event processing: Detect patterns across multiple streams

- Stateful processing: Remember context across events (e.g., calculate 5-minute rolling averages)

- Advanced windowing: Tumbling, sliding, session windows for aggregations

- Backpressure handling: Gracefully manages data spikes

Flink on EMR: Runs on 3-5 node cluster. Auto-scaling based on data velocity. Checkpoints state to S3 every 5 minutes.

RocksDB State Backend: Embedded database storing intermediate state. Enables fault tolerance. Recovers from checkpoints if nodes fail.

Flink Jobs: Custom Java/Scala code for: real-time aggregations, anomaly detection, pattern matching, multi-tenant data isolation.

### Data Platform Layer (Snowflake)

Snowpipe Auto-Ingestion: Detects new S3 files via events. Loads into Snowflake within seconds. Serverless—no warehouse management.

Raw Tables: VARIANT columns store semi-structured JSON. Partitioned by tenant_id. Clustered on timestamp for query performance.

Snowflake Streams: Change Data Capture tracking new/changed rows. Enables incremental processing. Multiple consumers can read independently.

Snowflake Tasks: Scheduled SQL transformations. DAG-based dependencies. Runs hourly aggregations, data quality checks, archival.

Curated Views: Row-Level Security enforces tenant isolation. Pre-calculated aggregations. Analytics-ready datasets.

### Application Layer

API Gateway + Lambda: REST APIs for data access. Tenant authentication via Cognito. Query Snowflake and return JSON.

ECS Fargate Web App: React frontend hosted on Fargate. Auto-scaling. CI/CD via CodePipeline.

QuickSight Dashboards: Embedded analytics. Row-Level Security passes through from Snowflake. Pay-per-session pricing.

SageMaker ML: Custom model training (predictive maintenance, anomaly detection). GPU-accelerated. Model hosting on auto-scaling endpoints.

## Data Flow

Real-time path (critical alerts):

- Sensor → IoT Core (100ms)

- IoT Rules → Kinesis Streams (200ms)

- Flink processes and detects alert condition (500ms)

- SNS notification sent (200ms)

- Total: <2 seconds end-to-end

Batch path (historical analytics):

- Kinesis Firehose buffers 60 seconds

- Lambda transforms batch

- S3 receives Parquet files

- Snowpipe loads into Snowflake (<5 min)

- Snowflake Tasks aggregate hourly

- QuickSight dashboards refresh

## Strengths

Sub-Second Latency: Achieves <1s for critical data paths. Essential if regulatory requirements mandate immediate response.

Advanced Stream Processing: Complex event processing, pattern detection, sophisticated windowing not possible with simpler systems.

Unlimited Flexibility: Custom Java/Scala code enables any transformation or ML algorithm.

Proven at Scale: Flink powers streaming at Netflix, Uber, Alibaba processing billions of events daily.

## Limitations

Very High Complexity: Managing 15+ services, Flink cluster tuning, distributed debugging.

Flink Expertise Required: Rare and expensive skill set. Steep learning curve for Java/Scala.

Longest Timeline: 24 weeks to production. Complex distributed systems take time to build and test.

Operational Overhead: EMR cluster management, checkpointing monitoring, state recovery testing.

## When to Choose

Select Option A ONLY if:

- Sub-second latency is legally or regulatorily mandated (not just preferred)

- Complex event processing is essential for the business case

- Team has Flink expertise or funding for specialists

- Willing to accept highest complexity and 24-week timeline

# Architecture Option B: Snowflake-Leveraged Architecture

## Overview and Summary


| Characteristic | Details |
| --- | --- |
| Monthly Cost (30 tenants) | £2,200 - 3,000 (CHEAPEST) |
| estimated monthly cost | £73 - 100 |
| Complexity Level | Low (5 core services) |
| Implementation Timeline | 20 weeks (FASTEST) |
| Team Size & Skills | 2-3 engineers (SQL, Snowflake, basic AWS) |
| Best Suited For | Most scenarios - default recommendation |


Option B centralises data processing in Snowflake, simplifying the architecture compared to Option A. Leveraging Snowflake's native streaming, task orchestration, and SQL-first approach, this option provides the fastest time-to-market and lowest operational complexity whilst meeting all functional requirements.

## Architecture Diagram

## Core Components

### Simplified Ingestion

AWS IoT Core: Same as Option A—MQTT broker with X.509 authentication.

Kinesis Data Streams: Lightweight buffering (not Firehose). Streams directly to Snowflake. 10-20 shards partitioned by tenant_id.

Snowpipe Streaming: Snowflake's streaming ingestion service. Loads data in 5-10 seconds. Eliminates S3 staging and Lambda transformation complexity.

### Unified Data Platform (Snowflake Does It All)

Key Simplification:

In Option B, Snowflake replaces multiple Option A services:

- Replaces S3 Data Lake → Snowflake internal storage

- Replaces Lambda + Flink → Snowflake Streams and Tasks

- Replaces AWS Glue → Snowflake native schema evolution

- Replaces separate ETL orchestration → Snowflake Task DAGs

Raw Tables with VARIANT: JSON data stored in VARIANT columns. Schema-flexible. Automatic compression (75-85% reduction). Partitioned by tenant_id.

Snowflake Streams (CDC): Tracks inserts/updates/deletes. Enables incremental processing. Zero-copy—doesn't duplicate data.

Snowflake Tasks: SQL-based transformations run on schedule or when streams have data. DAG orchestration. Serverless compute.

Dynamic Tables: Continuously updated aggregations. Declarative SQL definitions. Incremental refresh automatically.

Row-Level Security (RLS): Native multi-tenancy. Policies enforce tenant isolation at database level. Cannot be bypassed by applications.

### Machine Learning (Snowflake Cortex)

Snowflake Cortex ML enables SQL-based machine learning:

- CREATE MODEL predict_failure AS SELECT * FROM training_data;

- SELECT PREDICT_FAILURE(sensor_data) FROM current_readings;

- Supports: Classification, regression, time-series forecasting

- Limitation: Less flexible than SageMaker but covers 80% of use cases

## Data Flow

End-to-end flow (simplified):

- Sensor → IoT Core (100ms)

- Kinesis Streams (200ms)

- Snowpipe Streaming → Raw table (5-10 seconds)

- Snowflake Stream detects new rows immediately

- Task processes (runs every 1 min) → Curated views

- Dashboard refreshes (total: 60-65 seconds)

Alert Latency Solution:

Default 60s latency violates <10s alert requirement. FIX: Add Lambda fast-path for alerts (+£100-150/month, +2 weeks). Fast-path achieves <5s alert latency whilst keeping batch processing in Snowflake.

## Strengths

Lowest Cost: £2,170-3,450/month. Cheapest option by 15-20%. Auto-suspend when idle.

Lowest Complexity: Only 5 core services vs 15+ in Option A. Single platform for most processing.

Fastest Timeline: 20 weeks to production. SQL-first development accelerates delivery.

SQL-First Development: Familiar to most engineers. Easier to hire than Flink specialists.

Native Multi-Tenancy: Row-Level Security enforced at database level. Production-proven.

Unified Governance: All data in one platform. Single place for audits, lineage, retention policies.

## Limitations

Alert Latency Requires Fix: 60s default. Add Lambda fast-path for <5s alerts (+£100-150/month).

Snowflake Licensing: Separate from AWS bill.

Not Sub-Second: Snowpipe Streaming is 5-10s, not <1s. If sub-second required, choose Option A.

## When to Choose

Select Option B if:

- Cost and simplicity are priorities (most SME scenarios)

- Team has SQL skills or can train quickly

- 60s dashboard latency acceptable, or willing to add Lambda fast-path

- Want fastest time to market (20 weeks)

- Snowflake licensing not a blocker

# Option C: AWS IoT SiteWise-Based

## Overview and Summary


| Characteristic | Details |
| --- | --- |
| Monthly Cost (30 tenants) | £2,500 |
| estimated monthly cost | £83 |
| Complexity Level | Medium-High (8-10 AWS services + dual storage) |
| Implementation Timeline | 28 weeks (longest - custom dashboards required) |
| Team Size & Skills | 3-4 engineers (SiteWise, AWS IoT, React, Timestream) |
| Best Suited For | Teams with deep SiteWise expertise; <10 tenants; AWS-native preference |


Option C leverages AWS IoT SiteWise, a managed service purpose-built for industrial equipment monitoring. SiteWise provides native concepts like asset hierarchies (Factory → Line → Machine), automatic time-series calculations, and OPC-UA/Modbus protocol support. However, it is NOT designed for multi-tenant SaaS, requiring significant customisation and dual-storage architecture.

## Architecture Diagram

## Core Components

### Dual Ingestion Path (SiteWise + Timestream)

Why Dual Storage?

Option C requires TWO separate data stores because SiteWise and Timestream serve different purposes:


| Aspect | SiteWise | Timestream |
| --- | --- | --- |
| Data Type | Continuous time-series (machine status, sensors) | Discrete events (RFID scans, job tracking) |
| Best For | Regular sensor readings, asset hierarchies, OEE | Irregular events, rich metadata, SQL queries |
| Use Cases | Machine utilisation, energy, air quality | Job location tracking, barcode scans |


SiteWise Gateway (On-Premises): Software appliance running at manufacturing sites. Translates industrial protocols (OPC-UA, Modbus TCP) to AWS IoT format. Handles local caching for offline operation. Requires management at each site (updates, security patches).

AWS IoT Core: MQTT broker (same as other options). Routes data based on type: continuous data → SiteWise, events → Kinesis.

IoT Rules Engine: Routes messages by content. Continuous sensor data goes to SiteWise, discrete events (RFID/barcodes) route to Kinesis Streams.

Kinesis Streams (Events Only): Buffers discrete events for ingestion into Timestream. Does NOT handle continuous sensor data (that goes directly to SiteWise).

### AWS IoT SiteWise (Time-Series Platform)

What Makes SiteWise Different?

Unlike general-purpose databases, SiteWise is purpose-built for industrial IoT:

- Asset Models: Templates defining equipment structure (e.g., "CNC Machine" with properties for spindle speed, temperature, state)

- Asset Hierarchies: Organise equipment in trees (Company → Site → Production Line → Machine → Sensor)

- Compute Expressions: Automatic calculations (OEE, availability, performance) without custom code

- Native Time-Series Storage: Optimised for high-frequency sensor data with automatic aggregations

- Built-in Formulas: Industry-standard metrics (OEE, MTBF, MTTR) pre-configured

SiteWise Asset Ingestion: Receives data from Gateway or direct MQTT. Validates against asset models. Stores in time-series database. Latency: <1 second.

Asset Models: Define structure: Measurements (raw sensor readings), Metrics (calculated values like OEE), Transforms (unit conversions, aggregations), Alarms (threshold-based alerts).

Compute Expressions: SiteWise Expression Language (similar to Excel formulas). Example: availability = (total_time - downtime) / total_time. Runs automatically as data arrives.

Time-Series Store: Hot tier: 13 months (fast queries). Cold tier: 14+ months (S3-based archival). Automatic aggregations: 1min, 5min, 1hour, 1day intervals.

SiteWise Monitor: Built-in dashboarding tool. LIMITATION: Cannot be adequately white-labelled for SaaS. AWS branding remains visible. Not multi-tenant aware.

### Critical Multi-Tenancy Challenge

Unlike Snowflake's Row-Level Security or Timestream's partition keys, SiteWise has NO native multi-tenancy support. The workaround:

- Tag every asset with "tenant_id" metadata

- Application layer (Lambda/API) must filter ALL queries by tenant_id

- Custom React application enforces filtering in UI code

- Requires extensive security testing—a bug could expose one tenant's data to another

Risk Assessment: Medium-high risk for multi-tenant SaaS. Acceptable for single-tenant deployments or <10 trusted tenants. Requires rigorous code review and penetration testing.

### Amazon Timestream (Event Data)

Why Timestream?: SiteWise cannot efficiently handle discrete events (RFID scans, job completions). These have irregular timing and rich metadata. Timestream is purpose-built for this.

Timestream Tables: Separate tables for job_scan_events, quality_checks, maintenance_logs. Partition key: tenant_id (better multi-tenancy than SiteWise tags).

SQL Query Engine: Standard SQL interface for event analysis. Example: "Find all scans for Job #1234 in past week." Much simpler than SiteWise property queries.

### Custom Dashboard Layer (Required)

Why Custom Dashboards Are Necessary

SiteWise Monitor limitations force custom development:

- Cannot white-label: AWS branding and URLs remain visible

- Not multi-tenant: No concept of separating dashboards by company

- Limited customisation: Dashboard layout and chart types are constrained

- Cannot combine data: Cannot easily show SiteWise + Timestream data together

Custom React Application: Built from scratch using React 18+ and TypeScript. Calls SiteWise and Timestream APIs directly. Uses Chart.js or Recharts for visualisations. Fully white-labelable.

API Gateway + Lambda: Backend layer enforcing tenant isolation. Every API call validates user's tenant_id before querying SiteWise/Timestream. Filters results by tenant.

AWS Amplify Hosting: Hosts React frontend. Provides CI/CD pipeline. Integrates with Cognito for authentication.

## Data Flow

Time-series data path (Machine/Energy/Air Quality):

- Sensor → OPC-UA/Modbus → SiteWise Gateway (on-prem)

- Gateway → AWS IoT SiteWise ingestion (latency: <1s)

- SiteWise validates against asset model, stores in time-series DB

- Compute expressions calculate metrics (OEE, aggregations)

- Custom React app queries SiteWise API for dashboard display (latency: <5s total)

Event data path (RFID/Barcode Scans):

- Scanner → HTTP POST to API Gateway

- Lambda validates and routes to Kinesis Streams (latency: <200ms)

- Lambda consumer writes to Timestream (latency: <1s)

- Custom React app queries Timestream SQL for job tracking dashboard (latency: <3s total)

## Strengths

Purpose-Built for Manufacturing: Native industrial concepts: asset models, OEE, equipment hierarchies. Speaks manufacturing language, not generic database terms.

Managed Asset Modelling: Built-in templates for common equipment. Automatic calculations for availability, performance, quality. Less custom code than building from scratch.

Real-Time Latency: <1 second for time-series data. Meets real-time monitoring requirements without complex stream processing like Flink.

Industrial Protocol Support: SiteWise Gateway handles OPC-UA, Modbus TCP natively. Easier connectivity to legacy manufacturing equipment.

Automatic Metric Calculations: Compute expressions run at ingestion time. Standard manufacturing metrics (OEE, MTBF, utilisation) pre-configured.

## Limitations

NOT Designed for Multi-Tenant SaaS: CRITICAL: No native Row-Level Security. Tag-based filtering is application-layer workaround with data leakage risk. Acceptable for <10 tenants; risky for SaaS.

Most Expensive Option: Cost: £6,334/month (£211/tenant) vs £2,170 for Option B (cheapest). 3x more expensive. Ingestion pricing ($0.75 per million values) adds up with 1Hz sensors.

Dual Storage Complexity: Requires BOTH SiteWise (time-series) AND Timestream (events). Applications must query two databases. Data correlation requires custom logic.

Custom Dashboard Development: SiteWise Monitor cannot be white-labelled. Must build custom React application (6-8 weeks development + ongoing maintenance).

Longest Timeline: 28 weeks to production. Custom dashboards, dual storage integration, and asset model configuration extend timeline 40% beyond Option B.

On-Premises Gateway Management: SiteWise Gateway requires software deployment at each manufacturing site. Software updates, troubleshooting, security patching across distributed locations.

SiteWise Learning Curve: Proprietary concepts (asset models, expression language) require training. Smaller talent pool than SQL or Python.

## When to Choose

Select Option C ONLY if:

- Team has existing deep AWS IoT SiteWise expertise (rare)

- Manufacturing focus with <10 tenants (multi-tenancy risk acceptable)

- Already using SiteWise for other projects (leverage existing skills)

- OPC-UA/Modbus connectivity is critical and must be managed (not delegated)

- consumption costs support £200+/tenant (most expensive option)

- Willing to invest 28 weeks + custom dashboard development

- Can accept dual storage complexity and manual multi-tenant isolation

Option C is viable after cost correction but NOT recommended for multi-tenant SaaS. The multi-tenancy risk (tag-based filtering), highest cost, dual storage complexity, and custom dashboard requirement outweigh the benefits of managed asset modelling. Choose Option B for simplicity or Option D for AWS-native without SiteWise limitations.

# Option D: AWS-Native Architecture (Timestream + Grafana)

## Overview and Summary


| Characteristic | Details |
| --- | --- |
| Monthly Cost (30 tenants) | £1,500 - 2,000* |
| estimated monthly cost | £50 - 67* |
| Complexity Level | Medium (7-8 AWS services) |
| Implementation Timeline | 22 weeks |
| Team Size & Skills | 2-3 engineers (AWS-native, SQL, Grafana) |
| Best Suited For | AWS-native mandate; organisations preferring no Snowflake |


Option D provides a fully AWS-native solution using Amazon Timestream for all time-series and event data, combined with Grafana for industry-leading dashboards. This approach avoids Snowflake licensing concerns (Option B) and SiteWise multi-tenancy limitations (Option C) whilst maintaining reasonable cost and complexity. It is the recommended choice when AWS-native services are mandated.

## Architecture Diagram

## Core Components

### Unified Ingestion (Single Data Path)

Key Simplification

Unlike Option C which requires dual storage (SiteWise + Timestream), Option D uses Timestream for EVERYTHING—continuous sensor data AND discrete events. This dramatically simplifies the architecture.

- Single database to query (not two)

- Unified data model (no translation between SiteWise and Timestream)

- Single SQL interface (familiar to most engineers)

- Native partition-based multi-tenancy (better than SiteWise tags)

- Lower operational overhead (one database to monitor, backup, optimise)

AWS IoT Core: Same MQTT broker as other options. X.509 certificate authentication. Device shadows. QoS 0/1 support.

IoT Rules Engine: Routes ALL data types to Kinesis Streams. Simpler than Option C (no dual routing). Enriches messages with tenant metadata.

Kinesis Data Streams: 10-20 shards partitioned by tenant_id. Buffers all sensor data and events. 24-hour retention for replay capability.

Lambda Ingestion Handler: Processes Kinesis batches. Validates sensor ranges. Converts to Timestream format. Writes to appropriate Timestream tables. Handles both time-series and events.

### Amazon Timestream (Unified Data Platform)

Why Timestream Over SiteWise?


| Feature | SiteWise (Option C) | Timestream (Option D) |
| --- | --- | --- |
| Cost Model | $0.75 per million values | $0.50 per GB ingested |
| Multi-Tenancy | Manual tags | Native partition keys |
| Event Data | Poor fit (needs Timestream) | Excellent (unified) |
| Query Language | Limited property APIs | Full SQL |
| Flexibility | Asset model constraints | Schemaless |
| Cost (30 tenants) | £6,334/month | £3,965/month |


Timestream is 40% cheaper and more flexible for multi-tenant SaaS.

Timestream Database Schema: Separate tables for machine_telemetry, energy_monitoring, air_quality, job_scan_events. ALL tables partitioned by tenant_id (native physical isolation).

Memory Store: Hot tier: 7-90 days configurable. Fast queries for recent data. Used for real-time dashboards and alerts.

Magnetic Store: Warm/cold tier: Months to years retention. Cost-optimised storage. Used for historical analysis and compliance.

SQL Query Engine: Standard SQL (mostly ANSI-compatible). Familiar to most engineers. Supports JOINs, window functions, aggregations. Time-series functions (interpolate, binning).

Scheduled Queries: Native support for pre-aggregation. Runs SQL queries on schedule to compute hourly/daily metrics. Results stored back to Timestream.

### Native Partition-Based Multi-Tenancy

Every Timestream table uses tenant_id as partition key. This provides:

- Physical data separation: Each tenant's data stored in separate partitions

- Query performance: Partition pruning automatically filters data

- Security: IAM policies can restrict access at partition level

- Cost allocation: Easy to track storage and query costs per tenant

- Scalability: Partitions distribute across nodes for parallel processing

Comparison to Other Options:

- Options A & B (Snowflake RLS): Excellent - Database-enforced, cannot be bypassed

- Option D (Timestream partitions): Good - Native physical isolation, query-enforced

- Option C (SiteWise tags): Risky - Application-layer filtering, can be misconfigured

### Grafana for Dashboards

Why Grafana?

Grafana is the industry-standard visualisation platform, widely used in manufacturing and DevOps. Key advantages:

- Fully White-Labelable: Remove Grafana branding, add company logos, custom themes

- Native Timestream Plugin: Official AWS plugin for querying Timestream

- Rich Visualisation Library: Time-series charts, gauges, heatmaps, state timelines, tables

- Embeddable Dashboards: iframe embedding in custom web applications

- Alert Management: Built-in alerting with multiple notification channels

- Variable Templates: Dynamic dashboards that adapt to user selection (site, machine)

- Community Support: Massive ecosystem, extensive documentation, active forums

Grafana Cloud (Managed): SaaS offering from Grafana Labs. Fully managed (no servers). £10-30 per user per month depending on tier. Automatic updates. 99.9% SLA.

Self-Hosted on ECS Fargate: Run Grafana container on AWS ECS. Full control over deployment. One-time setup effort. Lower long-term cost for many users.

### Application State (DynamoDB)

DynamoDB Tables: Stores: tenant configuration, device registry, user preferences, dashboard configs, alert rules. Fast key-value lookups. Single-digit millisecond latency.

API Gateway + Lambda: REST APIs for: device registration, dashboard management, user settings. Enforces tenant isolation. Queries Timestream and DynamoDB.

Cognito User Pools: Authentication with SSO support. MFA capability. JWT tokens passed to Grafana and APIs.

Secrets Manager: Stores: Timestream credentials, Grafana API keys, third-party integration secrets.

## Data Flow

Unified data flow (all data types):

- Sensor → IoT Core via MQTT (latency: <100ms)

- IoT Rules → Kinesis Streams (latency: <200ms)

- Lambda processes batch → Validates, enriches (latency: <500ms)

- Timestream Write API → Memory store (latency: <1s)

- Grafana queries Timestream via plugin (latency: <2s)

- Dashboard updates display (total: <5s end-to-end)

Critical alert fast-path:

- IoT Rules detects threshold breach (e.g., CO₂ >5000 ppm)

- Lambda fast-path triggered directly (bypasses Kinesis)

- SNS/SES notification sent (latency: <500ms)

- Alert logged to Timestream (latency: <2s total)

## Strengths

Fully AWS-Native: No Snowflake dependency. All AWS services. Single vendor relationship. Unified billing.

Unified Storage: Timestream handles both continuous time-series AND discrete events. No dual-database complexity like Option C.

Native Partition Multi-Tenancy: Physical data isolation at partition level. Better security than SiteWise tags. Simpler than application-layer filtering.

Industry-Standard Dashboards: Grafana is battle-tested in manufacturing and industrial monitoring. Familiar to many operations teams. Rich visualisation library.

Fully White-Labelable: Remove all vendor branding. Add company logos and themes. Embed dashboards in custom portals seamlessly.

Cost-Effective: £3,965/month (40% cheaper than Option C). Only 15% premium over Option B for AWS-native requirement.

Standard SQL: Timestream SQL is mostly ANSI-compatible. Familiar to engineers. Easier to hire than Flink specialists.

## Limitations

15% More Expensive Than Option B: £3,965/month vs £2,170-3,450 for Snowflake. Acceptable premium for AWS-native mandate but not cheapest option.

Custom Asset Modelling Required: Unlike SiteWise's built-in asset models, must build custom data schemas and calculation logic. More initial development than Option C.

Grafana Dependency: Whilst Grafana is popular, it adds external dependency (if using Grafana Cloud) or operational overhead (if self-hosted).

Timestream SQL Differences: Whilst mostly standard, some Timestream-specific syntax and functions. Learning curve for SQL engineers familiar with PostgreSQL/MySQL.

## When to Choose

Select Option D if:

- AWS-native is mandatory (no Snowflake allowed)

- Want best-in-class time-series dashboards (Grafana)

- Need native partition-based multi-tenancy

- Comfortable with 15% cost premium vs Option B for AWS-native benefit

- Team has AWS expertise (no Snowflake learning required)

- Want unified storage for time-series + events (simpler than Option C)

- Prefer industry-standard dashboards over custom development

If AWS-native is a requirement. Option D provides the best AWS-native solution without SiteWise's multi-tenancy limitations or custom dashboard burden. It is the second-best overall option after Option B (Snowflake).

# Architecture Comparison

This section provides a comprehensive comparison of all four architecture options across multiple dimensions including cost, requirements compliance, multi-tenancy approach, dashboards, implementation timeline, and risk assessment.

This analysis incorporates recalculated costs using AWS London (eu-west-2) region pricing with standardized common infrastructure costs across all options.

**Note:** All cost estimates now use verified London region pricing. Option D costs require further investigation as calculated figures show significant variance from initial estimates.

## Quick Comparison Matrix

The following table provides a high-level overview of the four architecture options across key selection criteria:


| Criterion | Option A: Flink | Option B: Snowflake | Option C: SiteWise | Option D: Timestream |
| --- | --- | --- | --- | --- |
| Monthly Cost | £2,400-3,100 | £2,200-3,000 | £2,500 | £1,500-2,000* |
| Cost/Tenant | £80-103 | £73-100 | £83 | £50-67* |
| cost-effective? | Yes | Yes | Yes | Yes |
| Services Count | 15+ | 5 | 8-10 | 7-8 |
| Complexity | Very High | Low | Medium-High | Medium |
| Real-time Latency | <1 second | 5-10 seconds | <1 second | <5 seconds |
| Alert Latency | <5 seconds | 60-65 seconds | <10 seconds | <5 seconds |
| Multi-Tenancy | Native (RLS) | Native (RLS) | Tags (App-enforced) | Partitions (DB-enforced) |
| Dashboards | QuickSight | QuickSight | Custom React | Grafana |
| AWS-Native | Partial | Partial | Full | Full |
| Timeline | 24 weeks | 20 weeks | 28 weeks | 22 weeks |
| Team Size | 3-4 engineers | 2-3 engineers | 3-4 engineers | 2-3 engineers |
| ML Capabilities | Advanced | Good | Basic | Custom |

**\* Option D costs:** Conservative estimate pending investigation of cost discrepancy.

Overall Rankings:

1. Option B (Snowflake): Best for most scenarios - simplest and lowest cost

2. Option D (Timestream + Grafana): Best for AWS-native mandate

3. Option C (SiteWise): Suitable with deep SiteWise expertise

4. Option A (Flink): Only for sub-second latency requirements

## Requirements Compliance Analysis

This section evaluates how each option meets the functional and non-functional requirements defined in Section 2.


| Requirement | Option A | Option B | Option C | Option D | Notes |
| --- | --- | --- | --- | --- | --- |
| FR-1 to FR-3: Multi-tenancy | Row Level Security | Row Level Security | Tags | Partitions | C requires manual filtering |
| FR-6: Data ingestion (2.6M-3.9M rows/day) |  |  |  |  | All handle easily |
| FR-7: Retention (90d raw, 2y agg) |  |  |  |  | All meet |
| FR-9: Dashboard provisioning |  |  | !
Custom | Grafana | C requires React dev |
| FR-11: <10s alert triggering | <5s | 60s | <10s | <5s | B fails (needs Lambda) |
| NFR-1: <1s real-time monitoring |  | !
5-10s |  |  | B acceptable for most cases |
| NFR-2: Scalability (30-100 tenants) |  |  |  |  | All scale linearly |
| NFR-3: 99.9% uptime |  |  |  |  | All meet |
| NFR-7: GDPR/SOC 2 |  | Easier | !
Complex |  | B unified, C distributed |
|  |  |  |  |  |  |


Compliance Scores:

• Option A: 100% (meets all requirements)

• Option B: 90% (fails alert SLA, but fixable with Lambda fast-path)

• Option C: 95% (multi-tenancy security concerns)

• Option D: 100% (meets all requirements)

## Detailed Cost Breakdown

The following table breaks down the monthly infrastructure costs by component for each architecture option. All costs are presented in GBP (£) based on current AWS pricing and exchange rates.


| Component | Option A | Option B | Option C | Option D |
| --- | --- | --- | --- | --- |
| Primary Data Storage | TBC | TBC | TBC | TBC |
| Snowflake credits | £1,000-1,500 | £1,340-2,090 | £0 | £0 |
| SiteWise | £0 | £0 | £1,560 | £0 |
| Timestream | £0 | £0 | £3,170 | £790 |
| AWS Infrastructure |  |  |  |  |
| IoT Core | £125 | £125 | £198 | £198 |
| Kinesis | £167 | £84 | £0 | £91 |
| Lambda | £167 | £42 | £18 | £7 |
| EMR (Flink) | £250 | £0 | £0 | £0 |
| DynamoDB | £42 | £42 | £13 | £16 |
| CloudWatch | £84 | £42 | £250 | £316 |
| API Gateway | £84 | £42 | £15 | £15 |
| Grafana Cloud | £0 | £0 | £0 | £242 |
| TOTAL | £2,100-3,500 | £1,800-2,900 | £5,300 | £3,300 |


Key Cost Findings:

• Option B (Snowflake) is the most cost-effective at est. £60-97/tenant (30 tenant scenario)

• Option C is the most expensive due to dual storage requirements (SiteWise + Timestream)

• All options remain cost-effective constraint

• Option C costs were corrected from an initial estimate of £17,650/month (70% reduction)

## Multi-Tenancy Security Comparison

Multi-tenancy is a critical requirement for the SMDH platform. The following comparison evaluates the security, implementation complexity, and maintenance requirements of each option's multi-tenancy approach.


| Option | Method | Security Level | Implementation | Maintenance |
| --- | --- | --- | --- | --- |
| A: Flink | Snowflake RLS | Excellent | Good | Low |
| B: Snowflake | Snowflake RLS | Excellent | Excellent | Low |
| C: SiteWise | Tags + App Layer | Moderate | Difficult | High |
| D: Timestream | Partition Keys | Good | Good | Low |


Key Multi-Tenancy Concerns:

Option C (SiteWise) Multi-Tenancy Risks:

• No native Row-Level Security: Must filter by tags in every API query

• Application-layer risk: Developer error could expose tenant data

• Higher audit complexity: Requires custom logging for data access

• Not SaaS-native: SiteWise designed for single-enterprise use, not multi-tenant SaaS

Options B and D offer native, secure, minimal-code multi-tenancy

## Dashboard and Visualisation Comparison

The dashboard solution impacts both user experience and development effort. This comparison evaluates white-labeling capabilities, multi-tenancy support, embedding options, and costs.


| Option | Solution | White-Labeling | Multi-Tenancy | Embeddable | Cost |
| --- | --- | --- | --- | --- | --- |
| A | QuickSight | Limited | Manual | Yes | £15/user/month |
| B | QuickSight | Limited | Manual | Yes | £15/user/month |
| C | Custom React | Full | Custom | Yes | Dev time (included) |
| D | Grafana Cloud | Full | Native Orgs | Yes (free) | £242/month |


Grafana Advantages (Option D):

• Industry-standard for time-series visualisation

• Multi-tenant organisations with built-in tenant isolation

• Full white-labeling (custom logo, colours, domain)

• 100+ data sources (platform-agnostic)

• Free embedding (no per-session charges)

• Advanced alerting capabilities

Option C Dashboard Challenge:

• SiteWise Monitor cannot be white-labeled for SaaS applications

• Requires building custom React dashboards from scratch

• Additional development time: 4-6 weeks

• Ongoing maintenance burden for updates and new features

## Implementation Timeline Breakdown

The following table breaks down the implementation timeline by project phase for each architecture option.


| Phase | Option A | Option B | Option C | Option D | Notes |
| --- | --- | --- | --- | --- | --- |
| Foundation | 3 weeks | 3 weeks | 3 weeks | 3 weeks | VPC, Cognito, IoT Core |
| Data Ingestion | 3 weeks | 2 weeks | 4 weeks | 3 weeks | C: SiteWise asset models |
| Use Cases | 4 weeks | 3 weeks | 5 weeks | 3 weeks | C: Custom dashboards |
| ML Features | 3 weeks | 2 weeks | 3 weeks | 2 weeks | Anomaly detection, predictive |
| Testing & Hardening | 3 weeks | 2 weeks | 5 weeks | 3 weeks | C: Multi-tenant security testing |
| Contingency Buffer | 4 weeks | 4 weeks | 4 weeks | 4 weeks | Risk mitigation |
| TOTAL | 24 weeks | 20 weeks | 28 weeks | 22 weeks |  |


Time to Market Analysis:

• Option B (Snowflake): 20 weeks - fastest time to market

• Option D (Timestream + Grafana): 22 weeks - 2 weeks slower than B

• Option A (Flink): 24 weeks - 4 weeks slower than B

• Option C (SiteWise): 28 weeks - 8 weeks slower than B (slowest due to custom dashboard development)

## Risk Assessment by Option

This section identifies critical, medium, and low risks for each architecture option.

Option A (Flink) - Highest Risk

Critical Risks:

• Flink operational complexity (High likelihood, High impact)

• Team skill gaps in Flink/Java (High likelihood, High impact)

Medium Risks:

• Multi-service debugging difficulty (High likelihood, Medium impact)

Option B (Snowflake) - Lowest Risk

Critical Risks:

• Alert latency SLA violation (High likelihood, High impact) - Fixable with Lambda fast-path

Medium Risks:

• Cortex ML limitations for advanced use cases (Medium likelihood, Medium impact)

Low Risks:

• Snowflake vendor lock-in (Medium likelihood, Low impact)

Option C (SiteWise) - Medium-High Risk

Critical Risks:

• Manual multi-tenancy implementation (Medium likelihood, High impact) - Data exposure risk

Medium Risks:

• Dual storage architecture complexity (High likelihood, Medium impact)

• Custom dashboard maintenance burden (High likelihood, Medium impact)

• SiteWise learning curve for team (High likelihood, Medium impact)

Option D (Timestream + Grafana) - Medium-Low Risk

Medium Risks:

• Timestream query cost spikes (Low likelihood, Medium impact)

• Custom asset modelling required (Medium likelihood, Medium impact)

Low Risks:

• Grafana multi-tenancy configuration (Low likelihood, Medium impact)

Risk Summary:

• Lowest Risk: Option B (1 critical risk, fixable with Lambda)

• Medium-Low Risk: Option D (0 critical risks, manageable medium risks)

• Medium-High Risk: Option C (1 critical multi-tenancy risk)

• Highest Risk: Option A (2 critical operational and skills risks)

## Decision Criteria and Use Case Suitability

This section provides guidance on when to choose each architecture option based on specific business constraints and technical requirements.

When to Choose Option A (Flink) - ONLY IF:

- Sub-second latency is legally/regulatorily required

- Custom deep learning models confirmed need

- Team has or can hire Flink expertise

- consumption costs support highest total cost of ownership

- 24-week timeline acceptable

- Prepared for very high operational complexity

When to Choose Option B (Snowflake)

- Cost and simplicity are top priorities

- Team is SQL-skilled or can train quickly

- 60-second alert latency acceptable (or can add Lambda fast-path)

- Want fastest time to market (20 weeks)

- Prefer unified data governance platform

- Snowflake licensing not a blocker

When to Choose Option D (Timestream + Grafana)

- AWS-native is mandatory (no Snowflake allowed)

- Want industry-best time-series dashboards (Grafana)

- Need native partition-based multi-tenancy

- Comfortable with 10-15% cost premium vs Option B

- Team has AWS expertise (no Snowflake learning curve)

- Unified storage for time-series and discrete events

When to Choose Option C (SiteWise)

- Already heavily invested in AWS IoT ecosystem

- Team has deep SiteWise expertise (rare)

- Single-tenant or <10 tenants (multi-tenancy less critical)

- Prefer AWS-managed asset modelling

- consumption patterns result in est. £167-210/tenant (30 tenant scenario)

- Can accept manual multi-tenant isolation risk

- Willing to build custom React dashboards (4-6 weeks)

Note - Not recommended for: Multi-tenant SaaS at scale (30-100 tenants)

## Decision Framework

The following decision tree provides a systematic approach to selecting the appropriate architecture option based on your primary constraints:

What are your constraints?

1. Is AWS-native required (no Snowflake)?

→ YES: Choose Option D (Timestream + Grafana)

→ NO: Continue to question 2

2. Is cost/simplicity the top priority?

→ YES: Choose Option B (Snowflake) - RECOMMENDED

→ NO: Continue to question 3

3. Do you have less than 10 tenants?

→ YES: Consider Option C (SiteWise)

→ NO: Continue to question 4

4. Is sub-second latency legally required?

→ YES: Choose Option A (Flink)

→ NO: Default to Option B (Snowflake) - RECOMMENDED

RECOMMENDATION: Choose Option B (Snowflake) - Best for all but real time scenarios

## Key Comparison Findings

1. All Options Are Economically Viable

2. Multi-Tenancy Security is a Critical Differentiator

Options B (Snowflake) and D (Timestream) offer native, database-level multi-tenancy with Row-Level Security and partition keys respectively.

Option C (SiteWise) requires manual application-layer filtering by tags, which introduces security risks and maintenance overhead for a multi-tenant SaaS platform.

3. Option B Alert Latency is Addressable

Whilst Option B (Snowflake) does not natively meet the <10-second alert latency requirement (60-65 seconds), this can be resolved by implementing a Lambda fast-path for critical alerts. This would add approximately £100-125/month and 2 weeks to the timeline.

4. Time to Market Varies by 8 Weeks

Option B (Snowflake) delivers the fastest time to market at 20 weeks

Option C (SiteWise) requires 28 weeks due to custom dashboard development.

# Recommendations

## Primary Recommendation: Option B (Snowflake) with Lambda Fast-Path

Based on the comprehensive analysis in Section 7, we recommend Option B (Snowflake-Leveraged Architecture) as the primary solution for the Smart Manufacturing Data Hub.

Why Option B:

- Lowest cost: £1,800-2,900/month (est. £60-97/tenant for 30 tenants)

- Simplest architecture: Only 5 core services

- Fastest time to market: 20 weeks

- Native multi-tenancy: Snowflake Row-Level Security

- Unified data platform: Single governance layer

- SQL-first approach: Leverages existing team skills

- Lowest risk: Proven technology stack

Optional Enhancement:

To meet the <10-second alert latency requirement (FR-11), implement a Lambda fast-path for critical alerts:

- Additional cost: £100-125/month

- Additional timeline: 2 weeks

- Implementation: AWS Lambda processes high-frequency data streams and triggers CloudWatch alarms for threshold violations

## Implementation Roadmap

For the recommended Option B (Snowflake), the following implementation phases are proposed. These cover all aspects of the delivery and are just high level assumptions around activities and time at this stage.

Phase 1: Foundation (Weeks 1-3)

- Set up AWS VPC, security groups, and networking

- Configure Amazon Cognito for authentication

- Establish AWS IoT Core for device connectivity

- Provision Snowflake account and database with Row-Level Security

Phase 2: Data Ingestion (Weeks 4-5)

- Implement Snowpipe Streaming for real-time ingestion

- Configure data validation and transformation logic

- Set up multi-tenant data partitioning

- Develop Lambda fast-path for critical alerts

Phase 3: Use Cases (Weeks 6-8)

- Implement machine utilisation monitoring dashboard

- Develop air quality management alerts and reporting

- Build energy monitoring with cost analysis

- Create job location tracking interface

Phase 4: ML Features (Weeks 9-10)

- Integrate Snowflake Cortex for anomaly detection

- Develop predictive maintenance models

- Implement energy optimisation recommendations

Phase 5: Testing & Hardening (Weeks 11-12)

- Multi-tenant security testing and penetration testing

- Load testing with 30+ concurrent tenants

- Disaster recovery and backup validation

- Documentation and training materials

Phase 6: Pilot & Refinement (Weeks 13-16)

- Onboard 3-5 pilot tenants

- Gather feedback and refine features

- Performance optimisation

- Contingency buffer for unforeseen issues

## Next Steps

Immediate Actions (Next 2 Weeks):

- Stakeholder decision meeting to confirm Option B

- Detailed design for infrastructure build

- Refinement of cost estimates

- Vendor engagement (Snowflake Solutions Architect or AWS IoT specialist)

Short-Term Actions (Weeks 3-4):

- Architecture detailed documentation

- Refined project plan with resource allocation

- AWS account setup and cost planning

# Glossary

This glossary provides plain-English explanations of technical terms used throughout this document.

Amazon CloudWatch: AWS monitoring service that collects and tracks metrics, logs, and sets alarms for AWS resources and applications.

Amazon Cognito: AWS service providing user authentication, authorisation, and user management for web and mobile applications.

Amazon DynamoDB: AWS fully managed NoSQL database service providing fast and predictable performance with seamless scalability.

Amazon Kinesis: AWS platform for streaming data on AWS, allowing real-time processing of large streams of data records.

Amazon QuickSight: AWS business intelligence service for creating and publishing interactive dashboards with ML-powered insights.

Amazon Timestream: AWS fully managed time-series database service optimised for IoT and operational applications.

Apache Flink: Open-source stream processing framework for distributed, high-performance data streaming applications.

API Gateway: AWS service for creating, publishing, maintaining, monitoring, and securing APIs at any scale.

AWS IoT Core: AWS managed cloud service that lets connected devices interact with cloud applications and other devices securely.

AWS IoT SiteWise: AWS managed service that makes it easy to collect, store, organise, and monitor data from industrial equipment at scale.

AWS Lambda: AWS serverless compute service that runs code in response to events without provisioning or managing servers.

Data Lake: Centralised repository that allows storage of structured and unstructured data at any scale for analytics.

EMR (Elastic MapReduce): AWS cloud-native big data platform for processing vast amounts of data using open-source tools such as Apache Spark and Hadoop.

Grafana: Open-source analytics and interactive visualisation platform, industry-standard for time-series data dashboards.

IoT (Internet of Things): Network of physical devices embedded with sensors, software, and connectivity to exchange data with other devices and systems.

Machine Learning (ML): Branch of artificial intelligence focused on building systems that learn from data to make predictions or decisions.

MQTT (Message Queuing Telemetry Transport): Lightweight messaging protocol designed for constrained devices and low-bandwidth, high-latency networks, commonly used in IoT.

Multi-Tenancy: Software architecture where a single instance of the application serves multiple customers (tenants) with data isolation between them.

OEE (Overall Equipment Effectiveness): Manufacturing metric that measures the percentage of planned production time that is truly productive (Availability × Performance × Quality).

Partition Key: Database key used to distribute data across multiple storage nodes for scalability and to enable data isolation in multi-tenant systems.

Real-Time Processing: Computing approach where data is processed immediately as it arrives, typically within milliseconds to seconds.

Row-Level Security (RLS): Database security feature that restricts which rows a user can access in a table based on user attributes or roles.

SaaS (Software as a Service): Software distribution model where applications are hosted by a service provider and made available to customers over the internet.

Snowflake: Cloud-based data warehousing platform that provides data storage, processing, and analytics services with automatic scaling.

Snowpipe: Snowflake continuous data ingestion service that loads data within minutes after files are added to a cloud storage location.

SQL (Structured Query Language): Standard programming language for managing and manipulating relational databases.

Stream Processing: Real-time processing of continuous data streams, analysing data as it flows through the system.

Telemetry: Automated communications process for collecting measurements and data from remote or inaccessible points and transmitting to receiving equipment.

Time-Series Data: Sequence of data points indexed in time order, typically consisting of successive measurements from the same source over time intervals.

VPC (Virtual Private Cloud): AWS logically isolated virtual network that you define, providing complete control over networking environment including IP address range, subnets and security settings.

---

Cost Methodology Note: All costs presented in this document are based on actual data consumption patterns and infrastructure usage. Costs will scale linearly with data volume, device count, and query patterns. The estimates provided use the specified data volumes: 2.6M-3.9M rows/day, 30 tenants, 117M values/month.

# Appendix A: Capacity Calculation Details

This appendix provides detailed capacity calculations showing how per-tenant and platform-wide data volumes were derived from requirements.

## Machine Data Calculation

Per Tenant (30 machines):

• Machines: 30, Properties: 30, Sampling: 1 Hz
• Calculation: 30 × 86,400 seconds = 2,592,000 rows/day per tenant
• Platform (30 tenants): 77,760,000 rows/day = 2.33B rows/month

## Energy & Air Quality Calculations

• Energy Meters: 10 meters × 1,440 min/day = 14,400 rows/day per tenant
• Air Quality: 5 sensors × 1,440 min/day = 7,200 rows/day per tenant
• Job Events: 50 jobs × 10 events = 500 rows/day per tenant
• Total per Tenant: ~2.6M rows/day
• Total Platform (30 tenants): ~78M rows/day = 2.35B rows/month