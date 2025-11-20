# Smart Manufacturing Data Hub (SMDH) - AWS Architecture Design

## 1. Executive Summary

### 1.1 What We're Building

The SMDH platform is a multi-tenant IoT analytics system that collects data from manufacturing facilities and provides real-time insights. The architecture must accommodate diverse data sources - from high-frequency sensors transmitting via MQTT to legacy systems uploading CSV files - while maintaining strict tenant isolation for up to 30 manufacturing SMEs.

### 1.2 Core Architecture Principle

**The data source determines the ingestion path.**

We don't force all data through a single pipeline. Instead, we provide three optimised paths based on how the data naturally arrives:

- **MQTT devices** → AWS IoT Core → Kinesis → Snowflake
- **HTTP/REST systems** → API Gateway → Lambda → Snowflake
- **File uploads** → Streamlit portal → Snowflake stages

This protocol-driven approach ensures we use the right tool for each site, avoiding unnecessary complexity while maintaining reliability.

### 1.3 Key Business Drivers

| Driver                        | Architectural Impact                       |
| ----------------------------- | ------------------------------------------ |
| **Up to 30 separate tenants** | Database-per-tenant isolation in Snowflake |
| **5-10 sensors per site**     | Modest but steady streaming data volume    |
| **Mixed device types**        | Multiple ingestion protocols required      |
| **Real-time monitoring**      | Sub-minute data latency requirements       |

---

## 2. Requirements Traceability

### 2.1 Functional Requirements

| Requirement                          | Description                                             | Architecture Solution                                            |
| ------------------------------------ | ------------------------------------------------------- | ---------------------------------------------------------------- |
| **FR-001: Multi-protocol ingestion** | Support MQTT, HTTP, and file-based data sources         | Three distinct ingestion paths optimised for each protocol       |
| **FR-002: Real-time processing**     | <1 minute from sensor to dashboard for critical metrics | Streaming architecture with Kinesis and Dynamic Tables           |
| **FR-003: Historical analysis**      | Store 2+ years of data for trend analysis               | Snowflake with Time Travel and configurable retention            |
| **FR-004: Multi-tenancy**            | Complete data isolation between customers               | Database-per-tenant in Snowflake, tenant validation at ingestion |
| **FR-005: Self-service uploads**     | Users can upload data files                             | Streamlit portal with drag-and-drop interface                    |

### 2.2 Non-Functional Requirements

| Requirement                  | Description                                                                          | Architecture Solution                                          |
| ---------------------------- | ------------------------------------------------------------------------------------ | -------------------------------------------------------------- |
| **NFR-001: Scalability**     | Handle up to 300 sensors across 30 sites at 1 Hz frequency (~26M messages/day total) | Auto-scaling serverless components (Lambda, Kinesis on-demand) |
| **NFR-002: Availability**    | 99.9% uptime for data ingestion                                                      | Multi-AZ deployment, managed services with SLAs                |
| **NFR-003: Security**        | End-to-end encryption, audit logging                                                 | TLS everywhere, CloudTrail, Snowflake audit logs               |
| **NFR-004: Performance**     | Sub-second API response times                                                        | API Gateway caching, Snowflake result cache                    |
| **NFR-005: Maintainability** | Minimal operational overhead                                                         | Managed services, Infrastructure as Code                       |

### 2.3 Constraints

| Constraint                                            | Impact on Architecture                            |
| ----------------------------------------------------- | ------------------------------------------------- |
| **MQTT devices cannot connect directly to Snowflake** | Must use AWS IoT Core as MQTT broker              |
| **Snowflake has no native MQTT support**              | Requires intermediate streaming service (Kinesis) |
| **Some systems only support HTTP webhooks**           | Need API Gateway for HTTP ingestion               |
| **Some data arrives as manual file uploads**          | Portal required for user uploads                  |

---

## 3. Component Architecture

### 3.1 Data Ingestion Layer

#### 3.1.1 AWS IoT Core (MQTT Broker)

Acts as the MQTT broker for all IoT devices. Maintains persistent connections with thousands of sensors, handles connection management, and routes messages to downstream services.

- MQTT devices (like LoRaWAN gateways) only transmit over MQTT protocol, not HTTP
- Provides device registry for managing certificates and metadata
- Handles connection state, reconnection and offline message queuing
- Offers QoS guarantees for reliable message delivery

**Traceability**

- FR-001: Enables MQTT protocol support
- NFR-001: Auto-scales to handle millions of messages
- NFR-003: Certificate-based authentication for devices

