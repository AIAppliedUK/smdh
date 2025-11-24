# Smart Manufacturing Data Hub (SMDH) - AWS Architecture Design

## 1. Executive Summary

### 1.1 What We're Building

The SMDH platform is a multi-tenant IoT analytics system that collects data from manufacturing facilities via native MQTT protocol and provides real-time insights. The architecture optimises for persistent, high-frequency sensor connections while maintaining strict tenant isolation for up to 30 manufacturing SMEs.

### 1.2 Core Architecture Principle

**MQTT is the universal IoT protocol.**

The SMDH platform uses AWS IoT Core as a managed MQTT broker. All sensor data sources connect via MQTT - either directly (DevTank OSM with Wi-Fi) or through LoRaWAN gateways (Milesight UG65). This single, protocol-native approach provides:

- Persistent connections for high-frequency sensors (1 Hz updates)
- Native QoS guarantees (at-least-once delivery)
- Built-in device registry and authentication
- Integrated buffering and ordering via Kinesis

No custom validation layers, no HTTP polling overhead, no protocol conversions—just pure MQTT from edge to cloud.

### 1.3 Key Business Drivers

| Driver                        | Architectural Impact                       |
| ----------------------------- | ------------------------------------------ |
| **Up to 30 separate tenants** | Database-per-tenant isolation in Snowflake |
| **5-10 sensors per site**     | Modest but steady streaming data volume    |
| **MQTT-native sensors**       | AWS IoT Core as central MQTT broker        |
| **Real-time monitoring**      | Sub-minute data latency requirements       |
| **Distributed gateways**      | Multi-AZ deployment, regional endpoints    |

---

## 2. Requirements Traceability

### 2.1 Functional Requirements

| Requirement                          | Description                                             | Architecture Solution                                            |
| ------------------------------------ | ------------------------------------------------------- | ---------------------------------------------------------------- |
| **FR-001: MQTT ingestion**           | Support MQTT-based sensors via gateways and Wi-Fi       | IoT Core as managed MQTT broker with multi-AZ high availability |
| **FR-002: Real-time processing**     | <1 minute from sensor to dashboard for critical metrics | Streaming architecture with Kinesis and Dynamic Tables           |
| **FR-003: Historical analysis**      | Store 2+ years of data for trend analysis               | Snowflake with Time Travel and configurable retention            |
| **FR-004: Multi-tenancy**            | Complete data isolation between customers               | Database-per-tenant in Snowflake, X.509 certs per tenant         |
| **FR-005: Persistent connections**   | Handle continuous sensor streams with QoS guarantees    | IoT Core QoS 1/2, Kinesis buffering, ordering per tenant         |

### 2.2 Non-Functional Requirements

| Requirement                  | Description                                                                          | Architecture Solution                                          |
| ---------------------------- | ------------------------------------------------------------------------------------ | -------------------------------------------------------------- |
| **NFR-001: Scalability**     | Handle up to 300 sensors across 30 sites at 1 Hz frequency (~26M messages/day total) | Auto-scaling serverless components (Lambda, Kinesis on-demand) |
| **NFR-002: Availability**    | 99.9% uptime for data ingestion                                                      | Multi-AZ deployment, managed services with SLAs                |
| **NFR-003: Security**        | End-to-end encryption, audit logging                                                 | TLS everywhere, CloudTrail, Snowflake audit logs               |
| **NFR-004: Performance**     | Sub-second API response times                                                        | API Gateway caching, Snowflake result cache                    |
| **NFR-005: Maintainability** | Minimal operational overhead                                                         | Managed services, Infrastructure as Code                       |

### 2.3 Constraints

| Constraint                                            | Impact on Architecture                                     |
| ----------------------------------------------------- | ---------------------------------------------------------- |
| **MQTT devices cannot connect directly to Snowflake** | Must use AWS IoT Core as managed MQTT broker               |
| **Snowflake has no native MQTT support**              | Requires intermediate streaming service (Kinesis)          |
| **X.509 certificates expire**                         | Automated rotation via AWS Certificate Manager or Secrets  |
| **IoT devices require network connectivity**          | Multi-AZ regional deployment, connection state monitoring  |

---

## 3. Component Architecture

### 3.1 Data Ingestion Layer

#### 3.1.1 AWS IoT Core (MQTT Broker)

Acts as the MQTT broker for all IoT devices. Maintains persistent connections with thousands of sensors, handles connection management, and routes messages to downstream services via the IoT Rules Engine.

**Capabilities:**

- MQTT v3.1.1 and v5.0 protocol support
- Device registry for managing X.509 certificates and metadata
- Connection state management, reconnection, and offline message queuing
- QoS 0 and 1 support for reliable message delivery (SMDH uses QoS 1 for at-least-once guarantee)
- Topic-based access control (ACLs) per tenant
- Built-in monitoring via CloudWatch metrics

**Why it's needed:**

All sensor data arrives via MQTT through Milesight UG65 gateways and DevTank OSM devices, so AWS IoT Core provides the central authentication point for distributed edge devices, manages certificate lifecycles without custom application logic, keeps persistent connections for high-frequency sensors (1 Hz+), and integrates natively with Kinesis through the IoT Rules Engine.

**Traceability**

- FR-001: Enables MQTT protocol support for all sensor types
- FR-005: Maintains persistent connections with QoS guarantees
- NFR-001: Auto-scales to handle 26M+ messages/day
- NFR-003: Certificate-based authentication (X.509)

#### 3.1.2 Kinesis Data Streams

Buffers and orders streaming data between IoT Core and Snowflake. Provides temporary storage for high-velocity data streams with guaranteed ordering per partition.

- IoT Core generates data faster than Snowflake can ingest individual messages
- Provides replay capability if downstream processing fails with 24-hour retention window
- Maintains message ordering within tenant partitions
- Enables multiple consumers (future real-time analytics)
- On-demand capacity mode auto-scales with message volume

**Traceability**

- FR-002: Enables real-time processing pipeline
- NFR-001: Handles high-throughput streaming data
- NFR-002: Provides durability with multi-AZ replication

Required when using IoT Core for MQTT ingestion. Optional for HTTP if buffering is needed.

#### 3.1.3 AWS IoT Thing Groups (Device Organization)

Provides hierarchical device management and organization across tenants and sites. Thing Groups enable bulk operations, cost tracking, health monitoring, and logical grouping of devices without requiring database queries.

**Capabilities:**

- **Hierarchical Structure**: Parent-child relationships for tenant → sites → devices organization
- **Static Groups**: Manually managed groups for organizational structure (tenant-level, site-level)
- **Dynamic Groups**: Query-based groups that automatically track device states (disconnected, active)
- **Bulk Operations**: Apply updates, configurations, or queries to all devices in a group
- **Cost Allocation**: Tag-based cost tracking at tenant and site level
- **Fleet Indexing**: Search and query devices across groups with AWS IoT Fleet Indexing

**SMDH Thing Group Hierarchy:**

```
Tenant Thing Group (smdh-tenant-{tenant_id})
├── Site Thing Group (smdh-{tenant_id}-site_001)
│   ├── Gateway: smdh-gateway-{tenant_id}-site_001-gw_001
│   ├── Gateway: smdh-gateway-{tenant_id}-site_001-gw_002
│   └── ... (additional gateways per site)
├── Site Thing Group (smdh-{tenant_id}-site_002)
│   └── Gateway: smdh-gateway-{tenant_id}-site_002-gw_001
├── Dynamic Group: smdh-{tenant_id}-disconnected (auto-tracks offline devices)
└── Dynamic Group: smdh-{tenant_id}-active (auto-tracks active devices)
```

