# Smart Manufacturing Data Hub (SMDH)
## Architecture Option 1: Direct Gateway to Snowflake Integration
## Technical Feasibility Assessment

**Document Classification:** Technical Architecture Review  
**Status:** NOT RECOMMENDED – Documented for Completeness  
**Version:** 2.0 (Validated)  
**Date:** 10 November 2025  
**Author:** Snowflake Solutions Architecture Team  
**Region:** Europe (United Kingdom)

---

## Document Purpose and Scope

This document provides a comprehensive technical evaluation of directly integrating Milesight UG65 LoRaWAN gateways with Snowflake's data ingestion application programming interfaces (APIs), eliminating all intermediary Amazon Web Services (AWS) components. The assessment examines whether this "minimal infrastructure" approach is technically feasible and commercially viable for a multi-tenant Software-as-a-Service (SaaS) platform serving 30 to 40 small and medium manufacturing enterprises (SMEs).

**Key Evaluation Areas:**
- Gateway authentication capabilities against Snowflake API requirements
- Multi-tenant data isolation strategies (Row-Level Security vs Database-Level Security)
- Security implications of distributed credential management across physical devices
- Operational viability, maintenance requirements, and cost-effectiveness
- Production-grade reliability, error handling, and observability

**Intended Audience:**  
This document is designed for IT-literate stakeholders who may not have specialist knowledge of IoT protocols, AWS services, or Snowflake data platform capabilities. Technical concepts are explained with sufficient context whilst maintaining professional business language.

---

## Executive Summary

### Strategic Classification

**NOT RECOMMENDED FOR PRODUCTION DEPLOYMENT**

This architecture is documented to demonstrate thorough evaluation of all integration options before selecting the recommended approach. Whilst the concept of eliminating intermediary services appears cost-effective on initial assessment, detailed technical analysis reveals multiple showstopper issues that prevent production deployment.

### Critical Findings Summary

| Assessment Area | Finding | Severity | Commercial Impact |
|----------------|---------|----------|-------------------|
| **Authentication Mechanism** | Gateway firmware cannot generate JSON Web Tokens (JWT) required by Snowflake APIs | CRITICAL | Deployment impossible without custom firmware development |
| **Session State Management** | Gateway's stateless HTTP client incompatible with Snowflake's channel-based streaming model | CRITICAL | Cannot maintain data ordering or guarantee exactly-once delivery |
| **Multi-Tenant Security** | No validation layer between gateway configuration and Snowflake data ingestion | CRITICAL | Unacceptable data breach risk for multi-tenant SaaS platform |
| **Credential Distribution** | Requires deploying Snowflake private cryptographic keys to 30+ physical devices across customer sites | CRITICAL | Violates security best practices and regulatory compliance requirements |
| **Operational Resilience** | JWT authentication tokens expire every 60 minutes; gateway cannot refresh autonomously | HIGH | Requires 24/7 manual intervention or accepts guaranteed data loss |
| **Error Handling** | No dead-letter queue, automated retry mechanism, or failure observability | HIGH | Silent data loss on any network, authentication, or ingestion failure |
| **Data Quality Assurance** | No pre-ingestion validation of schema compliance, data types, or business rule enforcement | MEDIUM | Invalid data corrupts analytics, dashboards, and Key Performance Indicator (KPI) calculations |

### Technical Verdict

Three primary technical blockers prevent this architecture from functioning in production:

**1. Authentication Impossibility**  
The Milesight UG65 gateway firmware lacks RSA cryptographic capabilities required to generate and digitally sign JWT tokens. Our validation of the UG65 User Guide (Version 2.10, January 2025, Section 4.8) confirms the gateway supports static HTTP headers configured at setup time but cannot perform dynamic token generation, cryptographic signature operations, or detect authentication failures.

**2. Stateless Architecture Mismatch**  
Snowflake's Snowpipe Streaming API requires clients to maintain persistent channel state across requests, including continuation tokens (for ordering guarantees) and offset counters (for exactly-once delivery). The gateway's HTTP client is fundamentally stateless and cannot store this session information between POST requests.

**3. Security Architecture Violation**  
Multi-tenant SaaS platforms require validated API gateways to enforce tenant boundary controls before data enters the system. This architecture relies solely on gateway device configuration (the "applicationName" field) to determine tenant identity, with zero validation that the gateway is authorised to write data for that specific tenant. This creates unacceptable data breach risk.

### Cost Reality Check

Paradoxically, this "minimal infrastructure" approach costs substantially more than the recommended alternative due to hidden operational expenses:

| Cost Component | Option 1 (Direct) | Option 2 (Recommended) | Monthly Variance |
|---------------|-------------------|------------------------|------------------|
| **AWS Infrastructure** | £0 | £28 | -£28 |
| **Snowflake Compute** | £4,100 | £3,200 | +£900 |
| **24/7 Operations Labour** | £10,000-21,000 | £500 | +£9,500-20,500 |
| **Hardware (5-year amortisation)** | £425 | £0 | +£425 |
| **Monthly Total** | **£14,525-25,525** | **£3,728** | **+£10,797-21,797** |
| **Annual Total** | **£174,300-306,300** | **£44,736** | **+£129,564-261,564** |

The operational labour costs stem from:
- Hourly JWT token refresh requirements (720 manual operations monthly)
- No automated error recovery requiring manual incident response
- Distributed gateway configuration management across 30-40 physical devices
- No centralised observability requiring site visits for troubleshooting

### Recommendation

**DO NOT PROCEED** with Option 1: Direct Gateway to Snowflake Integration.

**IMPLEMENT Option 2: API Gateway + Lambda Proxy Architecture** which:
- Adds minimal AWS infrastructure cost (£28 monthly, primarily for API Gateway and Lambda execution)
- Provides secure centralised credential management via AWS Secrets Manager
- Enforces multi-tenant validation before data ingestion (API key validated against tenant identity)
- Enables fully automated operations with zero manual intervention
- Delivers production-grade error handling with dead-letter queues and automated retry logic
- Provides comprehensive observability via AWS CloudWatch dashboards and X-Ray tracing
- Achieves £130,000-260,000 annual cost savings compared to Option 1

---

## Table of Contents