Always required when devices communicate via MQTT protocol. This includes most IoT sensors and gateways.

#### 3.1.2 API Gateway

Provides a managed REST API endpoint for HTTP-based data sources. Handles authentication, rate limiting, and request routing to Lambda functions.

- Legacy systems often only support HTTP/webhook integration
- Provides centralised API management and monitoring
- Enforces rate limits to protect backend systems
- Generates SDK and documentation automatically

**Traceability**

- FR-001: Enables HTTP/REST protocol support
- NFR-002: Managed service with 99.95% SLA
- NFR-003: API key management and request validation

Required for any data source that pushes data via HTTP POST, including configured gateways, third-party webhooks, and legacy system integrations.

#### 3.1.3 Kinesis Data Streams

Buffers and orders streaming data between IoT Core and Snowflake. Provides temporary storage for high-velocity data streams with guaranteed ordering per partition.

- IoT Core generates data faster than Snowflake can ingest individual messages
- Provides replay capability if downstream processing fails
- Maintains message ordering within tenant partitions
- Enables multiple consumers (future real-time analytics)

**Traceability**

- FR-002: Enables real-time processing pipeline
- NFR-001: Handles high-throughput streaming data
- NFR-002: Provides durability with multi-AZ replication

Required when using IoT Core for MQTT ingestion. Optional for HTTP if buffering is needed.

### 3.2 Processing Layer

#### 3.2.1 Lambda Functions

Serverless compute that handles data validation, transformation, and routing. Different functions serve different purposes:

- **Ingestion Lambda**: Validates tenant ID, generates JWT tokens, calls Snowflake APIs
- **Transformation Lambda**: Converts between data formats, enriches data

- Validates data before it enters Snowflake (fail-fast principle)
- Enforces multi-tenant boundaries (prevents data leakage)
- Handles authentication complexity (JWT generation for Snowflake)
- Transforms data into consistent schema

**Traceability**

- FR-004: Tenant validation prevents cross-tenant data access
- NFR-001: Auto-scales with load
- NFR-005: Serverless means no servers to maintain

Required for API Gateway integration. Optional for IoT Core if transformation is needed or the site can't support MQTT transmission.

### 3.3 Storage & Analytics Layer

#### 3.3.1 Snowflake Data Platform

Central data warehouse handling all storage, processing, and analytics. Provides:

- Raw data storage in VARIANT columns (flexible schema)
- Stream processing via Streams and Tasks
- Real-time aggregations via Dynamic Tables
- ML capabilities via Cortex functions
- Native web apps via Streamlit

**Why it's needed:**

- Single source of truth for all manufacturing data
- Handles both structured and semi-structured data
- Provides powerful analytics without moving data
- Scales compute independently of storage
- Native multi-tenancy support

**Traceability**

- FR-003: Long-term storage with Time Travel
- FR-004: Database-per-tenant isolation
- NFR-004: Query optimisation and result caching

#### 3.3.2 Streamlit in Snowflake

Native web application framework running inside Snowflake. Provides:

- Customer portal for dashboards
- File upload interface for batch data
- Configuration management UI
- Custom reporting tools

**Why it's needed:**

- Eliminates need for separate web hosting
- Direct access to Snowflake data (no APIs needed)
- Inherits Snowflake security and authentication
- Rapid development with Python

**Traceability**

- FR-005: Self-service file upload capability
- NFR-003: Inherits Snowflake's security model
- NFR-005: No separate infrastructure to manage

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

#### 3.4.2 DynamoDB

Stores API key to tenant ID mappings for fast lookup during ingestion.

- Sub-millisecond lookups for API key validation
- Scales automatically with request volume
- Provides consistent performance
- Serverless with no maintenance

**Traceability**

- FR-004: Enables tenant identification
- NFR-004: Fast lookups for API performance

#### 3.4.3 CloudWatch

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

**Scenario:** Temperature sensor sending readings every second via LoRaWAN gateway

**Flow:**

1. **Sensor → Gateway**: LoRaWAN protocol over 868 MHz radio
2. **Gateway → IoT Core**: MQTT publish with X.509 authentication
3. **IoT Core → Kinesis**: Rule engine routes based on topic pattern
4. **Kinesis → Snowflake**: Openflow connector or Snowpipe ingests batches
5. **Snowflake Processing**: Streams detect changes, Tasks transform data
6. **Analytics**: Dynamic Tables aggregate, Streamlit displays dashboards

**Why this path:**