**Why Thing Groups are needed:**

- **Simplified Operations**: Query all devices for a tenant with a single recursive command instead of database queries
- **Site-Level Management**: Apply firmware updates or configuration changes to all devices at a specific site
- **Health Monitoring**: Automatically track disconnected or problematic devices via dynamic groups
- **Organizational Clarity**: Mirror the business structure (tenant → sites → devices) in AWS IoT
- **Cost Visibility**: Tag thing groups to track IoT costs per tenant and per site
- **Snowflake Integration**: Sync thing group hierarchy to Snowflake infrastructure tables for unified device management

**Key Operations Enabled:**

```bash
# List all devices for a tenant (recursive includes all site groups)
aws iot list-things-in-thing-group \
  --thing-group-name "smdh-tenant-company_a" \
  --recursive --region eu-west-2

# List devices at a specific site
aws iot list-things-in-thing-group \
  --thing-group-name "smdh-company_a-site_001" \
  --region eu-west-2

# Check disconnected devices (uses dynamic group)
aws iot list-things-in-thing-group \
  --thing-group-name "smdh-company_a-disconnected" \
  --region eu-west-2
```

**Traceability:**

- FR-004: Supports multi-tenant device isolation and organization
- FR-005: Enables efficient device connection state monitoring
- NFR-001: Scales to support 300+ devices across 30 tenants
- NFR-005: Reduces operational overhead for device management

### 3.2 IoT Rules Engine

Routes and filters MQTT messages from IoT Core to Kinesis. Implements multi-tenant routing and error handling without custom code.

**Capabilities:**

- SQL-based topic pattern matching (e.g., `smdh/{tenant_id}/+/sensor-data`)
- Message transformation and enrichment
- Conditional routing (filter before forwarding)
- Error handling with configurable dead-letter topics
- CloudWatch metrics for monitoring

**Why it's needed:**

- Extracts tenant context from MQTT topic path
- Routes messages to correct Kinesis partition per tenant
- Republishes failures to error topics for investigation
- Reduces dependency on custom processing code

**Traceability**

- FR-001: Routes MQTT messages based on tenant
- FR-004: Enforces tenant isolation via topic ACLs
- FR-005: Guarantees ordered delivery per partition

### 3.3 Snowflake Integration

**Overview:**

Kinesis streams integrate with Snowflake via the Snowflake Openflow Kinesis Connector (native integration). This is an external system to AWS but critical for the complete data pipeline.

**Integration Requirements:**

- Snowflake account must exist in eu-west-2 (same region as Kinesis)
- Cross-account IAM role configured in AWS to allow Snowflake to read from Kinesis
- Openflow connector configured per tenant to route Kinesis streams to Snowflake databases
- Each tenant gets isolated database: `smdh_tenant_{tenant_id}`

**Key AWS Configuration for Snowflake Integration:**

1. **IAM Role** for Snowflake Openflow connector
   - Allows Snowflake to assume role and read Kinesis streams
   - Restricts access to specific Kinesis streams only
   - External ID required for security

2. **Secrets Manager Secret**
   - Stores Snowflake private key for JWT authentication
   - Used by Snowflake to sign requests to Kinesis
   - Automatic rotation before expiry

3. **Kinesis Stream Naming**
   - Stream: `smdh-sensor-data-stream`
   - Partitioned by `{tenant_id}` to route messages to correct tenant database
   - On-demand capacity scales automatically with message volume

**Traceability**

- FR-002: Real-time data flow from Kinesis to Snowflake
- FR-004: Tenant isolation enforced via partition keys
- NFR-002: High availability via multi-AZ Kinesis replication

### 3.4 Supporting Services

#### 3.4.1 AWS Secrets Manager

Securely stores and rotates sensitive credentials like Snowflake private keys, API keys, and connection strings.

- Lambda functions need Snowflake credentials
- Enables automatic credential rotation
- Provides audit trail for credential access
- Encrypts secrets at rest and in transit

**Traceability**

- NFR-003: Secure credential management
- NFR-005: Automated rotation reduces operational burden

#### 3.4.2 CloudWatch

Centralised monitoring and logging for all AWS services. Collects metrics, stores logs, and triggers alarms.

**Why it's needed:**

- Single pane of glass for system health
- Automated alerting for issues
- Performance metrics for optimisation
- Audit trail for compliance

**Traceability**

- NFR-002: Monitoring for availability targets
- NFR-003: Audit logging for security
- NFR-005: Automated alerting reduces manual monitoring

---

## 4. Data Flow Patterns

### 4.1 MQTT Sensor Data Flow

**Scenario:** Manufacturing facility with multiple sensor types sending continuous data

**Devices in scope:**

- Milesight UG65 LoRaWAN gateways (collect sensor data via 868 MHz radio)
- DevTank OpenSmartMonitor (air quality, energy, environment via Wi-Fi MQTT or LoRaWAN)
- Generic LoRaWAN sensors (temperature, vibration, state monitoring)

**End-to-end data flow:**

```
1. Sensor Generation
   └─ Milesight UG65 Gateway or DevTank OSM
   └─ Frequency: 1 Hz (sensors) to 1 min (air quality)

2. MQTT Publish (TLS 1.3)
   └─ Milesight UG65 → AWS IoT Core
      Topic: smdh/{tenant_id}/sensor-data
      Authentication: X.509 certificate
   └─ DevTank OSM → AWS IoT Core (Wi-Fi)
      Topic: smdh/{tenant_id}/devtank-data
      Authentication: X.509 certificate

3. IoT Rules Engine Routing
   └─ SQL: SELECT *, '{tenant_id}' as tenant_id FROM 'smdh/+/+'
   └─ Validates message structure
   └─ Routes to Kinesis with tenant partition key

4. Kinesis Buffering & Ordering
   └─ Partition: {tenant_id}
   └─ Guarantees: In-order delivery per tenant, 24h retention
   └─ Throughput: On-demand, auto-scales with message volume

5. Snowflake Openflow Integration
   └─ Native Kinesis connector (preview feature)
   └─ Reads from Kinesis stream
   └─ Writes to smdh_tenant_{tenant_id}.raw.sensor_readings
   └─ Latency: 5-15 seconds end-to-end

6. Snowflake Processing
   └─ Streams detect new data in raw tables
   └─ Tasks normalize and transform (Python/SQL)
   └─ Dynamic Tables aggregate to business metrics
   └─ Cortex ML detects anomalies

7. Analytics & Visualization
   └─ Power BI: DirectQuery for real-time dashboards
   └─ Streamlit: Native portal within Snowflake
   └─ Users see data within 1-2 minutes of sensor reading
```

**Why this architecture:**

- All sensors are MQTT-native (gateways and devices)
- Persistent connections handle continuous 1 Hz streams
- X.509 certificates provide strong device authentication
- Topic-based routing inherently multi-tenant
- Kinesis provides buffering without custom code
- No Lambda/validation layers = lower latency and cost

---

## 5. Multi-Tenancy Strategy

### 5.1 Isolation Levels