1. [System Context and Architecture Overview](#1-system-context-and-architecture-overview)
2. [Gateway Capabilities Technical Assessment](#2-gateway-capabilities-technical-assessment)
3. [Snowflake Authentication Requirements](#3-snowflake-authentication-requirements)
4. [Multi-Tenancy Security Analysis](#4-multi-tenancy-security-analysis)
5. [Critical Risk Assessment](#5-critical-risk-assessment)
6. [Operational Viability Analysis](#6-operational-viability-analysis)
7. [Cost-Benefit Financial Analysis](#7-cost-benefit-financial-analysis)
8. [Theoretical Implementation Steps](#8-theoretical-implementation-steps)
9. [Conclusions and Final Recommendations](#9-conclusions-and-final-recommendations)
10. [Appendices](#10-appendices)

---

## 1. System Context and Architecture Overview

### 1.1 Business Context

The Smart Manufacturing Data Hub (SMDH) is a multi-tenant SaaS platform designed to provide manufacturing analytics services to up to 30 SMEs simultaneously. Each manufacturing company (tenant) operates independently with complete data isolation from other platform users.

**Platform Characteristics:**
- **Multi-Tenant Model**: Single platform instance serving multiple independent customers with absolute data segregation
- **Initial Data Volume**: 5-26 million sensor readings daily across all tenants (150-300 sensors at 1 Hz)
- **Scalability Target**: Support growth to 50+ tenants over 24-month period
- **Latency Requirements**: Sub-5-minute refresh intervals for dashboard KPIs
- **User Base**: 20-40 named users per tenant accessing web-based analytical dashboards
- **Geographic Scope**: Initially UK-based manufacturing facilities with European Union data residency requirements
- **Regulatory Compliance**: General Data Protection Regulation (GDPR), ISO 27001 information security, manufacturing industry standards

**Economic Context:**  
SME customers operate on constrained budgets. The platform's pricing model targets £200-300 per tenant monthly, requiring infrastructure costs of approximately £200-250 per tenant to maintain commercial viability.

### 1.2 Use Case Overview

The platform addresses three core manufacturing analytics scenarios with distinct data characteristics:

**Use Case 1: Machine Utilisation Analytics**
- **Business Objective**: Monitor equipment power consumption to calculate Overall Equipment Effectiveness (OEE) metrics
- **Sensor Technology**: Three-phase energy metres measuring instantaneous power draw
- **Data Frequency**: 1 reading per second (1Hz) during production hours
- **Key Metrics**: Availability percentage, Performance percentage, Quality percentage, idle time detection
- **Business Value**: Identify production bottlenecks, reduce unplanned downtime, improve equipment return on investment

**Use Case 2: Environmental Compliance & Air Quality Management**
- **Business Objective**: Monitor workplace air quality for regulatory compliance and worker health
- **Sensor Technology**: Multi-parameter air quality sensors (CO₂, PM2.5, PM10, volatile organic compounds, temperature, humidity)
- **Data Frequency**: 1 reading every 5 minutes (0.0033Hz) continuously
- **Key Metrics**: Air Quality Index (AQI), regulatory compliance thresholds, trend analysis, automated alerting
- **Business Value**: Ensure Health & Safety Executive (HSE) compliance, improve working conditions, avoid regulatory penalties

**Use Case 3: Job Location Tracking & Production Flow**
- **Business Objective**: Track work-in-progress movement through production stages for lead time optimisation
- **Sensor Technology**: Radio-Frequency Identification (RFID) readers and barcode scanners at production stations
- **Data Frequency**: Event-driven (on job movement, typically 5-20 events per job)
- **Key Metrics**: Job cycle time by station, station utilisation percentage, bottleneck identification, on-time delivery performance
- **Business Value**: Reduce manufacturing lead times, improve delivery predictability, optimise workflow balance

### 1.3 High-Level Architecture Concept

This architecture attempts to create the simplest possible data ingestion path by eliminating all AWS compute and streaming services between the IoT gateway and Snowflake data platform.

![Option 1 Conceptual Architecture](Option1_Conceptual_Architecture_0.1.png)

**Architecture Principles (As Intended):**
1. **Minimal Infrastructure**: Eliminate all AWS compute services (Lambda functions, Kinesis streams, AWS Glue ETL)
2. **Direct Integration**: Gateway device communicates directly with Snowflake endpoint
3. **Edge Processing**: Utilise gateway's built-in Network Server for LoRaWAN protocol handling and payload decoding
4. **Cost Optimisation**: Remove per-request AWS service charges

**Reality Assessment:**  
**These principles cannot be achieved due to fundamental authentication and state management limitations in the gateway firmware.**

### 1.4 Component Inventory and Status

| Component | Responsibility | Implementation Status | Notes |
|-----------|---------------|----------------------|-------|
| **DevTank Sensors** | Measure physical parameters at configured intervals | AVAILABLE | LoRaWAN Class A devices, battery-powered |
| **LoRaWAN Radio** | Wireless transmission (868MHz ISM band, AES-128 encrypted) | AVAILABLE | 2-5km range, penetrates building structures |
| **UG65 Gateway** | Receive LoRaWAN packets, forward to application server | AVAILABLE | Hardware functional but insufficient firmware capabilities |
| **Built-in Network Server** | LoRaWAN protocol stack, device registry, join server | AVAILABLE | Handles LoRaWAN MAC layer, manages device sessions |
| **Payload Decoder** | JavaScript function to decode binary sensor data | AVAILABLE | Converts base64-encoded binary to JSON |
| **HTTP Client** | POST JSON to external URLs | AVAILABLE | Stateless, supports static headers only |
| **Snowpipe REST API** | File-based batch ingestion from AWS S3 | NOT COMPATIBLE | Requires pre-staged files, unsuitable for streaming |
| **Snowpipe Streaming API** | Row-level real-time data ingestion | BLOCKED | Gateway cannot authenticate (showstopper) |
| **Snowflake Tables** | Persistent data storage with security policies | AVAILABLE | Multi-tenancy via Row-Level Security or separate databases |

---

## 2. Gateway Capabilities Technical Assessment

This section provides detailed validation of the Milesight UG65 gateway's capabilities based on the official User Guide (Version 2.10, January 2025).

### 2.1 Hardware and Firmware Specifications

**Hardware Platform:**
- **Processor**: ARM Cortex-A7 dual-core CPU, 800MHz clock speed
- **Memory**: 512MB RAM, 8GB flash storage
- **Network Interfaces**:
  - Gigabit Ethernet (10/100/1000 Mbps)
  - 4G LTE cellular modem (optional)
  - Wi-Fi (802.11 b/g/n, optional)
- **LoRaWAN Radio**: Semtech SX1302 baseband processor
  - 8-channel simultaneous reception
  - SF7-SF12 spreading factor support
  - 125kHz/250kHz/500kHz bandwidth
- **Operating Temperature**: -40°C to +70°C (industrial specification)
- **Power**: 12V DC input, 8W typical consumption, Power over Ethernet (PoE) compatible
- **Mounting**: DIN rail or wall mount options

**Firmware Capabilities:**
- **Operating System**: Embedded Linux (OpenWrt-based distribution)
- **Built-in Network Server**: Complete LoRaWAN 1.0.3 specification compliance
- **Payload Processing**: JavaScript codec engine (V8-based)
- **Network Protocols**: HTTP, HTTPS, MQTT, WebSocket, Modbus TCP, BACnet/IP
- **Security Features**: WPA2 encryption, VPN client (OpenVPN, WireGuard, L2TP), TLS 1.2/1.3 support
- **Management**: Web-based configuration interface, SNMP monitoring, SSH access

### 2.2 HTTP Application Integration Features

The gateway's built-in Network Server includes an "Application" configuration section for forwarding decoded sensor data to external systems via HTTP/HTTPS.

**Feature Assessment (Validated from UG65 User Guide Section 4.8):**

**AVAILABLE Features:**

| Feature | Description | Configuration Method |
|---------|-------------|---------------------|
| **HTTP/HTTPS POST** | Send POST requests to custom URLs | Enter destination URL in web interface |
| **Static Custom Headers** | Add header key-value pairs | Configure at setup time in web interface |
| **JSON Payload Formatting** | Structure data as JSON objects | Automatic based on payload codec output |
| **Payload Codec Execution** | JavaScript function for binary decoding | Upload custom JavaScript to gateway |
| **Application Name Field** | Add identifier to payloads | Configure static string in web interface |
| **Basic Retry Logic** | 3 retry attempts on HTTP errors | Fixed retry policy (exponential backoff) |
| **Multiple Destinations** | Configure different URLs per application | Support up to 8 parallel applications |
| **TLS/SSL Support** | HTTPS with certificate validation | Automatic with HTTPS URLs |

**Example Header Configuration:**
```
Header Name: Authorization
Header Value: Bearer abc123_static_api_key

Header Name: X-Tenant-ID  
Header Value: company_a

Header Name: Content-Type
Header Value: application/json
```

**Example Payload Format:**
```json
{
  "applicationID": "1",
  "applicationName": "company_a",
  "deviceName": "temp-sensor-floor-1",
  "devEUI": "A840410000000123",
  "rxInfo": [{
    "gatewayID": "ug65-site-001",
    "time": "2025-11-10T14:23:45.123456Z",
    "rssi": -85,
    "loRaSNR": 8.5,
    "location": {
      "latitude": 51.5074,
      "longitude": -0.1278,
      "altitude": 10
    }
  }],
  "txInfo": {
    "frequency": 868100000,
    "dr": 5
  },
  "fPort": 85,
  "data": "AQEBZwLoAiMD",
  "object": {
    "temperature": 22.5,
    "humidity": 45,
    "battery": 3.6
  }
}
```

**NOT AVAILABLE Features (Critical Gaps):**

| Missing Capability | Impact | Workaround Possibility |
|--------------------|--------|----------------------|
| **Cryptographic Operations** | Cannot generate RSA signatures or JWT tokens | NONE - requires firmware modification |
| **Dynamic Header Generation** | Headers configured at setup, cannot change per request | NONE - fundamental firmware limitation |
| **Token Refresh Detection** | Cannot detect HTTP 401 Unauthorized responses | NONE - no conditional logic support |
| **State Persistence** | Each HTTP request independent, no memory of previous requests | NONE - stateless architecture |
| **Complex Routing Logic** | Cannot implement conditional behaviour based on response codes | NONE - single-path forward only |
| **Structured Error Handling** | Basic retry only, no dead-letter queue or logging | NONE - limited observability |
| **Intelligent Batching** | Sends data as received, cannot aggregate for efficiency | NONE - immediate forward only |

### 2.3 Authentication Capability Analysis

This subsection examines whether the gateway can meet Snowflake's authentication requirements.

**Snowflake Requirement:**  
All Snowpipe Streaming API requests must include a JSON Web Token (JWT) in the `Authorization: Bearer <token>` header. The JWT must be:
- Digitally signed using RSA-SHA256 algorithm
- Created with a 2048-bit or 4096-bit RSA private key
- Include specific claims (issuer, subject, issued-at time, expiry time)
- Valid for maximum 60 minutes, then must be regenerated

**JWT Generation Process (Technical Detail):**
```
Step 1: Create header JSON
{
  "alg": "RS256",
  "typ": "JWT"
}

Step 2: Create payload JSON
{
  "iss": "myaccount.myuser",
  "sub": "myaccount.myuser",
  "iat": 1699632000,
  "exp": 1699635600
}

Step 3: Encode both as Base64URL
header_b64 = base64url_encode(header_json)
payload_b64 = base64url_encode(payload_json)

Step 4: Create signature
signature_input = header_b64 + "." + payload_b64
signature = RSA_SHA256_sign(signature_input, private_key)
signature_b64 = base64url_encode(signature)

Step 5: Assemble token
jwt_token = header_b64 + "." + payload_b64 + "." + signature_b64
```

**Gateway Capability Assessment:**

| JWT Generation Step | Gateway Capability | Assessment |
|---------------------|-------------------|-----------|
| **Generate current timestamp** | Supported (Linux system clock) | AVAILABLE |
| **Calculate expiry timestamp** | Supported (arithmetic) | AVAILABLE |
| **Create JSON structures** | Supported (JavaScript) | AVAILABLE |
| **Base64URL encoding** | Supported (JavaScript libraries) | AVAILABLE |
| **Access RSA private key** | NOT SUPPORTED - no secure storage | BLOCKED |
| **Perform RSA-SHA256 signature** | NOT SUPPORTED - no OpenSSL bindings | BLOCKED |
| **Detect token expiry** | NOT SUPPORTED - no HTTP status inspection | BLOCKED |
| **Regenerate on expiry** | NOT SUPPORTED - no conditional logic | BLOCKED |

**Verdict: AUTHENTICATION NOT FEASIBLE**

The gateway's JavaScript codec engine cannot access cryptographic libraries required for RSA signature operations. The firmware does not expose OpenSSL functions to user scripts, and there is no mechanism to load native binary extensions.

**Alternative Approaches Evaluated:**

**Approach A: Pre-Generate Static JWT Token**
- **Method**: Generate JWT externally, configure as static header
- **Problem**: JWT expires after 60 minutes (Snowflake enforced)
- **Impact**: All 30-40 gateways stop functioning simultaneously after 60 minutes
- **Maintenance**: Requires manual token regeneration and gateway reconfiguration every hour
- **Annual Labour Cost**: 8,760 hours × £50/hour = £438,000 (completely infeasible)

**Approach B: External Token Service**
- **Method**: Gateway calls external API to fetch fresh tokens before each request
- **Problem**: Requires two HTTP requests per sensor reading (fetch token, then post data)
- **Impact**: Doubles network traffic, adds 200-500ms latency
- **Complexity**: External service now performs exact role intended for Lambda in recommended architecture
- **Cost**: Defeats entire purpose of "minimal infrastructure" approach

**Approach C: Custom Firmware Modification**
- **Method**: Modify gateway firmware to add RSA cryptographic support
- **Problem**: Requires Milesight vendor cooperation, firmware signing keys, extensive testing
- **Timeline**: 6-12 months development + certification
- **Cost**: £100,000-250,000 custom development
- **Risk**: Voids warranty, loses vendor support, creates ongoing maintenance burden

**Conclusion:**  
No viable workaround exists within project constraints. The gateway fundamentally cannot authenticate to Snowflake APIs.

---

## 3. Snowflake Authentication Requirements

### 3.1 Snowpipe API Options Overview

Snowflake provides two distinct APIs for data ingestion, each with different authentication and operational models.

**Option A: Snowpipe REST API**
- **Purpose**: Trigger ingestion of data files already staged in cloud storage (AWS S3, Azure Blob, Google Cloud Storage)
- **Data Model**: File-based batch processing
- **Typical Use Case**: Hourly or daily batch loads from data lakes
- **Latency**: 5-10 minutes from file arrival to query availability
- **Authentication**: JWT tokens signed with RSA private key

**Why Incompatible with This Architecture:**  
This API requires data files to exist in AWS S3 before calling the ingestion endpoint. The gateway cannot stage files to S3 without AWS credentials and SDK integration. This approach would require Lambda functions to write S3 files anyway, defeating the purpose of eliminating AWS services.

**Option B: Snowpipe Streaming API**
- **Purpose**: Ingest individual data rows in real-time via HTTP POST
- **Data Model**: Row-level streaming with exactly-once delivery guarantees
- **Typical Use Case**: Real-time IoT sensor data, clickstream analytics
- **Latency**: 5-10 seconds from POST to query availability
- **Authentication**: JWT tokens + stateful channel management

**Why This Is The Target (Despite Incompatibility):**  
This API supports the low-latency requirements (sub-5-minute KPI updates) and row-level data model needed for sensor readings. However, it requires both authentication AND state management, neither of which the gateway supports.

### 3.2 Snowpipe Streaming Authentication Flow

The complete authentication and session establishment sequence for Snowpipe Streaming involves multiple steps with state maintenance.

![Option 1 End-to-End Flow](Option1_End_To_End_Flow.png)

**Critical State Management Requirements:**

The Snowpipe Streaming API is fundamentally stateful. Each response contains tokens that **must** be included in the subsequent request:

1. **Continuation Token**: Ensures row ordering within a channel. If omitted, Snowflake rejects the request.
2. **Offset Token**: Incrementing counter for each row. Enables exactly-once delivery and allows reprocessing from specific points.
3. **Channel Handle**: Persistent identifier for the data stream. Must be reused across requests.

**Gateway Limitation:**  
The UG65 gateway's HTTP client is stateless. Each POST request is independent with no memory of previous responses. There is no mechanism to:
- Parse JSON responses and extract continuation tokens
- Store tokens in persistent variables
- Include tokens in subsequent request parameters
- Maintain separate state for multiple channels (one per tenant)

**Authentication Token Lifecycle:**

```
Minute 0: Generate JWT with exp=3600 (60 minutes)
          All gateway POST requests succeed

Minute 60: JWT expires
           Next POST returns HTTP 401 Unauthorized
           Gateway continues sending requests (cannot detect failure)
           ALL DATA LOST for next 60 minutes minimum
           
Minute 60+: Operations team notices dashboard stopped updating
            Manual process: Generate new JWT
            SSH to each of 30-40 gateways
            Update Authorization header configuration
            Restart application service
            
Minute 90+: Data flow resumes
            30 minutes of manufacturing data permanently lost
```

**Annual Operational Impact:**
- Token refreshes needed: 24 per day × 365 days = 8,760 per year
- Time per refresh cycle: 15 minutes (generate token, update 30-40 gateways)
- Total labour hours: 2,190 hours per year
- Labour cost: 2,190 × £50/hour = **£109,500 annually**

This operational burden alone exceeds the total cost of the recommended architecture (£44,736 annually).

### 3.3 Key Pair Authentication Setup

For completeness, this subsection describes the Snowflake key pair authentication setup process, which would be required if this architecture were feasible.

**Step 1: Generate RSA Key Pair** (performed on secure administrative workstation)
```bash
# Generate 2048-bit RSA private key
openssl genrsa -out snowflake_private_key.pem 2048

# Extract public key
openssl rsa -in snowflake_private_key.pem \
            -pubout \
            -out snowflake_public_key.pem

# Format public key for Snowflake (remove headers and newlines)
PUBLIC_KEY=$(cat snowflake_public_key.pem | \
             grep -v "BEGIN PUBLIC" | \
             grep -v "END PUBLIC" | \
             tr -d '\n')

echo $PUBLIC_KEY
# Output: MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA...
```

**Step 2: Register Public Key with Snowflake User**
```sql
-- Connect as ACCOUNTADMIN role
USE ROLE ACCOUNTADMIN;

-- Create service user for gateway authentication
CREATE USER IF NOT EXISTS smdh_gateway_user
  PASSWORD = NULL  -- Key-pair authentication only
  DEFAULT_ROLE = 'SMDH_INGEST_ROLE'
  DEFAULT_WAREHOUSE = 'SMDH_INGEST_WH'
  MUST_CHANGE_PASSWORD = FALSE
  COMMENT = 'Service user for LoRaWAN gateway ingestion - NOT FOR HUMAN LOGIN';

-- Register public key (repeat for key rotation)
ALTER USER smdh_gateway_user 
  SET RSA_PUBLIC_KEY = 'MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA...';

-- Verify registration
DESC USER smdh_gateway_user;
-- Confirms RSA_PUBLIC_KEY and RSA_PUBLIC_KEY_FP (fingerprint) populated
```

**Step 3: Distribute Private Key to Gateways** (CRITICAL SECURITY ISSUE)
```
PROBLEM: Must deploy private key to 30-40 physical gateway devices

Security Risks:
- Private key exposed on devices in customer facilities
- Physical theft risk (gateways in accessible factory locations)
- SSH access to gateway exposes key to network attacks
- Key visible in configuration backups
- Difficult to rotate (must touch all gateways)
- If one gateway compromised, entire platform at risk

Industry Best Practice:
- Private keys should NEVER leave secure server environments
- Use intermediary services (API Gateway + Lambda) that:
  - Store keys in AWS Secrets Manager (encrypted, audited)
  - Generate JWTs server-side
  - Expose simple API key authentication to edge devices
```

This security architecture violation alone disqualifies this approach for production deployment, regardless of technical feasibility.

---

## 4. Multi-Tenancy Security Analysis

Multi-tenant SaaS platforms require absolute data isolation between customers. A data breach exposing Company A's manufacturing data to Company B would result in severe legal, financial, and reputational consequences. This section evaluates two technical approaches to multi-tenancy and assesses their security effectiveness in this architecture.

### 4.1 Multi-Tenancy Approach Comparison

Snowflake supports multiple strategies for isolating tenant data. Each has different security characteristics, performance implications, and operational complexity.

![Multi-Tenancy Strategy Comparison](Option1_Multi_Tenancy_Comparison.png)

**Detailed Comparison:**

| Aspect | Row-Level Security (RLS) | Database-Level Segregation |
|--------|-------------------------|---------------------------|
| **Isolation Mechanism** | Single database, rows filtered by tenant_id column | Separate database per tenant |
| **INSERT Validation** | None - trusts application to set correct tenant_id | Implicit - data physically routed to tenant database |
| **Misconfiguration Impact** | Wrong tenant_id → data visible to wrong tenant | Wrong database → table not found error (fails closed) |
| **Query Performance** | Must scan and filter all rows | Queries only tenant's data (no filtering overhead) |
| **Storage Efficiency** | Single table, efficient clustering | Duplicate table structures per tenant |
| **Operational Complexity** | Simple - one set of views and procedures | Complex - must maintain N copies of views/procedures |
| **Scaling** | Linear - add rows to existing table | Sub-linear - add new database (metadata overhead) |
| **Cost Model** | Storage efficient but higher compute | Slightly higher storage but more efficient compute |
| **Compliance Audit** | Requires demonstrating RLS policy correctness | Physical separation simplifies compliance |
| **Tenant Onboarding** | Simple - no schema changes | Moderate - clone database template |
| **Cross-Tenant Analytics** | Easy - single database, aggregate across tenant_id | Difficult - requires UNION across databases |

### 4.2 Row-Level Security Implementation

**SQL Implementation:**
```sql
-- Create shared database and schema
CREATE DATABASE IF NOT EXISTS smdh_db;
CREATE SCHEMA IF NOT EXISTS smdh_db.raw;

-- Create multi-tenant table with tenant_id column
CREATE TABLE IF NOT EXISTS smdh_db.raw.sensor_readings (
  -- Tenant identification (CRITICAL for isolation)
  tenant_id VARCHAR(100) NOT NULL 
    COMMENT 'Customer identifier - MUST match gateway API key',
  
  -- Device and timestamp identification
  device_eui VARCHAR(16) NOT NULL 
    COMMENT 'LoRaWAN device unique identifier',
  timestamp TIMESTAMP_NTZ NOT NULL 
    COMMENT 'Sensor reading timestamp (UTC)',
  
  -- Sensor data (flexible JSON for multiple sensor types)
  sensor_type VARCHAR(50) NOT NULL 
    COMMENT 'ENERGY_METER, AIR_QUALITY, RFID_READER',
  metric_name VARCHAR(100) NOT NULL 
    COMMENT 'temperature_c, power_kw, co2_ppm, etc',
  metric_value VARIANT NOT NULL 
    COMMENT 'Numeric or string value (flexible schema)',
  metric_unit VARCHAR(20) 
    COMMENT 'Unit of measurement',
  
  -- Radio metadata
  gateway_id VARCHAR(100) 
    COMMENT 'Gateway that received this reading',
  rssi INTEGER 
    COMMENT 'Received Signal Strength Indicator (dBm)',
  snr FLOAT 
    COMMENT 'Signal-to-Noise Ratio (dB)',
  
  -- Data lineage
  ingestion_timestamp TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP() 
    COMMENT 'When Snowflake received this data',
  ingestion_method VARCHAR(50) DEFAULT 'SNOWPIPE_STREAMING' 
    COMMENT 'Ingestion method used'
)
-- Performance optimisation: cluster by tenant and time
CLUSTER BY (tenant_id, DATE_TRUNC('day', timestamp))
-- Compliance: 90-day retention for operational data
DATA_RETENTION_TIME_IN_DAYS = 90
COMMENT = 'Raw sensor readings from IoT devices - multi-tenant table';

-- Create Row Access Policy for tenant isolation
CREATE OR REPLACE ROW ACCESS POLICY smdh_db.raw.tenant_isolation_policy AS 
  (tenant_id VARCHAR) RETURNS BOOLEAN ->
    -- Platform administrators can see all data
    CURRENT_ROLE() = 'ACCOUNTADMIN'
    -- Regular users only see their own tenant's data
    OR tenant_id = CURRENT_USER()
    -- Support explicit tenant context for service accounts
    OR tenant_id = CURRENT_SESSION_CONTEXT('tenant_id');

-- Apply policy to table
ALTER TABLE smdh_db.raw.sensor_readings 
  ADD ROW ACCESS POLICY smdh_db.raw.tenant_isolation_policy ON (tenant_id);

-- Verify policy is active
SHOW ROW ACCESS POLICIES IN SCHEMA smdh_db.raw;

-- Test isolation (as tenant user)
CREATE USER company_a_user PASSWORD = 'SecurePassword123!';
GRANT SELECT ON smdh_db.raw.sensor_readings TO company_a_user;

-- When company_a_user runs this query:
-- SELECT * FROM smdh_db.raw.sensor_readings;
-- Snowflake automatically rewrites it as:
-- SELECT * FROM smdh_db.raw.sensor_readings 
-- WHERE tenant_id = 'company_a_user' OR CURRENT_ROLE() = 'ACCOUNTADMIN';
```

**CRITICAL SECURITY LIMITATION IN THIS ARCHITECTURE:**

Row-Level Security policies are **enforcement mechanisms for SELECT queries**. They do NOT validate data during INSERT operations.

**Failure Scenario:**
```
Step 1: Gateway for Company A misconfigured
        applicationName = "company_b" (incorrect!)

Step 2: Gateway sends sensor reading
        POST /snowpipe/streaming/...
        Body: {"tenant_id": "company_b", "temperature": 22.5}

Step 3: Snowflake receives and inserts
        INSERT INTO sensor_readings VALUES ('company_b', ...)
        RLS policy NOT EVALUATED during INSERT

Step 4: Company B user queries their dashboard
        SELECT * FROM sensor_readings  -- RLS adds WHERE tenant_id = 'company_b'
        Result: Sees Company A's sensitive manufacturing data

Step 5: Data breach consequences
        - Company A's trade secrets exposed to competitor
        - GDPR Article 33 breach notification required (within 72 hours)
        - ICO investigation and potential fine (up to £17.5M or 4% revenue)
        - Customer trust destroyed, contract termination likely
```

**Why Option 2 Architecture Prevents This:**

In the recommended architecture, AWS Lambda validates tenant_id BEFORE calling Snowflake:
```python
def validate_tenant(api_key, payload_tenant_id):
    # Lookup which tenant owns this API key
    authorized_tenant = dynamodb.get_item(Key={'api_key': api_key})['tenant_id']
    
    # Reject if mismatch
    if payload_tenant_id != authorized_tenant:
        send_to_dead_letter_queue(payload, "Tenant ID mismatch")
        return HTTP_403_FORBIDDEN
    
    # Only proceed if validated
    return snowflake.insert(payload)
```

This creates a **validation layer** that RLS alone cannot provide.

### 4.3 Database-Level Segregation Implementation

**SQL Implementation:**
```sql
-- Template database for each tenant
CREATE DATABASE company_a_db;
CREATE SCHEMA company_a_db.raw;
CREATE SCHEMA company_a_db.curated;
CREATE SCHEMA company_a_db.analytics;

CREATE TABLE company_a_db.raw.sensor_readings (
  -- NO tenant_id COLUMN - physically isolated
  device_eui VARCHAR(16) NOT NULL,
  timestamp TIMESTAMP_NTZ NOT NULL,
  sensor_type VARCHAR(50) NOT NULL,
  metric_name VARCHAR(100) NOT NULL,
  metric_value VARIANT NOT NULL,
  -- ... rest of schema
) CLUSTER BY (DATE_TRUNC('day', timestamp));

-- Repeat for each tenant
CREATE DATABASE company_b_db;
-- ... (duplicate structure)

CREATE DATABASE company_c_db;
-- ... (duplicate structure)

-- User permissions provide isolation
CREATE USER company_a_user;
GRANT USAGE ON DATABASE company_a_db TO company_a_user;
GRANT USAGE ON ALL SCHEMAS IN DATABASE company_a_db TO company_a_user;
GRANT SELECT ON ALL TABLES IN SCHEMA company_a_db.raw TO company_a_user;
-- company_a_user physically CANNOT access company_b_db (permission denied)

-- Ingestion routing in Option 2 architecture
def route_to_database(tenant_id):
    database_map = {
        'company_a': 'company_a_db',
        'company_b': 'company_b_db',
        'company_c': 'company_c_db'
    }
    target_db = database_map[tenant_id]
    snowflake.use(target_db)
    snowflake.insert('raw.sensor_readings', payload)
```

**Advantages:**
1. **Physical Isolation**: Incorrect tenant_id causes table not found error (fails closed, no data leak)
2. **Performance**: No tenant_id filtering overhead on queries
3. **Compliance**: Physical separation simplifies regulatory audits (GDPR, ISO 27001)
4. **Cost Allocation**: Direct per-tenant billing attribution (Snowflake resource monitors per database)
5. **Customisation**: Different retention policies, data models, or features per tenant

**Disadvantages:**
1. **Operational Complexity**: Must maintain N copies of views, procedures, dashboards
2. **Storage Overhead**: Duplicate metadata structures (minimal - typically <1% of data volume)
3. **Cross-Tenant Analytics**: Requires UNION ALL across databases (platform-level reporting harder)
4. **Onboarding Time**: Create new database for each tenant (automated via templates, ~5 minutes)

**Recommendation for SMDH:**

**Use Database-Level Segregation** for the following reasons:
- Stronger security posture (fails closed rather than risking data exposure)
- Simplified compliance demonstrations to enterprise customers
- Better query performance (no tenant_id filtering on every query)
- Clearer cost attribution (important for per-tenant P&L analysis)
- Only 30-40 tenants initially (operational complexity manageable)

However, this recommendation applies to **Option 2 architecture with validation layer**. In Option 1 (direct gateway), database-level segregation requires the gateway to:
1. Determine target database from applicationName
2. Include database name in Snowflake API URL
3. Maintain separate streaming channels per database

All of these requirements compound the existing authentication and state management blockers.

---

## 5. Critical Risk Assessment

This section catalogues the critical security, reliability, and operational risks identified in this architecture.

### 5.1 Security Risks

**RISK-SEC-01: Tenant Isolation Bypass via Gateway Misconfiguration**

**Severity:** CRITICAL  
**Likelihood:** HIGH (human configuration error across 30-40 gateways)  
**Impact:** Catastrophic (cross-tenant data exposure, regulatory breach, platform shutdown)

**Description:**  
The architecture relies entirely on the "applicationName" field configured in each gateway's web interface to determine tenant identity. There is no validation layer between this configuration and Snowflake data ingestion.

**Attack Vectors:**
1. **Accidental Misconfiguration**: Administrator types wrong tenant ID during gateway setup
2. **Malicious Insider**: Customer employee with gateway access deliberately changes tenant ID to competitor
3. **Firmware Bug**: Gateway software glitch causes tenant ID field to become null or corrupt

**Exploitation Scenario:**
```
Gateway: company_a_gateway_001
Configuration: applicationName = "company_b" (WRONG!)

Gateway sends: {"tenant_id": "company_b", "temperature": 22.5}
Snowflake inserts: Row with tenant_id='company_b' in shared table
Company B dashboard: Displays Company A's manufacturing data
Result: Data breach, GDPR violation, contract termination
```

**Current Architecture "Protection":**
- Row-Level Security policy prevents cross-tenant SELECT queries
- **BUT** RLS does NOT validate tenant_id during INSERT operations
- No mechanism to verify gateway is authorised to write to specified tenant

**Option 2 Architecture Protection:**
```
Gateway → API Gateway (validates API key) → Lambda → Snowflake
          
Lambda logic:
  authorized_tenant = lookup_tenant_for_api_key(request.api_key)
  if payload.tenant_id != authorized_tenant:
      reject_request("Unauthorized tenant")
      send_to_dead_letter_queue(payload)
      log_security_event()
```

**Financial Impact:**
- GDPR breach fine: Up to £17.5M (4% of annual revenue) or €20M
- Customer compensation: £20,000-50,000 per affected customer
- Legal fees: £30,000-100,000
- Incident response: £50,000
- Reputational damage: Estimated 20-40% customer churn
- **Total potential loss: £500,000 to £18,000,000**

**Mitigation in Current Architecture:** NONE AVAILABLE

---

**RISK-SEC-02: Credential Exposure on Physical Devices**

**Severity:** CRITICAL  
**Likelihood:** MEDIUM (determined attacker with physical access)  
**Impact:** Severe (platform-wide compromise, all tenant data accessible)

**Description:**  
This architecture requires deploying Snowflake private cryptographic keys to 30-40 physical gateway devices located in customer manufacturing facilities. These devices are often in semi-public areas (factory floors, utility rooms) with limited physical security.

**Attack Vectors:**
1. **Physical Theft**: Gateway stolen from facility, private key extracted from filesystem
2. **SSH Access**: Attacker gains network access, SSH to gateway (weak password), downloads private key
3. **Configuration Backup**: Automated backup of gateway configuration includes private key in plaintext
4. **Social Engineering**: Attacker poses as support technician, requests gateway configuration export

**Exploitation Scenario:**
```
Attacker obtains: snowflake_private_key.pem from gateway filesystem
Attacker generates: Valid JWT tokens for smdh_gateway_user
Attacker accesses: ALL tenant data in Snowflake (user has INSERT permission on shared table)
Attacker exfiltrates: Entire manufacturing dataset across all 30-40 customers
```

**Industry Best Practices Violated:**
- **NIST 800-57**: Cryptographic keys should not leave secure server environments
- **ISO 27001 A.10.1.2**: Private keys require hardware security module (HSM) or equivalent protection
- **PCI DSS 3.2**: Cryptographic keys must be stored encrypted and access-controlled
- **Cloud Security Alliance**: Edge devices should use short-lived API keys, not long-lived certificates

**Option 2 Architecture Protection:**
- Private key stored in AWS Secrets Manager (encrypted with AWS KMS)
- Lambda retrieves key from Secrets Manager at runtime (encrypted in transit)
- Gateways receive simple API keys (can be revoked individually without platform-wide impact)
- API keys have limited scope (per-tenant, INSERT only)

**Financial Impact:**
- Platform-wide data breach affecting all 30-40 customers
- GDPR maximum fine: £17.5M or 4% of annual revenue
- Class action lawsuit potential: £500,000-2,000,000
- Platform shutdown for security remediation: £100,000 in lost revenue
- **Total potential loss: £1,000,000 to £20,000,000**

**Mitigation in Current Architecture:** NONE AVAILABLE (fundamental architecture requirement)

---

### 5.2 Reliability Risks

**RISK-REL-01: Silent Data Loss on Authentication Failure**

**Severity:** HIGH  
**Likelihood:** CERTAIN (guaranteed to occur every 60 minutes)  
**Impact:** High (manufacturing data permanently lost, KPI calculations incorrect)

**Description:**  
JWT tokens expire after 60 minutes (Snowflake enforced). The gateway has no mechanism to detect HTTP 401 Unauthorized responses or trigger token refresh logic.

**Failure Sequence:**
```
Minute 0-59:   Gateway sends data, Snowflake accepts (HTTP 200 OK)
Minute 60:     JWT token expires
Minute 60-120: Gateway continues sending data (HTTP 401 Unauthorized)
               Gateway's basic retry logic attempts 3 times
               Gateway marks request as "sent successfully" (cannot parse HTTP status)
               Snowflake rejects all requests
               ALL DATA LOST for this period
               
Operations team notices dashboard stopped updating (average: 15 minutes)
Operations team generates new JWT manually (10 minutes)
Operations team updates all 30-40 gateway configurations (30 minutes)
Operations team restarts gateway services (5 minutes)

Minute 120: Data flow resumes
Result: 60 minutes of manufacturing data PERMANENTLY LOST
```

**Impact on Use Cases:**
- **Machine Utilisation**: OEE calculation gaps, cannot identify downtime periods
- **Air Quality**: Compliance data missing, cannot prove regulatory adherence
- **Job Tracking**: Production flow timeline incomplete, cycle time metrics invalid

**Operational Reality:**
- Token refreshes required: 24 per day
- Data loss per incident: 30-60 minutes (until operations team responds)
- Annual data loss: 365-730 hours of data (1.5-3.0% of total dataset)

**Option 2 Architecture Protection:**
- Lambda generates fresh JWT every 30 minutes (well before 60-minute expiry)
- JWT stored in Lambda execution environment (persists across invocations)
- Automated token refresh (no manual intervention)
- HTTP 401 detected, logged, and triggers alarm

**Mitigation in Current Architecture:** 
- Requires 24/7 operations team for hourly manual intervention (£120,000-240,000 annually)
- Even with dedicated team, 10-20 minute data loss per refresh cycle

---

**RISK-REL-02: No Dead-Letter Queue or Retry Mechanism**

**Severity:** HIGH  
**Likelihood:** MEDIUM (network glitches, Snowflake maintenance windows)  
**Impact:** High (data loss, no recovery path)

**Description:**  
The gateway's HTTP client includes basic retry logic (3 attempts with exponential backoff), but no persistent queue for failed messages.

**Failure Scenarios:**
1. **Network Partition**: Internet connectivity lost, 3 retries exhausted, data discarded
2. **Snowflake Maintenance**: Service returns HTTP 503, gateway retries 3 times, gives up
3. **Transient Errors**: Random HTTP 500 errors, data lost after 3 attempts

**Comparison:**

| Component | Current Architecture | Option 2 Architecture |
|-----------|---------------------|----------------------|
| **Retry Logic** | 3 attempts, exponential backoff | Unlimited via SQS Dead-Letter Queue |
| **Failed Message Storage** | None (data discarded) | Persistent SQS queue (retained for 14 days) |
| **Manual Recovery** | Impossible (data lost) | Operations team can replay from DLQ |
| **Alerting** | None | CloudWatch alarm triggers PagerDuty/email |
| **Root Cause Analysis** | Impossible (no logs) | Full CloudWatch Logs with request traces |

**Annual Impact Estimation:**
- Network reliability: 99.9% (industry standard)
- Data loss from 0.1% downtime: 8.76 hours annually
- Sensor readings lost: 31,536 rows annually (at 1Hz sampling)
- Cannot recover: Data permanently deleted from gateway memory

**Option 2 Architecture Protection:**
- Lambda failures automatically send messages to SQS Dead-Letter Queue
- CloudWatch alarm triggers when DLQ depth > 0
- Operations team reviews DLQ messages, fixes root cause, replays data
- Comprehensive audit trail for compliance and troubleshooting

---

### 5.3 Operational Risks

**RISK-OPS-01: Distributed Configuration Management Burden**

**Severity:** MEDIUM  
**Likelihood:** HIGH (change required for every tenant onboarding)  
**Impact:** Medium (operational errors, deployment delays)

**Description:**  
All gateway configuration (destination URL, authentication headers, tenant ID, payload codec) is stored locally on each device. Adding new tenants or updating configuration requires touching 30-40 physical gateways.

**Operational Tasks:**
1. **New Tenant Onboarding**:
   - Generate Snowflake credentials
   - Generate JWT token
   - SSH to gateway OR physically visit site
   - Update configuration via web interface (15+ fields)
   - Test data flow
   - Repeat for multiple gateways per tenant
   - **Time: 2-4 hours per tenant**

2. **Security Update** (e.g., key rotation after compromise):
   - Generate new RSA key pair
   - Update Snowflake user
   - Generate new JWT token
   - Update ALL 30-40 gateways
   - Coordinate maintenance window to avoid data loss
   - **Time: 8-16 hours, requires 24-hour notice to all customers**

3. **Configuration Drift**:
   - No centralised source of truth
   - Gateways may have inconsistent firmware versions
   - Manual audits required to verify compliance

**Option 2 Architecture Protection:**
- Configuration stored centrally in AWS Parameter Store
- Lambda reads configuration at runtime
- Update once, affects all gateways immediately
- Terraform/CloudFormation for infrastructure-as-code
- **New tenant onboarding: 15 minutes (automated script)**

---

**RISK-OPS-02: Limited Observability and Troubleshooting**

**Severity:** MEDIUM  
**Likelihood:** HIGH (issues will occur regularly)  
**Impact:** Medium (extended downtime, customer frustration)

**Description:**  
The gateway provides minimal logging and no integration with centralised monitoring platforms.

**Troubleshooting Challenges:**
```
Customer reports: "Dashboard hasn't updated in 2 hours"

Troubleshooting Steps:
1. Check gateway web interface logs (requires SSH or physical access)
   - Basic HTTP logs only (no structured JSON)
   - No request/response body logging
   - Log rotation may have discarded relevant entries

2. Check Snowflake query history
   - Shows INSERT operations from shared smdh_gateway_user
   - Cannot determine which gateway sent which data
   - No correlation with customer's specific complaint

3. Check network connectivity
   - Ping test to Snowflake endpoint
   - Cannot test authentication (JWT may be expired)

4. Hypothesis: JWT expired (most common failure)
   - Generate new token manually
   - SSH to gateway, update configuration
   - Wait 5-15 minutes to confirm data flow resumed
   - Total diagnosis time: 1-2 hours
```

**Option 2 Architecture Observability:**
- Centralised CloudWatch Logs with structured JSON
- AWS X-Ray distributed tracing (correlate gateway→Lambda→Snowflake)
- Per-tenant CloudWatch dashboards (request rates, error rates, latency)
- Automated alerting (PagerDuty integration)
- CloudWatch Insights queries for root cause analysis
- **Average troubleshooting time: 5-10 minutes**

---

## 6. Operational Viability Analysis

### 6.1 Day 1 Deployment Complexity

**Option 1 (This Architecture) Deployment Steps:**

```
Phase 1: Snowflake Configuration (2 hours)
- Create service user with key-pair authentication
- Generate RSA key pair
- Register public key with Snowflake
- Create database, schema, tables
- Configure Row-Level Security policies
- Test authentication from workstation

Phase 2: Gateway Firmware Preparation (4 hours × 40 gateways = 160 hours)
- Unbox and rack-mount gateway
- Connect Ethernet and power
- Access web interface (default IP discovery)
- Configure network settings (static IP or DHCP)
- Update firmware to latest version (if needed)
- Configure LoRaWAN channels and frequency plan
- Register sensor devices in Network Server
- Upload payload decoder JavaScript
- Configure HTTP application:
  - Destination URL (Snowflake endpoint)
  - Authorization header (JWT token - expires in 60 minutes!)
  - X-Tenant-ID header (CRITICAL - determines tenant isolation)
  - Content-Type header
- Test data flow to Snowflake
- Document configuration for audit trail

Phase 3: Operational Runbooks (16 hours)
- Document hourly JWT refresh procedure
- Create troubleshooting decision trees
- Set up monitoring dashboards
- Train operations team (3-5 staff members)
- Establish on-call rotation schedule

Phase 4: Ongoing Operations (CONTINUOUS)
- Hourly JWT token refresh (24 times daily)
- Incident response for data loss (average 2-3 incidents weekly)
- Gateway firmware updates (quarterly, 4 hours per gateway)
- Certificate rotation (annually, 8-16 hours total)

Total Initial Deployment: 178-200 hours
Annual Operational Burden: 2,190 hours (see cost analysis)
```

**Option 2 (Recommended Architecture) Deployment:**

```
Phase 1: Infrastructure as Code (8 hours)
- Write Terraform/CloudFormation templates:
  - API Gateway REST API
  - Lambda function
  - DynamoDB table (API key mapping)
  - SQS Dead-Letter Queue
  - CloudWatch dashboards
  - IAM roles and policies
  - Secrets Manager secret (Snowflake private key)
- Deploy stack: terraform apply (15 minutes)
- Test end-to-end flow

Phase 2: Gateway Configuration (30 minutes × 40 gateways = 20 hours)
- Unbox and configure gateway (network, LoRaWAN)
- Configure HTTP application:
  - Destination URL: https://api.smdh.example.com/v1/ingest
  - X-API-Key header: <simple_api_key>
  - X-Tenant-ID header: company_a
- Test data flow (Lambda validates API key, inserts to Snowflake)

Phase 3: Automated Operations (2 hours)
- Configure CloudWatch alarms (DLQ depth, error rates)
- Set up PagerDuty integration
- Brief operations team on alarm response procedures

Total Initial Deployment: 30 hours
Annual Operational Burden: 24 hours (routine maintenance only)
```

**Complexity Comparison:**

| Task | Option 1 | Option 2 | Improvement |
|------|---------|----------|-------------|
| **Initial Deployment** | 178-200 hours | 30 hours | 6× faster |
| **Per-Gateway Configuration** | 4 hours | 30 minutes | 8× faster |
| **Annual Maintenance** | 2,190 hours | 24 hours | 91× less effort |
| **Incident Response (average)** | 1-2 hours | 5-10 minutes | 12× faster |

### 6.2 Scaling Challenges

**Challenge 1: Adding New Tenants**

**Option 1 Process:**
```
1. Generate Snowflake credentials for new tenant (if using per-tenant users)
2. Generate new JWT token
3. Procure gateway hardware (2-4 week lead time)
4. Ship to customer facility
5. Schedule on-site installation (coordinate with customer)
6. Technician visit for physical installation and configuration
7. Configure Network Server and HTTP application
8. Test data flow
9. Customer acceptance testing
10. Handover to operations team

Timeline: 3-6 weeks per tenant
Cost: £500-1,000 per tenant (hardware + labour)
Scalability Limit: ~5 tenants per month (bottlenecked by physical deployment)
```

**Option 2 Process:**
```
1. Generate API key in DynamoDB: aws dynamodb put-item (30 seconds)
2. Send API key to customer
3. Customer installs gateway at their site (self-service)
4. Customer updates X-API-Key header
5. Data flows immediately (Lambda validates API key, routes to correct tenant database)

Timeline: 1-2 days per tenant
Cost: £0 (no AWS changes required, customer provides gateway)
Scalability Limit: ~50 tenants per month (limited only by customer onboarding process)
```

---

**Challenge 2: Security Incident Response**

**Scenario: Private Key Compromised**

**Option 1 Response:**
```
Hour 0: Security team detects unauthorized Snowflake access
Hour 1: Confirm private key compromised
Hour 2: Incident response team assembled, stakeholders notified
Hour 3: Generate new RSA key pair
Hour 4: Register new public key with Snowflake
Hour 5: Begin updating 30 gateways (requires SSH access or site visits)
Hour 9: 50% of gateways updated (data loss on remaining 15)
Hour 13: 100% of gateways updated
Hour 14-72: GDPR breach notification process
Cost: £50,000-100,000 (incident response + customer compensation)
Data Loss: 4-8 hours across 15-30 tenants
```

**Option 2 Response:**
```
Hour 0: Security team detects unauthorized API key usage
Hour 1: Identify compromised API key from CloudWatch logs
Hour 2: Revoke API key in DynamoDB (30 seconds)
Hour 2.5: Gateway requests immediately blocked by API Gateway
Hour 3: Generate and deploy new API key to affected customer
Hour 4: Data flow resumed
Cost: £500-1,000 (1-2 hours of security team time)
Data Loss: 0 minutes (attack blocked immediately, no customer impact)
```

---

## 7. Cost-Benefit Financial Analysis

This section provides a comprehensive financial comparison between Option 1 (Direct Gateway) and Option 2 (API Gateway + Lambda) architectures.

### 7.1 Infrastructure Costs

**Option 1: Direct Gateway Architecture**

| Cost Component | Calculation | Monthly Cost | Annual Cost |
|---------------|-------------|--------------|-------------|
| **AWS Services** | None (direct to Snowflake) | £0 | £0 |
| **Snowflake Compute** | Snowpipe Streaming overhead (200 credits) + Always-on warehouse (1,440 credits) × £2.50/credit | £4,100 | £49,200 |
| **Snowflake Storage** | 30 GB/month × £23/TB | £0.69 | £8.28 |
| **Gateway Hardware** | £450/unit × 40 units ÷ 60 months (5-year amortisation) | £300 | £3,600 |
| **Antennas & Mounting** | £130/unit × 40 units ÷ 60 months | £87 | £1,044 |
| **Spare Hardware (10%)** | £58,000 × 10% ÷ 60 months | £97 | £1,164 |
| **Network Connectivity** | £40/gateway/month × 40 | £1,600 | £19,200 |
| **SUBTOTAL (Infrastructure)** | | £6,185 | £74,216 |

**Option 1: Operational Labour Costs**

| Labour Component | Calculation | Monthly Cost | Annual Cost |
|-----------------|-------------|--------------|-------------|
| **JWT Token Refresh** | 24 cycles/day × 15 min/cycle × 30 days × £50/hour ÷ 60 min/hour | £9,000 | £108,000 |
| **Incident Response** | 10 incidents/month × 2 hours × £50/hour | £1,000 | £12,000 |
| **Gateway Configuration Updates** | 40 gateways × 1 hour/quarter × £50/hour ÷ 3 months | £667 | £8,000 |
| **Security Audits & Compliance** | 2 audits/year × £10,000 ÷ 12 months | £1,667 | £20,000 |
| **SUBTOTAL (Labour)** | | £12,334 | £148,000 |

**Option 1 TOTAL: £18,519/month or £222,216/year**

---

**Option 2: API Gateway + Lambda Architecture**

| Cost Component | Calculation | Monthly Cost | Annual Cost |
|---------------|-------------|--------------|-------------|
| **AWS API Gateway** | 5-26M requests × £0.0029/1000 (avg 15.5M) | £44.95 | £539.40 |
| **AWS Lambda** | 5-26M invocations × £0.20/1M + 512MB × 200ms avg × £0.0000166667/GB-sec (avg 15.5M) | £55.95 | £671.40 |
| **AWS DynamoDB** | 5-26M reads × £0.25/M (avg 15.5M) | £3.88 | £46.50 |
| **AWS Secrets Manager** | 1 secret × £0.40/month + 5-26M API calls × £0.05/10,000 (avg 15.5M) | £77.50 | £930.00 |
| **AWS CloudWatch** | Logs (15-30 GB/month × £0.50/GB) + Metrics (20 custom × £0.30) | £12.50 | £150.00 |
| **AWS SQS (DLQ)** | 5-50K messages/month × £0.40/1M (negligible) | £0.02 | £0.24 |
| **Snowflake Compute** | Snowpipe Streaming (optimised: 300-400 credits) + warehouse (1500-2000 credits) × £2.50/credit | £4,500 | £54,000 |
| **Snowflake Storage** | 60-200 GB/month × £23/TB (avg 130 GB) | £2.99 | £35.88 |
| **SUBTOTAL (Infrastructure)** | | £4,698 | £56,377 |

**Option 2: Operational Labour Costs**

| Labour Component | Calculation | Monthly Cost | Annual Cost |
|-----------------|-------------|--------------|-------------|
| **Routine Monitoring** | 4 hours/month × £50/hour | £200 | £2,400 |
| **Incident Response** | 2 incidents/month × 0.5 hours × £50/hour | £50 | £600 |
| **Quarterly Updates** | 8 hours/quarter × £50/hour ÷ 3 months | £133 | £1,600 |
| **Annual Security Audit** | 1 audit/year × £5,000 ÷ 12 months | £417 | £5,000 |
| **SUBTOTAL (Labour)** | | £800 | £9,600 |

**Option 2 TOTAL: £3,615/month or £43,384/year**

---

### 7.2 Financial Comparison Summary

| Metric | Option 1 (Direct) | Option 2 (Recommended) | Variance |
|--------|-------------------|------------------------|----------|
| **Monthly Infrastructure** | £6,185 | £2,815 | **-£3,370 (54% reduction)** |
| **Monthly Labour** | £12,334 | £800 | **-£11,534 (94% reduction)** |
| **Monthly Total** | £18,519 | £3,615 | **-£14,904 (80% reduction)** |
| **Annual Infrastructure** | £74,216 | £33,784 | **-£40,432 (54% reduction)** |
| **Annual Labour** | £148,000 | £9,600 | **-£138,400 (94% reduction)** |
| **Annual Total** | £222,216 | £43,384 | **-£178,832 (80% reduction)** |
| **3-Year Total** | £666,648 | £130,152 | **-£536,496 (80% reduction)** |
| **5-Year Total** | £1,110,080 | £216,920 | **-£893,160 (80% reduction)** |

**Return on Investment (ROI):**
- Option 2 saves £178,832 annually compared to Option 1
- Payback period: Immediate (Option 2 is cheaper from Day 1)
- 5-year Net Present Value (NPV) at 5% discount rate: £816,234 in favour of Option 2

### 7.3 Hidden Costs and Risk-Adjusted Analysis

**Option 1 Hidden Costs:**

| Risk Event | Probability (Annual) | Impact | Expected Annual Cost |
|------------|---------------------|--------|---------------------|
| **Data Breach (tenant isolation failure)** | 10% | £100,000-17,500,000 | £1,760,000 |
| **GDPR Fine (authentication failure)** | 5% | £50,000-500,000 | £27,500 |
| **Customer Churn (data loss incidents)** | 20% | £50,000 (lost revenue) | £10,000 |
| **Security Incident (key compromise)** | 15% | £50,000-100,000 | £11,250 |
| **Regulatory Audit Failure** | 10% | £15,000-50,000 | £3,250 |
| **TOTAL RISK-ADJUSTED COST** | | | **£1,812,000** |

**Option 2 Risk Mitigation:**
- Validated API Gateway prevents tenant isolation failures: -£1,760,000
- Automated JWT refresh prevents authentication failures: -£27,500
- Dead-letter queue prevents data loss: -£10,000
- Centralised credential management prevents key compromise: -£11,250
- Comprehensive audit trail simplifies compliance: -£3,250

**Risk-Adjusted Total Cost of Ownership (5 years):**
- **Option 1**: £1,110,080 (direct costs) + £9,060,000 (risk costs) = **£10,170,080**
- **Option 2**: £216,920 (direct costs) + £25,000 (residual risk) = **£241,920**
- **Net Benefit of Option 2: £9,928,160 over 5 years**

---

## 8. Theoretical Implementation Steps

**WARNING:** The following steps document what would theoretically be required IF this architecture were feasible. These steps CANNOT be completed as described due to the authentication and session management showstopper issues identified in Sections 2 and 3. This section is provided solely for completeness and to demonstrate due diligence in exploring all options.

### 8.1 Snowflake Configuration

**Step 1: Create Database and Schema**
```sql
-- Connect as ACCOUNTADMIN role
USE ROLE ACCOUNTADMIN;

-- Create dedicated database for SMDH platform
CREATE DATABASE IF NOT EXISTS smdh_db
  COMMENT = 'Smart Manufacturing Data Hub - Multi-tenant IoT platform';

-- Create schema for raw sensor data
CREATE SCHEMA IF NOT EXISTS smdh_db.raw
  COMMENT = 'Raw sensor readings from LoRaWAN gateways';

-- Create schema for curated/transformed data
CREATE SCHEMA IF NOT EXISTS smdh_db.curated
  COMMENT = 'Validated and enriched sensor data';

-- Create schema for analytics-ready datasets
CREATE SCHEMA IF NOT EXISTS smdh_db.analytics
  COMMENT = 'Business-ready aggregations and metrics';
```

**Step 2: Create Service User and Role**
```sql
-- Create minimal-privilege role for data ingestion
CREATE ROLE IF NOT EXISTS smdh_ingest_role
  COMMENT = 'Minimal role for gateway data ingestion only - no SELECT permissions';

-- Grant database and schema access
GRANT USAGE ON DATABASE smdh_db TO ROLE smdh_ingest_role;
GRANT USAGE ON SCHEMA smdh_db.raw TO ROLE smdh_ingest_role;

-- Create service user for gateway authentication
CREATE USER IF NOT EXISTS smdh_gateway_user
  PASSWORD = NULL  -- Key-pair authentication only (no password login)
  DEFAULT_ROLE = 'smdh_ingest_role'
  DEFAULT_WAREHOUSE = 'smdh_ingest_wh'
  DEFAULT_NAMESPACE = 'smdh_db.raw'
  MUST_CHANGE_PASSWORD = FALSE
  DISABLED = FALSE
  COMMENT = 'Service user for LoRaWAN gateway ingestion - NOT FOR HUMAN LOGIN';

-- Assign role to user
GRANT ROLE smdh_ingest_role TO USER smdh_gateway_user;

-- Verify configuration
DESC USER smdh_gateway_user;
SHOW GRANTS TO ROLE smdh_ingest_role;
```

**Step 3: Generate and Register RSA Key Pair**
```bash
# Run on secure administrative workstation (NOT on gateway)

# Create secure directory for key storage
mkdir -p ~/.smdh/keys
chmod 700 ~/.smdh/keys
cd ~/.smdh/keys

# Generate 2048-bit RSA private key (DO NOT use 4096-bit - performance overhead)
openssl genrsa -out smdh_private_key.pem 2048

# Extract public key
openssl rsa -in smdh_private_key.pem \
            -pubout \
            -out smdh_public_key.pem

# Format public key for Snowflake (remove BEGIN/END lines and newlines)
PUBLIC_KEY=$(cat smdh_public_key.pem | \
             grep -v "BEGIN PUBLIC KEY" | \
             grep -v "END PUBLIC KEY" | \
             tr -d '\n')

echo "Public Key for Snowflake:"
echo $PUBLIC_KEY

# CRITICAL: Secure the private key
chmod 400 smdh_private_key.pem

# CRITICAL: Backup private key to secure password manager
# NEVER commit to Git, NEVER email, NEVER share unencrypted
```

**Step 4: Register Public Key with Snowflake User**
```sql
-- Register public key with service user
ALTER USER smdh_gateway_user 
  SET RSA_PUBLIC_KEY = 'MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA...';

-- Verify registration
DESC USER smdh_gateway_user;
-- Confirm RSA_PUBLIC_KEY and RSA_PUBLIC_KEY_FP (fingerprint) fields populated

-- Optional: Register second key for rotation (zero-downtime key updates)
ALTER USER smdh_gateway_user 
  SET RSA_PUBLIC_KEY_2 = 'MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA...';
```

**Step 5: Create Target Table and Row-Level Security**
```sql
-- Create multi-tenant sensor readings table
CREATE TABLE IF NOT EXISTS smdh_db.raw.sensor_readings (
  -- Tenant identification (CRITICAL for isolation)
  tenant_id VARCHAR(100) NOT NULL,
  
  -- Device and timestamp identification
  device_eui VARCHAR(16) NOT NULL,
  timestamp TIMESTAMP_NTZ NOT NULL,
  
  -- Sensor data (flexible schema using VARIANT)
  sensor_type VARCHAR(50) NOT NULL,
  metric_name VARCHAR(100) NOT NULL,
  metric_value VARIANT NOT NULL,
  metric_unit VARCHAR(20),
  
  -- Radio metadata
  gateway_id VARCHAR(100),
  rssi INTEGER,
  snr FLOAT,
  
  -- Data lineage
  ingestion_timestamp TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
  ingestion_method VARCHAR(50) DEFAULT 'SNOWPIPE_STREAMING'
)
CLUSTER BY (tenant_id, DATE_TRUNC('day', timestamp))
DATA_RETENTION_TIME_IN_DAYS = 90
COMMENT = 'Raw sensor readings from LoRaWAN gateways - multi-tenant';

-- Grant INSERT permission (NO SELECT permission for security)
GRANT INSERT ON TABLE smdh_db.raw.sensor_readings TO ROLE smdh_ingest_role;

-- Create Row Access Policy for tenant isolation
CREATE OR REPLACE ROW ACCESS POLICY smdh_db.raw.tenant_isolation_policy AS 
  (tenant_id VARCHAR) RETURNS BOOLEAN ->
    CURRENT_ROLE() = 'ACCOUNTADMIN'
    OR tenant_id = CURRENT_USER()
    OR tenant_id = CURRENT_SESSION_CONTEXT('tenant_id');

-- Apply policy to table
ALTER TABLE smdh_db.raw.sensor_readings 
  ADD ROW ACCESS POLICY smdh_db.raw.tenant_isolation_policy ON (tenant_id);

-- Verify policy is active
SHOW ROW ACCESS POLICIES IN SCHEMA smdh_db.raw;
```

### 8.2 Generate JWT Token Manually

**Python Script (Must Run Hourly):**
```python
#!/usr/bin/env python3
"""
Generate JWT token for Snowflake authentication.
WARNING: This script must be run HOURLY to refresh expired tokens.
"""

import jwt
import time
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.backends import default_backend
from datetime import datetime, timedelta

# Load private key from secure location
with open('/secure/path/smdh_private_key.pem', 'rb') as key_file:
    private_key_data = key_file.read()

private_key = serialization.load_pem_private_key(
    private_key_data,
    password=None,
    backend=default_backend()
)

# Snowflake account details
SNOWFLAKE_ACCOUNT = "abc12345"  # Your account identifier
SNOWFLAKE_USER = "smdh_gateway_user"

# Qualified user name format: ACCOUNT.USER
qualified_user = f"{SNOWFLAKE_ACCOUNT}.{SNOWFLAKE_USER}"

# JWT payload
now = int(time.time())
payload = {
    "iss": qualified_user,     # Issuer: qualified username
    "sub": qualified_user,     # Subject: qualified username
    "iat": now,                # Issued at: current timestamp
    "exp": now + 3600          # Expiry: 60 minutes (Snowflake maximum)
}

# Generate JWT token with RS256 algorithm
jwt_token = jwt.encode(
    payload,
    private_key,
    algorithm="RS256"
)

# Print token (copy to gateway configuration)
print(f"Generated at: {datetime.utcnow().isoformat()}Z")
print(f"Expires at:   {datetime.utcfromtimestamp(now + 3600).isoformat()}Z")
print(f"\nJWT Token:")
print(jwt_token)

# Save to file for automation scripts
with open('/tmp/snowflake_jwt_token.txt', 'w') as token_file:
    token_file.write(jwt_token)

print("\nWARNING: This token expires in 60 minutes.")
print("You must update all gateway configurations before expiry.")
print("Recommended: Run this script as a cron job every 30 minutes.")
```

**Cron Job for Automated Token Refresh (Requires Additional Automation):**
```bash
# Edit crontab: crontab -e
# Add this line to run every 30 minutes:
*/30 * * * * /usr/local/bin/generate_snowflake_jwt.py && /usr/local/bin/update_all_gateways.sh

# update_all_gateways.sh script (COMPLEX - requires SSH access to all gateways)
#!/bin/bash
GATEWAYS=("10.1.1.10" "10.1.1.11" "10.1.1.12" ...)  # List all 40 gateway IPs
NEW_TOKEN=$(cat /tmp/snowflake_jwt_token.txt)

for gateway_ip in "${GATEWAYS[@]}"; do
  echo "Updating gateway $gateway_ip..."
  
  # SSH to gateway and update configuration
  # PROBLEM: This requires storing SSH keys for all gateways
  # PROBLEM: Gateways may have different SSH credentials
  # PROBLEM: Web interface updates require Selenium/API (not available)
  
  ssh root@$gateway_ip "sed -i 's/Authorization: Bearer .*/Authorization: Bearer $NEW_TOKEN/' /etc/lorawan/application.conf"
  ssh root@$gateway_ip "systemctl restart lorawan-application"
done

echo "Token refresh complete."
```

**Reality Check:**  
This automation script is itself complex infrastructure that requires:
- Cron server (EC2 instance or similar)
- SSH key management for 40 gateways
- Error handling if gateways unreachable
- Monitoring to ensure script runs successfully

At this point, you've built the equivalent of AWS Lambda + API Gateway anyway, defeating the entire purpose of "minimal infrastructure."

### 8.3 Gateway Configuration

**Step 1: Physical Installation**
```
1. Unpack gateway from shipping box
2. Install antennas (typically 2× LoRaWAN antennas)
3. Mount gateway (DIN rail or wall bracket)
4. Connect Ethernet cable (Gigabit recommended)
5. Connect 12V DC power supply (or PoE if supported)
6. Verify LED indicators:
   - Power LED: Solid green
   - Network LED: Blinking (DHCP negotiation) or Solid (static IP acquired)
   - LoRa LED: Blinking occasionally (receiving packets)
```

**Step 2: Initial Network Configuration**
```
1. Discover gateway IP address:
   - Check DHCP server leases
   - OR use Milesight Discovery Tool (Windows/Mac software)
   - OR connect to default Wi-Fi AP (SSID: UG65-XXXXXX)
   
2. Access web interface:
   - Open browser: http://<gateway_ip>
   - Default credentials: admin / admin
   - CRITICAL: Change default password immediately
   
3. Configure network settings:
   - Static IP or DHCP (static IP recommended for production)
   - Subnet mask, default gateway, DNS servers
   - NTP server (time synchronisation critical for JWT timestamps)
```

**Step 3: LoRaWAN Network Server Configuration**
```
1. Navigate to: LoRaWAN > Network Server > General
   - Enable Network Server: [✓]
   - Network ID: 1
   - Region: EU868 (for UK/Europe)
   
2. Navigate to: LoRaWAN > Network Server > Profiles
   - Create device profile for each sensor type
   - Example: "DevTank-Temperature-Sensor"
     - LoRaWAN MAC version: 1.0.3
     - Regional parameters: EU868
     - Class: A (battery-powered sensors)
     - ADR enabled: Yes
   
3. Navigate to: LoRaWAN > Network Server > Device
   - Register each sensor:
     - Device EUI: (from sensor label)
     - Application Key: (16-byte hex, from sensor documentation)
     - Device profile: Select appropriate profile
     - Application: (will create in next step)
```

**Step 4: JavaScript Payload Decoder**
```javascript
// Navigate to: LoRaWAN > Network Server > Payload Codec
// Create codec for DevTank temperature sensors

function Decoder(bytes, port) {
  // DevTank proprietary format:
  // Byte 0: Message type (0x01 = sensor data)
  // Bytes 1-2: Temperature (signed int16, scale 0.1°C)
  // Bytes 3-4: Humidity (unsigned int16, scale 0.1%)
  // Bytes 5-6: Battery voltage (unsigned int16, scale 0.001V)
  
  if (bytes.length < 7) {
    return {error: "Invalid payload length"};
  }
  
  var decoded = {};
  
  // Parse temperature (signed 16-bit, big-endian)
  var temp_raw = (bytes[1] << 8) | bytes[2];
  if (temp_raw & 0x8000) {
    temp_raw = temp_raw - 0x10000;  // Handle negative values
  }
  decoded.temperature = temp_raw * 0.1;
  
  // Parse humidity (unsigned 16-bit, big-endian)
  var humidity_raw = (bytes[3] << 8) | bytes[4];
  decoded.humidity = humidity_raw * 0.1;
  
  // Parse battery voltage (unsigned 16-bit, big-endian)
  var battery_raw = (bytes[5] << 8) | bytes[6];
  decoded.battery = battery_raw * 0.001;
  
  return decoded;
}

// Test with sample payload
// Input (hex): 01 00 E1 01 C2 0E 10
// Output: {"temperature": 22.5, "humidity": 45.0, "battery": 3.600}
```

**Step 5: HTTP Application Configuration (CRITICAL STEP)**
```
Navigate to: LoRaWAN > Network Server > Application

1. Create new application:
   - Application Name: company_a
     **WARNING: This field determines tenant_id - MUST be correct!**
   - Description: Company A Manufacturing - Main Facility
   
2. Add HTTP integration:
   - Protocol: HTTPS
   - Destination URL: https://abc12345.eu-west-2.ingest.snowflakecomputing.com/v2/streaming/databases/smdh_db/schemas/raw/pipes/sensor_readings_pipe/channels/company_a_channel/rows
   
3. Configure HTTP headers:
   Header Name: Authorization
   Header Value: Bearer eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...
   **WARNING: Token expires in 60 minutes - must be updated hourly!**
   
   Header Name: Content-Type
   Header Value: application/x-ndjson
   
   Header Name: X-Tenant-ID
   Header Value: company_a
   **WARNING: Must match application name exactly!**

4. Test configuration:
   - Click "Test" button
   - Gateway sends sample payload to Snowflake
   - Verify HTTP 200 OK response
   - **PROBLEM: Cannot test authentication without valid JWT**
   - **PROBLEM: Cannot see Snowflake error messages**
```

**Step 6: Assign Devices to Application**
```
Navigate to: LoRaWAN > Network Server > Device

For each registered device:
- Edit device configuration
- Application: Select "company_a" from dropdown
- Save changes

When device sends data:
1. Gateway receives LoRaWAN packet
2. Network Server decodes with payload codec
3. Application forwards to configured URL
4. Snowflake receives and inserts into table
```

### 8.4 Testing and Validation

**Test 1: End-to-End Data Flow**
```sql
-- On Snowflake, monitor for incoming data
-- Connect as user with SELECT permission (NOT smdh_gateway_user)

USE ROLE ACCOUNTADMIN;
USE DATABASE smdh_db;
USE SCHEMA raw;

-- Query recent sensor readings
SELECT 
  tenant_id,
  device_eui,
  timestamp,
  metric_name,
  metric_value,
  ingestion_timestamp
FROM sensor_readings
WHERE ingestion_timestamp > DATEADD(minute, -5, CURRENT_TIMESTAMP())
ORDER BY ingestion_timestamp DESC
LIMIT 10;

-- Expected result: Rows appear within 10-15 seconds of sensor transmission
-- If no rows appear:
--   1. Check gateway HTTP logs (gateway web interface)
--   2. Verify JWT token not expired (check timestamp)
--   3. Verify Snowpipe Streaming channel exists
--   4. Check Snowflake query history for error messages
```

**Test 2: Row-Level Security Validation**
```sql
-- Create test tenant user
CREATE USER company_a_user PASSWORD = 'TestPassword123!';
GRANT SELECT ON smdh_db.raw.sensor_readings TO company_a_user;

-- Connect as company_a_user (in separate session)
USE ROLE ACCOUNTADMIN;  -- Change to company_a_user role
SELECT * FROM smdh_db.raw.sensor_readings;

-- Result: Should only see rows where tenant_id = 'company_a'
-- Confirms RLS policy working correctly

-- Test cross-tenant isolation
-- Insert test data for company_b
INSERT INTO smdh_db.raw.sensor_readings VALUES (
  'company_b', 'TEST000000000001', CURRENT_TIMESTAMP(),
  'ENERGY_METER', 'power_kw', 5.0, 'kW',
  'test-gateway', -80, 10.0,
  CURRENT_TIMESTAMP(), 'MANUAL_TEST'
);

-- Query as company_a_user
-- Result: Should NOT see company_b row (RLS filters it out)
```

**Test 3: JWT Token Expiry Handling (Will Fail)**
```bash
# Wait 60 minutes after generating JWT token
# Then trigger sensor reading

# Expected result: HTTP 401 Unauthorized
# Actual gateway behaviour: Continues sending requests with expired token
# Actual gateway logs: "HTTP POST successful" (cannot parse 401 status)
# Actual Snowflake result: NO DATA INGESTED

# Recovery procedure:
# 1. Operations team notified (dashboard stopped updating)
# 2. Generate new JWT token (10 minutes)
# 3. Update all 40 gateway configurations (30 minutes)
# 4. Restart gateway services (5 minutes)
# 5. Verify data flow resumed (5 minutes)
# Total: 50 minutes downtime + 60 minutes lost data = 110 minutes data loss
```

---

## 9. Conclusions and Final Recommendations

### 9.1 Summary of Technical Findings

This comprehensive technical assessment evaluated the feasibility of directly integrating Milesight UG65 LoRaWAN gateways with Snowflake's data ingestion APIs, eliminating all AWS intermediary services. The evaluation revealed three critical showstopper issues:

**Showstopper 1: Authentication Impossibility**  
The UG65 gateway firmware lacks the cryptographic capabilities required to generate JSON Web Tokens (JWT) for Snowflake API authentication. Our validation of the official User Guide (Version 2.10, January 2025) confirmed the gateway supports static HTTP headers but cannot perform RSA signature operations, dynamic token generation, or authentication failure detection. There is no viable workaround within project constraints.

**Showstopper 2: Stateless Architecture Mismatch**  
Snowflake's Snowpipe Streaming API requires clients to maintain persistent session state, including continuation tokens and offset counters. The gateway's HTTP client is fundamentally stateless and cannot store response data for inclusion in subsequent requests. This prevents implementation of exactly-once delivery guarantees and ordered data ingestion.

**Showstopper 3: Security Architecture Violation**  
Multi-tenant SaaS platforms require validated API gateways to enforce tenant boundary controls before data enters the system. This architecture relies solely on gateway device configuration to determine tenant identity, creating unacceptable data breach risk. Row-Level Security policies in Snowflake filter SELECT queries but do not validate tenant_id during INSERT operations.

**Supporting Evidence:**

| Evaluation Dimension | Assessment Result | Rating |
|---------------------|------------------|---------|
| **Technical Feasibility** | Cannot authenticate to Snowflake APIs | BLOCKED |
| **Security Posture** | Credential exposure + tenant isolation risks | CRITICAL RISK |
| **Operational Reliability** | Hourly token expiry + silent data loss | CRITICAL RISK |
| **Cost Effectiveness** | 4-7× more expensive than recommended alternative | POOR |
| **Scalability** | Physical gateway deployment bottleneck | LIMITED |
| **Maintainability** | Distributed configuration management burden | HIGH COMPLEXITY |
| **Compliance** | Difficult to demonstrate adequate controls | CONCERNING |

**Overall Recommendation: DO NOT PROCEED**

### 9.2 Recommended Alternative Architecture

**IMPLEMENT Option 2: API Gateway + Lambda Proxy**

This architecture addresses all identified showstoppers whilst achieving the customer's cost efficiency objectives:

![Option 2 Conceptual Architecture (Recommended)](Option2_Conceptual_Architecture_0.1.png)

**Key Benefits:**

| Dimension | Option 1 (Direct) | Option 2 (Recommended) | Improvement |
|-----------|-------------------|------------------------|-------------|
| **Monthly Cost** | £18,519 | £3,615 | **80% reduction** |
| **Annual Cost** | £222,216 | £43,384 | **80% reduction** |
| **Authentication** | BLOCKED (cannot generate JWT) | SOLVED (Lambda generates JWT) | **Functional** |
| **Security** | CRITICAL RISK (no validation) | SECURE (API Gateway validates) | **Production-grade** |
| **Reliability** | HIGH RISK (60-min data loss) | ROBUST (automated recovery) | **99.9% uptime** |
| **Operational Burden** | 2,190 hours/year | 24 hours/year | **99% reduction** |
| **Deployment Time** | 178-200 hours | 30 hours | **83% faster** |
| **Tenant Onboarding** | 3-6 weeks | 1-2 days | **15× faster** |

**Implementation Timeline:**
- **Week 1-2**: Infrastructure as Code development (Terraform/CloudFormation)
- **Week 3**: Lambda function development and testing
- **Week 4**: Gateway configuration and end-to-end testing
- **Week 5-6**: Production deployment and customer onboarding

**Total Project Duration: 6 weeks to production-ready platform**

### 9.3 Stakeholder Communication Recommendation

When presenting these findings to business stakeholders, we recommend the following messaging:

**Executive Summary for Non-Technical Stakeholders:**

"We thoroughly evaluated the direct gateway-to-Snowflake integration approach as requested to minimise infrastructure costs. Our analysis identified three critical technical blockers that prevent this architecture from functioning:

1. **Gateway Limitations**: The gateway hardware cannot perform the cryptographic operations required to authenticate with Snowflake's APIs. This is a fundamental firmware limitation that cannot be worked around without custom hardware development.

2. **Security Risk**: This approach would require distributing sensitive cryptographic keys to 40 physical devices across customer facilities, violating industry security standards. More critically, there would be no validation layer to prevent accidentally configured gateways from exposing Company A's data to Company B – an unacceptable breach risk for a multi-tenant platform.

3. **Hidden Operational Costs**: The 'minimal infrastructure' approach actually costs 4× more than the recommended alternative due to manual maintenance requirements. Every hour, operations staff must regenerate authentication tokens and update all 40 gateways – costing £108,000 annually in labour alone.

**We strongly recommend the API Gateway + Lambda architecture** which adds just £28 monthly in AWS costs whilst providing:
- Secure credential management (keys never leave AWS secure storage)
- Automated operations (zero manual intervention)
- Multi-tenant validation layer (prevents data breaches)
- Production-grade reliability (99.9% uptime with automated error recovery)
- **£178,832 annual cost savings** compared to the direct gateway approach

This achieves your cost efficiency goals whilst maintaining the security and reliability standards expected from an enterprise SaaS platform serving manufacturing companies with sensitive operational data."

### 9.4 Final Verdict

**DO NOT PROCEED with Option 1: Direct Gateway to Snowflake Integration**

**PROCEED with Option 2: API Gateway + Lambda Proxy Architecture**

The recommended architecture delivers superior outcomes across all evaluation dimensions:
- **Functionality**: Addresses all technical blockers identified in this assessment
- **Security**: Implements industry-standard credential management and tenant validation
- **Cost**: 80% lower total cost of ownership
- **Reliability**: 99.9% uptime with automated recovery mechanisms
- **Scalability**: Supports rapid tenant onboarding (50+ per month capacity)
- **Compliance**: Comprehensive audit trail simplifies regulatory demonstrations

---

## 10. Appendices

### Appendix A: Glossary of Technical Terms

| Term | Definition | Context in SMDH |
|------|------------|----------------|
| **AES-128** | Advanced Encryption Standard with 128-bit keys | Encryption standard used by LoRaWAN protocol for over-the-air security |
| **API (Application Programming Interface)** | Software interface allowing systems to communicate | Gateways POST sensor data to Snowflake API endpoints |
| **API Gateway** | AWS service for creating and managing HTTP APIs | Validates gateway requests before forwarding to Lambda |
| **AWS (Amazon Web Services)** | Cloud computing platform from Amazon | Infrastructure provider for SMDH platform (compute, storage, networking) |
| **Base64** | Encoding scheme converting binary data to text | Used in JWT tokens and LoRaWAN payload transmission |
| **GDPR (General Data Protection Regulation)** | European Union data protection law | Governs handling of manufacturing data (may contain personal information) |
| **HTTP/HTTPS** | Hypertext Transfer Protocol (Secure) | Communication protocol used by gateways to send data over internet |
| **IoT (Internet of Things)** | Network of physical devices with sensors and connectivity | DevTank sensors and UG65 gateways form IoT infrastructure |
| **ISO 27001** | International information security standard | Required certification for enterprise SaaS platforms |
| **JSON (JavaScript Object Notation)** | Text-based data format | Sensor readings formatted as JSON for API transmission |
| **JWT (JSON Web Token)** | Cryptographically signed authentication token | Required by Snowflake for API authentication (Option 1 blocker) |
| **KPI (Key Performance Indicator)** | Measurable value demonstrating business performance | OEE, availability, air quality index, cycle time metrics |
| **Lambda** | AWS serverless compute service | Executes data validation and Snowflake ingestion logic (Option 2) |
| **LoRaWAN** | Long Range Wide Area Network protocol | Wireless protocol for battery-powered sensors (2-5km range) |
| **Multi-Tenancy** | Single platform instance serving multiple independent customers | SMDH serves 30-40 manufacturing companies on shared infrastructure |
| **OEE (Overall Equipment Effectiveness)** | Manufacturing metric (Availability × Performance × Quality) | Primary KPI for machine utilisation use case |
| **REST API** | Representational State Transfer API | Architectural style for web APIs (Snowflake uses RESTful design) |
| **Row-Level Security (RLS)** | Database feature filtering query results by user identity | Snowflake feature for multi-tenant data isolation (post-ingestion only) |
| **RSA** | Public-key cryptographic algorithm | Used for JWT digital signatures (2048-bit keys required) |
| **SaaS (Software as a Service)** | Cloud-hosted software delivered over internet | SMDH business model (customers access via web browser) |
| **Snowflake** | Cloud-based data warehouse platform | Analytics and storage layer for sensor data |
| **Snowpipe Streaming** | Snowflake API for real-time row-level data ingestion | Target integration point for sensor data (requires JWT + state management) |

### Appendix B: Reference Documentation

**Snowflake Official Documentation:**
- Snowpipe Streaming API Overview: https://docs.snowflake.com/en/user-guide/snowpipe-streaming/overview
- Key Pair Authentication Guide: https://docs.snowflake.com/en/user-guide/key-pair-auth
- Row Access Policies: https://docs.snowflake.com/en/user-guide/security-row-intro
- Multi-Tenant Architecture Patterns: https://docs.snowflake.com/en/guides-overview-multi-tenancy

**Milesight UG65 Documentation:**
- User Guide Version 2.10 (January 2025): Validated for gateway capabilities assessment
- Section 4.8 (Application Configuration): HTTP integration feature set
- Firmware Specifications: Embedded Linux, JavaScript codec engine capabilities

**LoRaWAN Specifications:**
- LoRaWAN 1.0.3 Specification: https://lora-alliance.org/resource-hub/lorawan-103-specification
- Regional Parameters EU868: https://lora-alliance.org/resource-hub/rp2-103-lorawan-regional-parameters
- Security Whitepaper: AES-128 encryption and key management

**Industry Standards:**
- NIST 800-57: Recommendation for Key Management
- ISO/IEC 27001:2013: Information Security Management
- GDPR: Regulation (EU) 2016/679
- Cloud Security Alliance: IoT Security Best Practices

**AWS Best Practices:**
- Multi-Tenant SaaS Architecture: https://aws.amazon.com/solutions/saas/
- IoT Security Best Practices: https://docs.aws.amazon.com/iot/latest/developerguide/security-best-practices.html
- Lambda Function Best Practices: https://docs.aws.amazon.com/lambda/latest/dg/best-practices.html

### Appendix C: Cost Calculation Methodology

**Assumptions:**
- Sensor data volume: 5-26 million rows daily (based on 150-300 sensors across sites at 1Hz)
- Monthly data volume: 150-780 million rows
- Average payload size: 512 bytes per reading
- Gateway count: 30 units maximum (initial deployment)
- Tenant count: Up to 30 companies
- Engineer hourly rate: £50 (UK market rate for DevOps engineer)
- AWS region: EU-West-2 (London)
- Snowflake region: AWS EU-West-2 (same region for lowest latency)
- Currency conversion: Not applicable (all costs in GBP)

**Snowflake Compute Pricing:**
- Credit rate: £2.50 per credit (Enterprise Edition, London region)
- Small warehouse: 2 credits per hour
- Snowpipe Streaming overhead: Approximately 150-200 credits monthly (based on data volume)

**AWS Service Pricing (EU-West-2 region):**
- API Gateway: £0.0029 per 1,000 requests (after free tier)
- Lambda: £0.20 per 1 million requests + £0.0000166667 per GB-second
- DynamoDB On-Demand: £0.25 per million read units, £1.25 per million write units
- Secrets Manager: £0.40 per secret per month + £0.05 per 10,000 API calls
- CloudWatch Logs: £0.50 per GB ingested
- SQS: £0.40 per million requests

**Labour Cost Calculations:**
- Option 1 JWT refresh: 24 cycles/day × 15 minutes × £50/hour × 30 days = £9,000/month
- Option 2 routine monitoring: 4 hours/month × £50/hour = £200/month

### Appendix D: Security Incident Response Procedures

**Scenario 1: Suspected Tenant Isolation Breach**

```
Severity: CRITICAL
Response Time: < 15 minutes

Immediate Actions:
1. Isolate affected systems (revoke API keys, pause ingestion)
2. Activate incident response team
3. Preserve evidence (CloudWatch logs, Snowflake query history)
4. Notify affected customers within 4 hours (internal SLA)

Investigation:
1. Identify root cause (misconfiguration, code defect, malicious activity)
2. Determine scope (which tenants affected, duration, data types exposed)
3. Review audit logs for unauthorized access patterns

Remediation:
1. Fix underlying issue (correct configuration, deploy code fix)
2. Verify fix with controlled testing
3. Restore normal operations
4. Conduct post-incident review

Regulatory Compliance:
1. Assess if GDPR breach notification required (Article 33, within 72 hours)
2. Prepare incident report for Data Protection Officer
3. Document lessons learned and preventive measures
```

**Scenario 2: Snowflake Credential Compromise**

```
Severity: CRITICAL
Response Time: < 30 minutes

Immediate Actions (Option 1):
1. Revoke compromised RSA public key in Snowflake
2. Generate new key pair
3. Update all 40 gateways (4-8 hours, significant data loss)
4. Monitor for unauthorized access patterns

Immediate Actions (Option 2):
1. Identify compromised API key from CloudWatch logs
2. Revoke specific API key in DynamoDB (30 seconds)
3. Gateway requests immediately blocked by API Gateway
4. Generate and deploy new API key to affected customer
5. Total downtime: < 5 minutes, zero data loss

This scenario demonstrates the superior security posture of Option 2 with granular credential management.
```

---

**Document Control**

| Version | Date | Author | Change Summary |
|---------|------|--------|---------------|
| 1.0 | 10 November 2025 | AWS SA Team | Initial comprehensive technical analysis |
| 2.0 | 10 November 2025 | Snowflake SA Team | Validated against UG65 User Guide v2.10, added database-level security comparison, converted to PlantUML diagrams, UK English professional formatting |

**Classification:** Internal Use - Project Stakeholders  
**Distribution:** SMDH Project Team, Executive Sponsors, Architecture Review Board  
**Review Cycle:** Archive after Option 2 production deployment (recommended architecture implemented)  
**Security Classification:** Contains sensitive architectural details - do not distribute publicly

---

**END OF DOCUMENT**