- Sensor only speaks LoRaWAN/MQTT, not HTTP
- IoT Core provides MQTT broker functionality
- Kinesis buffers high-frequency data
- Snowflake handles all processing centrally

### 4.2 HTTP API Data Flow

**Scenario:** Legacy sensor systems sending production events via webhook

**Flow:**

1. **System → API Gateway**: HTTP POST with API key authentication
2. **API Gateway → Lambda**: Validates request and API key
3. **Lambda Processing**: Checks tenant ID, validates schema
4. **Lambda → Snowflake**: Calls Snowpipe Streaming API
5. **Snowflake Processing**: Same as MQTT path

**Why this path:**

- Legacy site only supports HTTP webhooks
- API Gateway provides rate limiting and authentication
- Lambda adds validation layer before data enters Snowflake

### 4.3 File Upload Flow

**Scenario:** Quality manager uploading monthly inspection reports

**Flow:**

1. **User → Streamlit**: Logs in with SSO credentials
2. **File Upload**: Drag and drop Excel file
3. **Streamlit → Stage**: Writes directly to Snowflake stage
4. **Snowpipe → Tables**: Auto-ingests from stage
5. **Processing**: Tasks validate and transform data

**Why this path:**

- Human-driven process needs user interface
- Large files better handled as batch upload
- No real-time requirements

---

## 5. Multi-Tenancy Strategy

### 5.1 Isolation Levels

| Layer                 | Isolation Method                     | Rationale                          |
| --------------------- | ------------------------------------ | ---------------------------------- |
| **Device Level**      | Separate IoT certificates per tenant | Prevents device spoofing           |
| **API Level**         | Unique API keys per tenant           | Simple tenant identification       |
| **Lambda Level**      | Tenant validation before processing  | Prevents data injection attacks    |
| **Database Level**    | Separate database per tenant         | Complete data isolation            |
| **Application Level** | Role-based access control            | Users only see their tenant's data |

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

## 7. Security Architecture

### 7.1 Defense in Depth

| Layer           | Security Control                             |
| --------------- | -------------------------------------------- |
| **Network**     | TLS 1.2+ for all communications              |
| **Identity**    | Certificate-based for devices, SSO for users |
| **Access**      | Least privilege IAM roles                    |
| **Data**        | Encryption at rest and in transit            |
| **Application** | Input validation, SQL injection prevention   |
| **Monitoring**  | CloudTrail, VPC Flow Logs, Snowflake audit   |

### 7.2 Key Security Decisions

**Device authentication:** X.509 certificates over pre-shared keys

- Reason: Certificates can be revoked, provide non-repudiation

**API authentication:** API keys over OAuth

- Reason: Simpler for IoT devices, sufficient for server-to-server

**User authentication:** SSO via SAML

- Reason: Centralised identity management, MFA support

---

## 8. Cost Optimisation

### 8.1 Serverless-First Approach

**Why serverless?**

- Pay only for actual usage (no idle costs)
- Auto-scaling included (no over-provisioning)
- No maintenance overhead (reduces operational cost)

**Serverless components:**

- Lambda (compute)
- API Gateway (API management)
- DynamoDB (database)
- Kinesis On-Demand (streaming)

### 8.2 Cost Control Mechanisms

| Component         | Cost Control Strategy                       |
| ----------------- | ------------------------------------------- |
| **Lambda**        | Reserved capacity for predictable workloads |
| **Kinesis**       | On-demand pricing, auto-scales down         |
| **Snowflake**     | Auto-suspend warehouses, resource monitors  |
| **Storage**       | Lifecycle policies, compression             |
| **Data Transfer** | Keep within region to avoid charges         |

---

## 9. Operational Considerations

### 9.1 Monitoring Strategy

**What to monitor:**

- **Ingestion rate**: Messages per second by source
- **Processing latency**: Time from sensor to queryable
- **Error rates**: Failed validations, timeouts
- **Resource utilization**: Lambda duration, Snowflake credits
- **Business metrics**: Active sensors, data freshness

**How to monitor:**

- CloudWatch dashboards for AWS metrics
- Snowflake dashboards for data metrics
- Alerts via SNS for critical issues

### 9.2 Maintenance Windows

**Zero-downtime deployments:**

- Lambda versioning with alias updates
- Blue-green deployments for critical paths
- Snowflake changes during low-usage periods

**Regular maintenance:**

- Certificate rotation (automated via Secrets Manager)
- Software updates (managed services handle this)
- Data archival (automated via Snowflake policies)

---

## 10. Future Extensibility