| Layer                 | Isolation Method                              | Rationale                                          |
| --------------------- | --------------------------------------------- | -------------------------------------------------- |
| **Device Level**      | Separate X.509 certificates per gateway       | Prevents device spoofing, enables revocation       |
| **Thing Group Level** | Hierarchical thing groups per tenant/site     | Organizational isolation, bulk operations per tenant |
| **Topic Level**       | Topic ACLs enforce `smdh/{tenant_id}/*` path  | Prevents cross-tenant topic access at IoT Core    |
| **Rules Level**       | IoT Rules extract tenant from topic            | Validates tenant context before Kinesis routing    |
| **Partition Level**   | Kinesis partitioned by {tenant_id}             | In-order delivery, isolation per tenant            |
| **Database Level**    | Separate database per tenant in Snowflake      | Complete storage isolation                         |
| **Application Level** | Role-based access control in Snowflake         | Users only see their tenant's data                 |

### 5.2 Why Database-per-Tenant?

**Chosen approach:** Each tenant gets their own Snowflake database (e.g., `smdh_tenant_company_a`)

**Advantages:**

- **Fail-closed security**: Wrong database name = error, not data leak
- **Independent operations**: Can maintain one tenant without affecting others
- **Clear compliance**: Physical separation satisfies most regulations
- **Simple disaster recovery**: Can restore single tenant
- **Independent retention**: Different data retention per tenant

**Trade-offs accepted:**

- More databases to manage (automated via IaC)
- Cross-tenant analytics require data sharing (rare requirement)

---

## 6. Scalability Considerations

### 6.1 Current Scale

| Metric                  | Per Site  | 30 Sites Maximum |
| ----------------------- | --------- | ---------------- |
| **Sensors**             | 5-10      | 150-300          |
| **Messages/day (1 Hz)** | 432K-864K | 13-26M           |
| **Data volume/day**     | 50-200 MB | 1.5-6 GB         |
| **Concurrent users**    | 2-5       | 60-150           |

### 6.2 Scaling Strategy

**Horizontal scaling points:**

- **IoT Core**: Automatically scales to millions of connections
- **Kinesis**: On-demand mode scales with throughput
- **Lambda**: Concurrent execution scales to 1000s
- **Snowflake**: Multi-cluster warehouses for compute scaling

**Vertical scaling points:**

- **Snowflake warehouse size**: Start Small, scale to Large as needed
- **Lambda memory**: Start at 512MB, increase if processing is slow

---

## 7. AWS Account & Network Architecture

### 7.1 AWS Account Structure

**Single-Account Strategy:**

The SMDH platform operates in a single production AWS account in `eu-west-2` (London region).

```
AWS Account: 123456789012 (smdh-production)
├─ Region: eu-west-2 (London) - Primary
├─ Services:
│  ├─ AWS IoT Core (Global via regional endpoint)
│  ├─ Kinesis Data Streams (Regional)
│  ├─ Secrets Manager (Regional)
│  └─ CloudWatch (Regional)
└─ High Availability: Multi-AZ within region
```

**Rationale:**

- Simplified billing and cost allocation
- Single security boundary for compliance
- No cross-account authentication complexity
- IoT Core and Kinesis are regional services (benefits from multi-AZ)

### 7.2 VPC Configuration

**VPC Design Principle:** IoT devices are internet-connected; AWS services are either fully managed (serverless) or connect via managed endpoints.

```
┌─────────────────────────────────────────────────────────┐
│ AWS Account (eu-west-2)                                 │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  ┌────────────────────────────────────────────────────┐ │
│  │ AWS IoT Core (Fully Managed - Public Endpoint)     │ │
│  ├────────────────────────────────────────────────────┤ │
│  │ - Regional endpoint: *.iot.eu-west-2.amazonaws.com │ │
│  │ - No VPC required (managed service)                │ │
│  │ - TLS 1.2/1.3 encryption in transit                │ │
│  │ - Multi-AZ redundancy built-in                     │ │
│  └────────────────────────────────────────────────────┘ │
│                         ↓                                │
│  ┌────────────────────────────────────────────────────┐ │
│  │ IoT Rules Engine (Managed)                         │ │
│  │ Routes MQTT → Kinesis with tenant context          │ │
│  └────────────────────────────────────────────────────┘ │
│                         ↓                                │
│  ┌────────────────────────────────────────────────────┐ │
│  │ Kinesis Data Streams (Fully Managed)               │ │
│  ├────────────────────────────────────────────────────┤ │
│  │ - Multi-AZ by default                             │ │
│  │ - No VPC configuration needed                      │ │
│  │ - Accessed via AWS API (no IP addresses)           │ │
│  └────────────────────────────────────────────────────┘ │
│                         ↓                                │
│  ┌────────────────────────────────────────────────────┐ │
│  │ Snowflake Openflow Connector                       │ │
│  │ (Runs within Snowflake account, not in AWS VPC)    │ │
│  │ Reads from Kinesis via IAM role cross-account      │ │
│  └────────────────────────────────────────────────────┘ │
│                                                          │
│  ┌────────────────────────────────────────────────────┐ │
│  │ Secrets Manager (Fully Managed)                    │ │
│  ├────────────────────────────────────────────────────┤ │
│  │ - Stores Snowflake private key                     │ │
│  │ - No VPC needed (managed service)                  │ │
│  │ - Accessed via AWS API                             │ │
│  └────────────────────────────────────────────────────┘ │
│                                                          │
│  ┌────────────────────────────────────────────────────┐ │
│  │ CloudWatch (Fully Managed)                         │ │
│  ├────────────────────────────────────────────────────┤ │
│  │ - Metrics from IoT Core, Kinesis, Rules Engine     │ │
│  │ - Logs from all AWS services                       │ │
│  │ - No VPC needed (managed service)                  │ │
│  └────────────────────────────────────────────────────┘ │
│                                                          │
└─────────────────────────────────────────────────────────┘

External Connections:
├─ Internet (Gateways/Devices) → AWS IoT Core (Public)
│  └─ TLS 1.3, port 8883 (MQTT)
└─ Snowflake (Cross-Account) → Kinesis via IAM Role
   └─ Service-to-service, no internet
```

### 7.3 No VPC Required

**Why we don't need a VPC:**

All SMDH AWS components are **fully managed services** that don't require VPC hosting:

| Service              | Type           | Network Access               | VPC Required? |
| -------------------- | -------------- | ---------------------------- | ------------- |
| **IoT Core**         | Managed        | Public endpoint via internet  | No            |
| **Kinesis**          | Managed        | AWS API (internal)            | No            |
| **Secrets Manager**   | Managed        | AWS API (internal)            | No            |
| **CloudWatch**       | Managed        | AWS API (internal)            | No            |
| **IAM**              | Managed        | Control plane only            | No            |

**Trade-off:** No VPC means:
- ✓ Simpler architecture, fewer components
- ✓ No NAT gateways, no subnet management
- ✓ Lower operational overhead
- ✓ Multi-AZ redundancy automatic
- ✗ IoT Core endpoint is internet-facing (mitigated by X.509 certs)

### 7.4 Network Security Controls

**At IoT Core:**

1. **TLS 1.3 Encryption** - All MQTT connections must use TLS
2. **X.509 Certificate Authentication** - Device identity verified
3. **Topic ACLs** - Policy restricts devices to `smdh/{tenant_id}/*` topics only
4. **Connection Policies** - Limits allowed actions per certificate