### 10.1 Planned Enhancements

| Enhancement            | Architecture Impact                          |
| ---------------------- | -------------------------------------------- |
| **Real-time alerting** | Add EventBridge for complex event processing |
| **Machine learning**   | Leverage Snowflake Cortex or SageMaker       |
| **Mobile app**         | API Gateway can serve mobile clients         |
| **Edge processing**    | Add AWS IoT Greengrass for local compute     |
| **Kafka integration**  | Replace/supplement Kinesis with MSK          |

### 10.2 Architecture Flexibility

The architecture supports future changes through:

- **Protocol agnostic core**: Can add new ingestion methods
- **Loosely coupled services**: Can swap components independently
- **Standard interfaces**: Uses common formats (JSON, MQTT, HTTP)
- **Cloud-native design**: Can leverage new managed services

---

## 11. Decision Log

### 11.1 Key Architecture Decisions

| Decision              | Choice                 | Alternative Considered | Rationale                                         |
| --------------------- | ---------------------- | ---------------------- | ------------------------------------------------- |
| **MQTT Broker**       | AWS IoT Core           | EMQ X, Mosquitto       | Managed service, scales automatically             |
| **Stream Processing** | Kinesis                | Kafka, SQS             | Native AWS integration, less operational overhead |
| **Data Warehouse**    | Snowflake              | Redshift, BigQuery     | Superior semi-structured data handling            |
| **Web Framework**     | Streamlit in Snowflake | React + ECS            | Faster development, no infrastructure             |
| **Multi-tenancy**     | Database-per-tenant    | Row-level security     | Stronger isolation, simpler operations            |

### 11.2 Trade-offs Accepted

| Trade-off                    | Benefit Gained       | Risk Mitigation                       |
| ---------------------------- | -------------------- | ------------------------------------- |
| **Multiple ingestion paths** | Protocol flexibility | Standardize at Snowflake layer        |
| **Managed services lock-in** | Reduced operations   | Use standard protocols where possible |
| **Higher Snowflake costs**   | Unified platform     | Optimise with resource monitors       |
| **Eventual consistency**     | Better performance   | Design UI for eventual consistency    |

---

## 12. Tenant Onboarding Process

### 12.1 Overview

Onboarding a new tenant involves configuring resources across AWS and Snowflake to ensure complete isolation, proper authentication, and correct data routing. This process should be automated through Infrastructure as Code (IaC) but is documented here for understanding.

### 12.2 Tenant Onboarding Checklist

| Phase                  | Component         | Configuration Required           | Responsible Team         |
| ---------------------- | ----------------- | -------------------------------- | ------------------------ |
| **1. Planning**        | Business Setup    | Contract, SLAs, data volumes     | Sales/Account Management |
| **2. Identity**        | User Accounts     | SSO setup, user list, roles      | Identity Team            |
| **3. AWS Setup**       | IoT & API Gateway | Certificates, API keys, policies | Platform Team            |
| **4. Snowflake Setup** | Database & Roles  | Database creation, RBAC setup    | Data Team                |
| **5. Application**     | Portal Access     | Streamlit configuration          | Application Team         |
| **6. Validation**      | End-to-end Test   | Data flow verification           | QA Team                  |
| **7. Production**      | Go-live           | Monitoring, alerts, support      | Operations Team          |

### 12.3 Detailed Configuration Steps

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

**Step 2.1: Create IoT Thing Registry**

```
Component: AWS IoT Core
Purpose: Register tenant's gateways and devices

For each gateway:
- Thing Name: smdh-gateway-company-a-site-001
- Thing Type: LoRaWANGateway
- Attributes:
  - tenant_id: company_a
  - site_id: site-001
  - location: "Manchester Factory"
  - deployment_date: "2024-11-13"
```

**Step 2.2: Generate X.509 Certificates**

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

**Step 2.3: Create IoT Policy**

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

**Step 2.4: Configure IoT Rules**

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

#### Phase 3: API Gateway Configuration (for HTTP devices)

**Step 3.1: Generate API Key**

```
Component: API Gateway
Purpose: HTTP authentication

API Key: smdh-prod-company-a-{32-char-random}
Usage Plan: smdh-production-tier
Quota: 100M requests/month
Throttle: 1000 requests/second
```

**Step 3.2: Update DynamoDB Mapping**

```
Component: DynamoDB Table (smdh_api_key_mapping)
Purpose: Map API key to tenant

Item:
{
  "api_key": "smdh-prod-company-a-xxx",
  "tenant_id": "company_a",
  "created_date": "2024-11-13",
  "status": "active",
  "contact_email": "tech@companya.com"
}
```