**Example IoT Policy:**

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "iot:Connect",
      "Resource": "arn:aws:iot:eu-west-2:*:client/smdh-gateway-TENANT_ID-*"
    },
    {
      "Effect": "Allow",
      "Action": "iot:Publish",
      "Resource": "arn:aws:iot:eu-west-2:*:topic/smdh/TENANT_ID/*"
    }
  ]
}
```

**At Kinesis:**

1. **IAM Role-based Access** - Only Snowflake role can read
2. **Encryption at Rest** - AWS managed keys (customer keys optional)
3. **CloudTrail Logging** - All API calls logged

---

## 8. Security Architecture

### 8.1 Defense in Depth

| Layer           | Security Control                                       |
| --------------- | ------------------------------------------------------ |
| **Network**     | TLS 1.3 for all MQTT connections, regional endpoints  |
| **Identity**    | X.509 certificates for devices (managed by AWS IoT)    |
| **Access**      | Topic ACLs + IoT policies restrict per tenant          |
| **Data**        | Encryption at rest (Kinesis) and in transit (TLS)      |
| **Secrets**     | Secrets Manager for certificate rotation               |
| **Monitoring**  | CloudTrail, CloudWatch metrics, Snowflake audit logs   |

### 8.2 Key Security Decisions

**Device authentication:** X.509 certificates (AWS IoT Core managed)

- Reason: Industry standard for IoT, can be revoked, non-repudiation
- Implementation: Auto-generate, store securely, rotate before expiry
- Fallback: Manual certificate generation if needed

**Topic Isolation:** MQTT topic patterns enforced by IoT policies

- Reason: Prevents cross-tenant message injection
- Example: Device with tenant_a cert cannot publish to smdh/tenant_b/*
- Enforcement: Topic ACLs at IoT policy level

**Encryption in Transit:** TLS 1.3 for all MQTT connections

- Reason: Protects credentials and data from eavesdropping
- Implementation: Mandatory via port 8883 (MQTT with TLS)
- Verification: Certificate hostname validation on device

**User authentication:** SSO via SAML in Snowflake

- Reason: Centralised identity management, MFA support
- Scope: Covers access to Streamlit portal and Power BI
- Enforcement: Snowflake role-based access control

---

## 9. Cost Optimisation

### 9.1 Serverless-First Approach

**Why serverless?**

- Pay only for actual usage (no idle costs)
- Auto-scaling included (no over-provisioning)
- No maintenance overhead (reduces operational cost)

**Serverless components:**

- IoT Core (MQTT broker - pay per message)
- Kinesis On-Demand (streaming - pay per shard-hour)
- Secrets Manager (pay per secret + API calls)
- CloudWatch (pay per metric + logs ingested)

### 9.2 Cost Control Mechanisms

| Component         | Cost Control Strategy                             |
| ----------------- | ------------------------------------------------- |
| **IoT Core**      | On-demand pricing, 26M messages/day well below limits |
| **Kinesis**       | On-demand mode, auto-scales down to zero shards   |
| **Secrets Mgr**   | ~$0.40/secret/month, no per-call charges         |
| **CloudWatch**    | Log retention policies (90-180 days)             |
| **Snowflake**     | Auto-suspend warehouses, resource monitors       |

---

## 10. Operational Considerations

### 10.1 Monitoring Strategy

**What to monitor (AWS components):**

| Metric                    | Source         | Target    | Threshold                |
| ------------------------- | -------------- | --------- | ------------------------ |
| **IoT Connections**       | CloudWatch     | Dashboard | Track active gateways     |
| **Thing Group Device Count** | AWS IoT     | Dashboard | Track devices per tenant/site |
| **Disconnected Devices**  | Dynamic Thing Group | Alarm | >0 devices in disconnected group |
| **MQTT Messages**         | CloudWatch     | Dashboard | Should be ~86K/sec peak   |
| **Message Processing**    | CloudWatch     | Dashboard | <100ms latency           |
| **Connection Errors**     | CloudWatch     | Alarm     | >5 failures in 5 min     |
| **Certificate Expiry**    | CloudWatch     | Alarm     | <30 days until expiry    |
| **Kinesis Iterator Age**  | CloudWatch     | Alarm     | >60 seconds              |
| **CloudWatch Logs**       | CloudWatch     | Dashboard | Parse error patterns     |

**What to monitor (Snowflake components):**

- Raw data ingestion rate
- Task execution success/failure
- Dynamic Table refresh latency
- Storage growth per tenant
- Query performance

**How to implement:**

- **CloudWatch Dashboards**: Real-time AWS metrics
- **CloudWatch Alarms**: SNS notifications for issues
- **Thing Group Queries**: Regular polling of dynamic groups for disconnected devices
  ```bash
  # Check disconnected devices for all tenants
  for tenant in company_a company_b company_c; do
    aws iot list-things-in-thing-group \
      --thing-group-name "smdh-${tenant}-disconnected" \
      --region eu-west-2
  done
  ```
- **Snowflake System Views**: Query ingestion_metrics
- **Automated Reports**: Daily health check summaries leveraging thing group data

### 10.2 Alerting Strategy

**Critical Alerts (Page on-call):**
- IoT Core connection failures >5 in 5 minutes
- Certificate expiring <7 days
- Kinesis iterator age >2 minutes
- Zero data for >30 minutes

**Warning Alerts (Ticket):**
- Kinesis iterator age >60 seconds
- Snowflake task failures >3 in 1 hour
- Connection errors >1 per minute
- Disk space low warnings

**Information Alerts (Log only):**
- Successful tenant connections
- Daily ingestion statistics
- Certificate rotation completions

### 10.3 Maintenance Windows

**Zero-downtime operations:**

- **Certificate rotation**: Deploy new certs before expiry (30-day window)
- **IoT policy updates**: Changes effective immediately, no device reconnect required
- **Kinesis configuration**: Modify partition count without data loss
- **Snowflake changes**: Execute during low-traffic periods (typically 02:00-04:00 UTC)

**Regular maintenance:**

- **Certificate rotation** (automated): Secrets Manager triggers before expiry
- **CloudWatch logs cleanup**: Automated via retention policies (90 days)
- **IoT Core certificate expiry**: Monitor via CloudWatch alarms
- **Snowflake data archival**: Automated via Time Travel and storage tiers
- **CloudTrail logs**: Retained in S3 for 90 days (compliance requirement)

---

## 11. Future Extensibility

### 11.1 Planned Enhancements

| Enhancement                | Architecture Impact                                   |
| -------------------------- | ----------------------------------------------------- |
| **Real-time alerting**     | Add EventBridge for complex event processing         |
| **Machine learning**       | Leverage Snowflake Cortex ML built-in features       |
| **Mobile dashboards**      | Extend Snowflake Streamlit with mobile-optimized UI  |
| **Edge processing**        | Add AWS IoT Greengrass for local anomaly detection   |
| **PrivateLink**            | Optional encrypted connection for on-prem Snowflake  |
| **Multi-region failover**  | Secondary region with Kinesis replication            |

### 11.2 Architecture Flexibility

The architecture supports future changes through:

- **Protocol agnostic core**: Can add new ingestion methods
- **Loosely coupled services**: Can swap components independently
- **Standard interfaces**: Uses common formats (JSON, MQTT, HTTP)
- **Cloud-native design**: Can leverage new managed services

---

## 12. Decision Log

### 12.1 Key Architecture Decisions

| Decision                   | Choice                   | Alternative Considered | Rationale                                      |
| -------------------------- | ------------------------ | ---------------------- | ---------------------------------------------- |
| **MQTT Broker**            | AWS IoT Core             | EMQ X, Mosquitto       | Fully managed, scales to millions, native AWS  |
| **Stream Processing**      | Kinesis (on-demand)      | Kafka/MSK, SQS         | Native integration, no cluster management      |
| **Data Warehouse**         | Snowflake                | Redshift, BigQuery     | Superior semi-structured data handling         |
| **Web Framework**          | Streamlit in Snowflake   | React + ECS            | Faster development, no separate infrastructure |
| **Multi-tenancy**          | Database-per-tenant      | Row-level security     | Stronger isolation, simpler operations         |
| **Device Authentication**  | X.509 certificates       | Pre-shared keys        | Can be revoked, non-repudiation                |
| **Device Organization**    | AWS IoT Thing Groups     | Custom database tables | Native AWS feature, enables bulk operations, automatic hierarchy |
| **Network Design**         | No VPC (managed only)    | Custom VPC             | Simpler, IoT needs internet-facing endpoint    |
| **Regional Deployment**    | Single region (eu-west-2) | Multi-region          | Cost-effective, compliance, gateway proximity  |

### 12.2 Trade-offs Accepted

| Trade-off                         | Benefit Gained                     | Risk Mitigation                              |
| --------------------------------- | ---------------------------------- | -------------------------------------------- |
| **MQTT-only (no HTTP)**           | Simpler architecture, lower latency | File uploads handled via Streamlit           |
| **Managed services lock-in**      | Reduced operations, high reliability| Standard protocols (MQTT, AWS APIs)          |
| **Internet-facing IoT endpoint**  | No NAT overhead, simpler network   | Mitigated by X.509 certs + topic ACLs        |
| **Eventual consistency**          | Better performance, scalability    | Design dashboards for eventual consistency   |
| **Single region**                 | Simplified ops, cost optimization  | Multi-region failover via Kinesis replication |

---

## 13. Tenant Onboarding Process

### 13.1 Overview

Onboarding a new tenant involves configuring resources across AWS and Snowflake to ensure complete isolation, proper authentication, and correct data routing. This process should be automated through Infrastructure as Code (IaC) but is documented here for understanding.

### 13.2 Tenant Onboarding Checklist

| Phase                  | Component         | Configuration Required              | Responsible Team         |
| ---------------------- | ----------------- | ----------------------------------- | ------------------------ |
| **1. Planning**        | Business Setup    | Contract, SLAs, data volumes        | Sales/Account Management |
| **2. Identity**        | User Accounts     | SSO setup, user list, roles         | Identity Team            |
| **3. AWS Setup**       | IoT Core & Rules  | X.509 certificates, topic ACLs      | Platform Team            |
| **4. Snowflake Setup** | Database & Roles  | Database creation, RBAC setup       | Data Team                |
| **5. Application**     | Portal Access     | Streamlit configuration             | Application Team         |
| **6. Validation**      | End-to-end Test   | Data flow verification              | QA Team                  |
| **7. Production**      | Go-live           | Monitoring, alerts, certificate mgmt | Operations Team          |

### 13.3 Detailed Configuration Steps

#### Phase 1: Initial Setup and Planning

**Information Required:**

- Tenant identifier (e.g., `company_a`)
- Company name and details
- Number of sites/locations
- Number of devices per site
- Expected data volume (messages/day)
- User list with roles
- Data retention requirements
- SLA requirements

**Naming Convention:**

```
Tenant ID: company_a (lowercase, no spaces)
Resources: smdh_tenant_company_a_*
Database: smdh_tenant_company_a
API Key: smdh-prod-company-a-{random}
```

#### Phase 2: AWS IoT Configuration (for MQTT devices)

**Step 2.1: Create Thing Groups Hierarchy**

```
Component: AWS IoT Thing Groups
Purpose: Organize devices hierarchically for management and monitoring

Create tenant-level thing group:
- Name: smdh-tenant-company_a
- Description: "All IoT devices for tenant: Company A Manufacturing Ltd"
- Attributes:
  - tenant_id: company_a
  - tenant_name: Company_A_Manufacturing_Ltd
  - managed_by: terraform

Create site-level thing groups (one per site):
- Name: smdh-company_a-site_001
- Parent: smdh-tenant-company_a
- Description: "IoT devices at Company A - site_001"
- Attributes:
  - tenant_id: company_a
  - site_id: site_001
  - managed_by: terraform

Create dynamic thing groups (auto-tracking):
- Name: smdh-company_a-disconnected
- Query: attributes.tenant_id:company_a AND connectivity.connected:false
- Purpose: Automatically track disconnected devices for alerting

- Name: smdh-company_a-active
- Query: attributes.tenant_id:company_a AND connectivity.connected:true AND connectivity.timestamp > ${timestamp - 300000}
- Purpose: Track recently active devices for health monitoring
```

**Step 2.2: Create IoT Thing Registry**

```
Component: AWS IoT Core
Purpose: Register tenant's gateways and devices

For each gateway:
- Thing Name: smdh-gateway-company-a-site-001
- Thing Type: LoRaWANGateway
- Thing Groups: Add to smdh-company_a-site_001 (automatic parent inheritance)
- Attributes:
  - tenant_id: company_a
  - site_id: site-001
  - location: "Manchester Factory"
  - deployment_date: "2024-11-13"
```

**Step 2.3: Generate X.509 Certificates**

```
Component: AWS IoT Core Certificates
Purpose: Device authentication

Per gateway certificate:
- Generate unique certificate pair
- Store securely (AWS Secrets Manager for backup)
- Deploy to physical gateway
- Certificate lifecycle: 2 years
- Auto-rotation reminder: 30 days before expiry
```

**Step 2.4: Create IoT Policy**

```
Component: AWS IoT Policies
Purpose: Restrict device permissions to tenant namespace