#### Phase 4: Snowflake Configuration

**Step 4.1: Create Tenant Database**

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

**Step 4.2: Create Tables**

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

**Step 4.3: Setup Streaming Objects**

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

**Step 4.4: Create Roles and Users**

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

**Step 4.5: Configure Dynamic Tables**

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

#### Phase 5: Streamlit Portal Configuration

**Step 5.1: Tenant Configuration File**

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

**Step 5.2: Access Control**

```python
Component: Streamlit Access
Purpose: Tenant isolation in UI

# Automatically enforced by Snowflake role
# User's role determines accessible database
# No code changes needed - handled by Snowflake context
```

#### Phase 6: Monitoring and Alerting Setup

**Step 6.1: CloudWatch Dashboards**

```
Component: AWS CloudWatch
Purpose: Tenant-specific monitoring

Dashboard: smdh-company-a-dashboard
Widgets:
- Message ingestion rate
- Error rate
- Lambda invocations
- API Gateway requests
- Kinesis iterator age
- DLQ message count
```

**Step 6.2: Alerting Rules**

```
Component: CloudWatch Alarms + SNS
Purpose: Operational alerts

Alarms:
- High error rate (>1% for 5 minutes)
- No data received (0 messages for 15 minutes)
- Lambda errors (>10 in 5 minutes)
- Kinesis iterator age (>60 seconds)
- API throttling (>100 throttled requests)

SNS Topic: smdh-alerts-company-a
Subscribers: ops-team@company.com, tenant-contact@companya.com
```

#### Phase 7: Gateway Configuration

**Step 7.1: Physical Device Setup**

```
Component: Milesight UG65 Gateway
Purpose: Field device configuration

For MQTT path:
- Server: {iot-endpoint}.iot.eu-west-2.amazonaws.com
- Port: 8883
- Client ID: smdh-gateway-company-a-site-001
- Certificate: Upload company-a-cert.pem
- Private Key: Upload company-a-private.key
- CA Certificate: Upload AmazonRootCA1.pem
- Topic: smdh/company_a/sensor-data
- QoS: 1

For HTTP path:
- URL: https://{api-id}.execute-api.eu-west-2.amazonaws.com/prod/ingest
- Header: x-api-key: smdh-prod-company-a-xxx
- Method: POST
- Content-Type: application/json
- Retry: Enabled with exponential backoff
```

### 12.4 Validation Tests

**End-to-End Test Checklist:**

| Test                    | Description                               | Expected Result                         |
| ----------------------- | ----------------------------------------- | --------------------------------------- |
| **Device Connectivity** | Gateway connects to IoT Core/API Gateway  | Connection successful, no auth errors   |
| **Data Ingestion**      | Send test message from gateway            | Message appears in Snowflake within 30s |
| **Tenant Isolation**    | Try to access another tenant's topic/data | Access denied (403 error)               |
| **User Access**         | Login to Streamlit portal                 | Only see company_a data                 |
| **File Upload**         | Upload CSV via portal                     | File processed and visible in tables    |
| **Monitoring**          | Generate error condition                  | Alert received via SNS                  |
| **Dashboards**          | View analytics dashboards                 | Metrics display correctly               |
| **API Rate Limit**      | Send burst of requests                    | Throttling kicks in at limit            |

### 12.5 Automation Script Example