Policy: smdh-policy-company-a
Permissions:
- Connect: arn:aws:iot:eu-west-2:*:client/smdh-gateway-company-a-*
- Publish: arn:aws:iot:eu-west-2:*:topic/smdh/company_a/*
- Subscribe: arn:aws:iot:eu-west-2:*:topicfilter/smdh/company_a/commands/*
- Receive: arn:aws:iot:eu-west-2:*:topic/smdh/company_a/commands/*

Critical: No cross-tenant topic access
```

**Step 2.5: Configure IoT Rules**

```
Component: AWS IoT Rules Engine
Purpose: Route tenant data to correct stream

Rule Name: smdh_route_company_a
SQL: SELECT *, 'company_a' as tenant_id
     FROM 'smdh/company_a/+'
     WHERE timestamp IS NOT NULL
Action:
- Kinesis: Put to partition key 'company_a'
- Error Action: Republish to smdh/company_a/errors
```

**Step 2.6: Verify Thing Group Configuration**

```
Component: AWS IoT Thing Groups
Purpose: Validate hierarchy and device memberships

Verification commands:
# View thing group hierarchy
aws iot describe-thing-group --thing-group-name smdh-tenant-company_a

# List all devices for tenant (recursive)
aws iot list-things-in-thing-group \
  --thing-group-name smdh-tenant-company_a \
  --recursive --region eu-west-2

# List devices at specific site
aws iot list-things-in-thing-group \
  --thing-group-name smdh-company_a-site_001 \
  --region eu-west-2

# Check dynamic group for disconnected devices (should be empty initially)
aws iot list-things-in-thing-group \
  --thing-group-name smdh-company_a-disconnected \
  --region eu-west-2

Expected Results:
- Tenant group contains all site groups as children
- Site groups contain only devices for that site
- Devices automatically inherit tenant group membership
- Dynamic groups are empty until devices connect/disconnect
```

#### Phase 3: Snowflake Configuration

**Step 3.1: Create Tenant Database**

```sql
Component: Snowflake
Purpose: Isolated data storage

-- Create database
CREATE DATABASE smdh_tenant_company_a
  COMMENT = 'Company A - Manufacturing Ltd';

-- Create schemas
CREATE SCHEMA smdh_tenant_company_a.raw
  COMMENT = 'Raw ingested data';

CREATE SCHEMA smdh_tenant_company_a.normalized
  COMMENT = 'Cleaned and normalized data';

CREATE SCHEMA smdh_tenant_company_a.aggregated
  COMMENT = 'Aggregated metrics and KPIs';

CREATE SCHEMA smdh_tenant_company_a.analytics
  COMMENT = 'Analytics views and ML results';
```

**Step 3.2: Create Tables**

```sql
Component: Snowflake Tables
Purpose: Data storage structures

-- Raw sensor data table
CREATE TABLE smdh_tenant_company_a.raw.sensor_readings (
  tenant_id VARCHAR(100) DEFAULT 'company_a',
  sensor_id VARCHAR(255),
  timestamp TIMESTAMP_NTZ,
  payload VARIANT,
  ingestion_timestamp TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
  source_system VARCHAR(100),
  PRIMARY KEY (sensor_id, timestamp)
)
CLUSTER BY (DATE_TRUNC('day', timestamp));

-- Create similar tables for other data types
CREATE TABLE smdh_tenant_company_a.raw.uploaded_files (...);
CREATE TABLE smdh_tenant_company_a.raw.api_events (...);
```

**Step 3.3: Sync AWS IoT Metadata to Snowflake Infrastructure**

```sql
Component: Snowflake Infrastructure Schema (smdh_infrastructure.tenant_configs)
Purpose: Mirror AWS IoT Thing Group hierarchy for unified device management

-- This is done in the central infrastructure database, not per-tenant

-- Update tenant record with thing group information
UPDATE smdh_infrastructure.tenant_configs.tenants
SET
  tenant_thing_group_name = 'smdh-tenant-company_a',
  tenant_thing_group_arn = 'arn:aws:iot:eu-west-2:123456789012:thinggroup/smdh-tenant-company_a',
  last_sync_timestamp = CURRENT_TIMESTAMP()
WHERE tenant_id = 'company_a';

-- Add site thing group information
UPDATE smdh_infrastructure.tenant_configs.sites
SET
  site_thing_group_name = 'smdh-company_a-site_001',
  site_thing_group_arn = 'arn:aws:iot:eu-west-2:123456789012:thinggroup/smdh-company_a-site_001',
  last_device_sync = CURRENT_TIMESTAMP()
WHERE tenant_id = 'company_a' AND site_id = 'site_001';

-- Add device thing group memberships
UPDATE smdh_infrastructure.tenant_configs.devices
SET
  site_thing_group_name = 'smdh-company_a-site_001',
  tenant_thing_group_name = 'smdh-tenant-company_a',
  thing_group_memberships = ARRAY_CONSTRUCT('smdh-company_a-site_001', 'smdh-tenant-company_a'),
  last_sync_timestamp = CURRENT_TIMESTAMP()
WHERE device_id = 'smdh-gateway-company-a-site-001-gw-001';

-- Verify thing group hierarchy view
SELECT * FROM smdh_infrastructure.monitoring.v_thing_group_hierarchy
WHERE tenant_id = 'company_a';

Benefits of this sync:
- Unified view of AWS IoT device hierarchy in Snowflake
- Enable SQL queries across device organization
- Support for analytics on device groups (e.g., "average uptime per site")
- Integration point for monitoring and alerting dashboards
```

**Step 3.4: Setup Streaming Objects**

```sql
Component: Snowflake Streams & Tasks
Purpose: Real-time processing

-- Create stream for CDC
CREATE STREAM smdh_tenant_company_a.raw.sensor_readings_stream
  ON TABLE smdh_tenant_company_a.raw.sensor_readings
  APPEND_ONLY = TRUE;

-- Create processing task
CREATE TASK smdh_tenant_company_a.raw.process_sensor_data
  WAREHOUSE = etl_wh
  SCHEDULE = '1 MINUTE'
  WHEN SYSTEM$STREAM_HAS_DATA('sensor_readings_stream')
AS
  INSERT INTO normalized.sensor_metrics
  SELECT ... FROM sensor_readings_stream;

-- Start task
ALTER TASK process_sensor_data RESUME;
```

**Step 3.5: Create Roles and Users**

```sql
Component: Snowflake RBAC
Purpose: Access control

-- Create tenant role
CREATE ROLE tenant_company_a_user;

-- Grant database access
GRANT USAGE ON DATABASE smdh_tenant_company_a
  TO ROLE tenant_company_a_user;

GRANT ALL ON ALL SCHEMAS IN DATABASE smdh_tenant_company_a
  TO ROLE tenant_company_a_user;

-- Create admin role
CREATE ROLE tenant_company_a_admin;
GRANT OWNERSHIP ON DATABASE smdh_tenant_company_a
  TO ROLE tenant_company_a_admin;

-- Create users
CREATE USER john_smith_company_a
  DEFAULT_ROLE = tenant_company_a_user
  DEFAULT_WAREHOUSE = analytics_wh
  MUST_CHANGE_PASSWORD = TRUE;

GRANT ROLE tenant_company_a_user TO USER john_smith_company_a;
```

**Step 3.6: Configure Dynamic Tables**

```sql
Component: Snowflake Dynamic Tables
Purpose: Real-time aggregations

CREATE DYNAMIC TABLE smdh_tenant_company_a.aggregated.machine_utilization
  TARGET_LAG = '5 minutes'
  WAREHOUSE = streaming_wh
AS
SELECT
  machine_id,
  DATE_TRUNC('hour', timestamp) as hour,
  AVG(utilization) as avg_utilization,
  COUNT(*) as reading_count
FROM smdh_tenant_company_a.normalized.sensor_metrics
GROUP BY machine_id, hour;
```

#### Phase 4: Streamlit Portal Configuration

**Step 4.1: Tenant Configuration File**

```python
Component: Streamlit Configuration
Purpose: Portal customization

# config/tenants/company_a.yaml
tenant:
  id: company_a
  name: "Company A Manufacturing Ltd"
  logo_url: "https://..."
  theme:
    primary_color: "#1976D2"
    secondary_color: "#FFA726"
  features:
    machine_monitoring: true
    air_quality: true
    job_tracking: true
    file_upload: true
  dashboards:
    - machine_utilization
    - energy_consumption
    - production_flow
    - quality_metrics
```

**Step 4.2: Access Control**

```python
Component: Streamlit Access
Purpose: Tenant isolation in UI

# Automatically enforced by Snowflake role
# User's role determines accessible database
# No code changes needed - handled by Snowflake context
```

#### Phase 5: Monitoring and Alerting Setup

**Step 5.1: CloudWatch Dashboards**

```
Component: AWS CloudWatch
Purpose: Tenant-specific monitoring

Dashboard: smdh-company-a-dashboard
Widgets:
- MQTT message ingestion rate
- Connection errors
- IoT Rule failures
- Kinesis iterator age
- Certificate expiry countdown
- Data latency (Kinesis to Snowflake)
```

**Step 5.2: Alerting Rules**

```
Component: CloudWatch Alarms + SNS
Purpose: Operational alerts

Alarms:
- Connection failures (>5 in 5 minutes)
- Certificate expiry (<7 days)
- MQTT message drop rate (>1%)
- Kinesis iterator age (>60 seconds)
- IoT Rule errors (>5 in 5 minutes)
- Zero data received (>30 minutes)

SNS Topic: smdh-alerts-company-a
Subscribers: ops-team@company.com, tenant-contact@companya.com
```

#### Phase 6: Gateway Configuration

**Step 6.1: Physical Device Setup (Milesight UG65)**

```
Component: Milesight UG65 Gateway
Purpose: Field device MQTT configuration

Configuration:
- Server: {iot-endpoint}.iot.eu-west-2.amazonaws.com
- Port: 8883 (MQTT with TLS)
- Client ID: smdh-gateway-company-a-site-001
- Certificate: Upload company-a-cert.pem (X.509)
- Private Key: Upload company-a-private.key
- CA Certificate: Upload AmazonRootCA1.pem
- Topic: smdh/company_a/sensor-data
- QoS: 1 (at-least-once delivery)
- Keep Alive: 60 seconds
- Offline Buffer: 10,000 messages (store-and-forward)
```

**Step 6.2: DevTank OSM Setup (Wi-Fi MQTT)**

```
Configuration:
- Server: {iot-endpoint}.iot.eu-west-2.amazonaws.com
- Port: 8883 (MQTT with TLS)
- Wi-Fi Network: Company A production network
- Certificate: Upload company-a-osm-cert.pem
- Topic: smdh/company_a/devtank-data
- QoS: 1
- Frequency: 1-15 minute intervals (configurable)
```

### 13.4 Validation Tests

**End-to-End Test Checklist:**

| Test                      | Description                                 | Expected Result                         |
| ------------------------- | ------------------------------------------- | --------------------------------------- |
| **MQTT Connection**       | Gateway connects to IoT Core with X.509     | Connection successful, no auth errors   |
| **Thing Group Hierarchy** | Query tenant thing group recursively        | Returns all devices across all sites    |
| **Site Thing Group**      | Query site thing group                      | Returns only devices for that site      |
| **Dynamic Group**         | Check disconnected devices dynamic group    | Empty initially, updates when device disconnects |
| **Message Ingestion**     | Send test message from gateway              | Message appears in Snowflake within 30s |
| **Tenant Topic ACLs**     | Try to publish to another tenant's topic    | Access denied (403 error)               |
| **DevTank Wi-Fi**         | Connect DevTank OSM via Wi-Fi               | Connects, sends data to IoT Core        |
| **Data Routing**          | Verify data in correct Kinesis partition    | Partition key matches tenant_id         |
| **User Access**           | Login to Streamlit portal with SSO          | Only see company_a data                 |
| **Certificate Rotation**  | Trigger cert rotation via Secrets Manager   | New cert deployed, old connections drop |
| **Monitoring**            | Generate IoT error (bad topic)              | Alert received via SNS within 5 min     |
| **Dashboards**            | View CloudWatch metrics                     | Real-time ingestion metrics displayed   |

### 13.5 Automation Script Example

```bash
#!/bin/bash
# Tenant Onboarding Automation Script

TENANT_ID="company_a"
TENANT_NAME="Company A Manufacturing Ltd"
AWS_REGION="eu-west-2"
SNOWFLAKE_ACCOUNT="your-account"

echo "Starting tenant onboarding for $TENANT_ID..."

# 1. Create Thing Group Hierarchy
echo "Creating thing group hierarchy..."

# Tenant-level thing group
aws iot create-thing-group \
  --thing-group-name "smdh-tenant-${TENANT_ID}" \
  --thing-group-properties "attributePayload={attributes={tenant_id=${TENANT_ID},managed_by=terraform}}" \
  --region $AWS_REGION

# Site-level thing group (assuming site_001)
aws iot create-thing-group \
  --thing-group-name "smdh-${TENANT_ID}-site_001" \
  --parent-group-name "smdh-tenant-${TENANT_ID}" \
  --thing-group-properties "attributePayload={attributes={tenant_id=${TENANT_ID},site_id=site_001,managed_by=terraform}}" \
  --region $AWS_REGION

# Dynamic thing group for disconnected devices
aws iot create-dynamic-thing-group \
  --thing-group-name "smdh-${TENANT_ID}-disconnected" \
  --query-string "attributes.tenant_id:${TENANT_ID} AND connectivity.connected:false" \
  --region $AWS_REGION

# Dynamic thing group for active devices
aws iot create-dynamic-thing-group \
  --thing-group-name "smdh-${TENANT_ID}-active" \
  --query-string "attributes.tenant_id:${TENANT_ID} AND connectivity.connected:true" \
  --region $AWS_REGION

# 2. AWS IoT Setup
echo "Creating IoT resources..."
aws iot create-thing-type --thing-type-name "LoRaWANGateway" --region $AWS_REGION
aws iot create-thing --thing-name "smdh-gateway-${TENANT_ID}-site-001" \
  --thing-type-name "LoRaWANGateway" \
  --attribute-payload "{\"tenant_id\":\"${TENANT_ID}\"}" \
  --region $AWS_REGION

# Add thing to site thing group
aws iot add-thing-to-thing-group \
  --thing-name "smdh-gateway-${TENANT_ID}-site-001" \
  --thing-group-name "smdh-${TENANT_ID}-site_001" \
  --region $AWS_REGION

# 3. Generate certificates
CERT_ARN=$(aws iot create-keys-and-certificate --set-as-active \
  --certificate-pem-outfile ${TENANT_ID}-cert.pem \
  --private-key-outfile ${TENANT_ID}-private.key \
  --query 'certificateArn' --output text --region $AWS_REGION)

# 4. Create and attach policy
aws iot create-policy --policy-name "smdh-policy-${TENANT_ID}" \
  --policy-document file://templates/iot-policy-template.json \
  --region $AWS_REGION

aws iot attach-policy --policy-name "smdh-policy-${TENANT_ID}" \
  --target $CERT_ARN --region $AWS_REGION

# 5. Snowflake setup (via SnowSQL)
snowsql -a $SNOWFLAKE_ACCOUNT -u admin_user -f templates/create_tenant_database.sql \
  --variable tenant_id=$TENANT_ID \
  --variable tenant_name="$TENANT_NAME"

# 6. Sync thing group metadata to Snowflake
echo "Syncing AWS IoT metadata to Snowflake..."
TENANT_THING_GROUP_ARN=$(aws iot describe-thing-group \
  --thing-group-name "smdh-tenant-${TENANT_ID}" \
  --query 'thingGroupArn' --output text --region $AWS_REGION)

snowsql -a $SNOWFLAKE_ACCOUNT -u admin_user -q "
UPDATE smdh_infrastructure.tenant_configs.tenants
SET tenant_thing_group_name = 'smdh-tenant-${TENANT_ID}',
    tenant_thing_group_arn = '${TENANT_THING_GROUP_ARN}',
    last_sync_timestamp = CURRENT_TIMESTAMP()
WHERE tenant_id = '${TENANT_ID}';"

echo "Tenant onboarding complete for $TENANT_ID"
echo ""
echo "Verification commands:"
echo "  aws iot list-things-in-thing-group --thing-group-name smdh-tenant-${TENANT_ID} --recursive --region ${AWS_REGION}"
echo "  aws iot describe-thing-group --thing-group-name smdh-tenant-${TENANT_ID} --region ${AWS_REGION}"
```

### 13.6 Rollback Procedures

If onboarding fails or tenant needs to be removed:

1. **Disable IoT certificates** (prevents new connections)
   ```bash
   aws iot update-certificate --certificate-id $CERT_ID --new-status INACTIVE
   ```

2. **Deactivate IoT policies** (blocks all device access)
   ```bash
   # Create new policy without permissions, attach to cert
   ```

3. **Suspend Snowflake tasks** (stops ETL processing)
   ```sql
   ALTER TASK smdh_tenant_${TENANT_ID}.raw.task_process_data SUSPEND;
   ```

4. **Backup tenant database** (preserve data)
   ```sql
   CREATE DATABASE smdh_tenant_${TENANT_ID}_backup CLONE smdh_tenant_${TENANT_ID};
   ```

5. **Remove IoT Rules** (stops message routing)
   ```bash
   aws iot delete-topic-rule --rule-name smdh_route_${TENANT_ID}
   ```

6. **Clean up resources** (delete in reverse order)
   - Drop Snowflake database
   - Delete IoT policies and certificates
   - Remove Kinesis subscription

### 13.7 Tenant Lifecycle Management

| Event            | Action Required                     | Timeline            |
| ---------------- | ----------------------------------- | ------------------- |
| **Onboarding**   | Full setup as documented            | 2-4 hours automated |
| **Scaling Up**   | Add warehouses, increase limits     | 30 minutes          |
| **Scaling Down** | Reduce warehouses, adjust retention | 30 minutes          |
| **Suspension**   | Disable ingestion, preserve data    | 15 minutes          |
| **Reactivation** | Re-enable ingestion, validate       | 1 hour              |
| **Offboarding**  | Export data, remove resources       | 4-8 hours           |

---

## 14. Conclusion

The SMDH AWS architecture achieves simplicity through focus:

- **Single Protocol**: MQTT native for all sensor data (no HTTP conversion)
- **Managed Services**: IoT Core, Kinesis, CloudWatch eliminate ops overhead
- **Clear Isolation**: Multi-layer tenant isolation from device to database
- **Hierarchical Organization**: AWS IoT Thing Groups mirror business structure (tenant → sites → devices)
- **Operational Excellence**: Comprehensive monitoring, alerting, certificate management, and bulk device operations
- **Cost Effective**: Serverless on-demand pricing, no idle resources

By standardizing on MQTT and using AWS managed services, we eliminate custom validation layers, reduce latency, and minimize operational complexity. The architecture is designed to scale smoothly as tenant count grows from 5 to 30+ customers.

The AWS layer is intentionally minimal and focused—just four core services (IoT Core, Kinesis, Secrets Manager, CloudWatch) orchestrate all sensor data ingestion. AWS IoT Thing Groups provide native device organization that eliminates the need for custom management layers. Snowflake handles all data processing, analytics, and user-facing applications, with infrastructure tables mirroring the AWS IoT hierarchy for unified device management.

**Key Benefits of Thing Groups Integration:**

- **Simplified Operations**: Query all devices for a tenant with a single recursive AWS CLI command
- **Site-Level Management**: Apply firmware updates or configuration changes to entire sites
- **Automated Health Tracking**: Dynamic groups automatically identify disconnected or active devices
- **Unified View**: Snowflake infrastructure tables mirror AWS Thing Group hierarchy for cross-platform queries
- **Cost Visibility**: Thing group tags enable per-tenant and per-site cost tracking

---

## Appendix A: Component Mapping

| Business Requirement        | Technical Component        | AWS Service           | Status      |
| --------------------------- | -------------------------- | --------------------- | ----------- |
| Receive MQTT sensor data    | MQTT broker + Rules Engine | IoT Core + IoT Rules  | **Active**  |
| Organize devices by tenant/site | Hierarchical device groups | IoT Thing Groups | **Active** |
| Track device health         | Dynamic device queries     | Dynamic Thing Groups  | **Active**  |
| Buffer streaming data       | Message queue              | Kinesis               | **Active**  |
| Store sensor data           | Data warehouse             | Snowflake (external)  | **Active**  |
| Upload files                | Web portal                 | Streamlit (Snowflake) | **Active**  |
| Manage credentials          | Secrets store              | Secrets Manager       | **Active**  |
| Monitor system              | Observability              | CloudWatch            | **Active**  |
| Send alerts                 | Notification               | SNS                   | **Active**  |
| Geo-distributed apps        | Edge processing            | IoT Greengrass        | **Future**  |
| Complex event processing    | Real-time rules            | EventBridge           | **Future**  |

## Appendix B: AWS Pricing Estimate (30 Tenants, 26M msgs/day)

| Service          | Metric             | Monthly Cost  | Notes                                  |
| ---------------- | ------------------ | ------------- | -------------------------------------- |
| **IoT Core**     | 26M messages/day   | ~$130         | $0.12 per million messages             |
| **Kinesis**      | On-demand 1 shard  | ~$15-20       | On-demand scales down, 24h retention   |
| **Secrets Mgr**  | 1 secret           | ~$0.40        | One secret for Snowflake private key   |
| **CloudWatch**   | 200GB logs/month   | ~$100         | Includes metrics, logs, alarms         |
| **AWS Total**    |                    | ~**$250/mo**  | Approximately $8-10 per tenant/month   |
| **Snowflake**    | 30 tenants         | ~$5-10K/mo    | Dominated by data storage & compute    |

## Appendix C: Glossary

| Term               | Definition                                                       |
| ------------------ | ---------------------------------------------------------------- |
| **MQTT**           | Message Queuing Telemetry Transport - IoT communication protocol |
| **LoRaWAN**        | Long Range Wide Area Network - IoT radio protocol                |
| **Thing Groups**   | AWS IoT feature for hierarchical device organization and management |
| **Dynamic Thing Groups** | AWS IoT query-based groups that auto-update based on device attributes |
| **JWT**            | JSON Web Token - Authentication token format                     |
| **CDC**            | Change Data Capture - Tracking data modifications                |
| **VARIANT**        | Snowflake data type for semi-structured data                     |
| **Dynamic Tables** | Snowflake feature for materialized views with auto-refresh       |
| **Streamlit**      | Python framework for data applications                           |
| **X.509**          | Standard for public key certificates                             |
| **SAML**           | Security Assertion Markup Language - SSO protocol                |
| **IaC**            | Infrastructure as Code - Managing infrastructure through code    |