```bash
#!/bin/bash
# Tenant Onboarding Automation Script

TENANT_ID="company_a"
TENANT_NAME="Company A Manufacturing Ltd"
AWS_REGION="eu-west-2"
SNOWFLAKE_ACCOUNT="your-account"

echo "Starting tenant onboarding for $TENANT_ID..."

# 1. AWS IoT Setup
echo "Creating IoT resources..."
aws iot create-thing-type --thing-type-name "LoRaWANGateway" --region $AWS_REGION
aws iot create-thing --thing-name "smdh-gateway-${TENANT_ID}-site-001" \
  --thing-type-name "LoRaWANGateway" \
  --attribute-payload "{\"tenant_id\":\"${TENANT_ID}\"}" \
  --region $AWS_REGION

# 2. Generate certificates
CERT_ARN=$(aws iot create-keys-and-certificate --set-as-active \
  --certificate-pem-outfile ${TENANT_ID}-cert.pem \
  --private-key-outfile ${TENANT_ID}-private.key \
  --query 'certificateArn' --output text --region $AWS_REGION)

# 3. Create and attach policy
aws iot create-policy --policy-name "smdh-policy-${TENANT_ID}" \
  --policy-document file://templates/iot-policy-template.json \
  --region $AWS_REGION

aws iot attach-policy --policy-name "smdh-policy-${TENANT_ID}" \
  --target $CERT_ARN --region $AWS_REGION

# 4. API Gateway setup
API_KEY=$(openssl rand -hex 32)
aws apigateway create-api-key --name "smdh-${TENANT_ID}" \
  --value "smdh-prod-${TENANT_ID}-${API_KEY}" \
  --enabled --region $AWS_REGION

# 5. DynamoDB entry
aws dynamodb put-item --table-name smdh_api_key_mapping \
  --item "{\"api_key\":{\"S\":\"smdh-prod-${TENANT_ID}-${API_KEY}\"}, \
           \"tenant_id\":{\"S\":\"${TENANT_ID}\"}}" \
  --region $AWS_REGION

# 6. Snowflake setup (via SnowSQL)
snowsql -a $SNOWFLAKE_ACCOUNT -u admin_user -f templates/create_tenant_database.sql \
  --variable tenant_id=$TENANT_ID \
  --variable tenant_name="$TENANT_NAME"

echo "Tenant onboarding complete for $TENANT_ID"
```

### 12.6 Rollback Procedures

If onboarding fails or tenant needs to be removed:

1. **Disable IoT certificates** (prevents new data)
2. **Deactivate API keys** (blocks HTTP access)
3. **Suspend Snowflake tasks** (stops processing)
4. **Backup tenant database** (preserve data)
5. **Remove IAM roles** (revoke permissions)
6. **Clean up resources** (delete in reverse order)

### 12.7 Tenant Lifecycle Management

| Event            | Action Required                     | Timeline            |
| ---------------- | ----------------------------------- | ------------------- |
| **Onboarding**   | Full setup as documented            | 2-4 hours automated |
| **Scaling Up**   | Add warehouses, increase limits     | 30 minutes          |
| **Scaling Down** | Reduce warehouses, adjust retention | 30 minutes          |
| **Suspension**   | Disable ingestion, preserve data    | 15 minutes          |
| **Reactivation** | Re-enable ingestion, validate       | 1 hour              |
| **Offboarding**  | Export data, remove resources       | 4-8 hours           |

---

## 13. Conclusion

The SMDH architecture balances several competing requirements:

- **Flexibility** to handle diverse data sources
- **Simplicity** through managed services
- **Security** via multi-layered isolation
- **Scalability** using cloud-native patterns
- **Cost-effectiveness** with serverless and on-demand pricing

By choosing ingestion paths based on data source protocols rather than forcing a one-size-fits-all approach, we achieve optimal performance and reliability while maintaining operational simplicity.

The architecture is designed to start simple and grow with the business, adding capabilities as needed without major redesigns. The comprehensive tenant onboarding process ensures consistent, secure deployment for each new customer.

---

## Appendix A: Component Mapping

| Business Requirement   | Technical Component | AWS Service     |
| ---------------------- | ------------------- | --------------- |
| Receive sensor data    | MQTT broker         | IoT Core        |
| Handle HTTP webhooks   | REST API            | API Gateway     |
| Buffer streaming data  | Message queue       | Kinesis         |
| Validate and transform | Compute layer       | Lambda          |
| Store sensor data      | Data warehouse      | Snowflake       |
| Upload files           | Web portal          | Streamlit       |
| Manage credentials     | Secrets store       | Secrets Manager |
| Monitor system         | Observability       | CloudWatch      |
| Send alerts            | Notification        | SNS             |

## Appendix B: Glossary

| Term               | Definition                                                       |
| ------------------ | ---------------------------------------------------------------- |
| **MQTT**           | Message Queuing Telemetry Transport - IoT communication protocol |
| **LoRaWAN**        | Long Range Wide Area Network - IoT radio protocol                |
| **JWT**            | JSON Web Token - Authentication token format                     |
| **CDC**            | Change Data Capture - Tracking data modifications                |
| **VARIANT**        | Snowflake data type for semi-structured data                     |
| **Dynamic Tables** | Snowflake feature for materialized views with auto-refresh       |
| **Streamlit**      | Python framework for data applications                           |
| **X.509**          | Standard for public key certificates                             |
| **SAML**           | Security Assertion Markup Language - SSO protocol                |
| **IaC**            | Infrastructure as Code - Managing infrastructure through code    |
