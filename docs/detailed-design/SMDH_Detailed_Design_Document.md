# Smart Manufacturing Data Hub (SMDH)

## Detailed Infrastructure Design Document

### Version 1.3

**Document Classification:** Internal Use Only
**Date:** 20 November 2025
**Author:** David McNabb
**Status:** Draft

### Version 1.3 Changes

- Added comprehensive Milesight UG65 Gateway Configuration guide (Section 12)
- Documented UG65 dual-protocol support (MQTT and HTTP)
- Added physical deployment procedures and site survey guidelines
- Included network server configuration and codec management
- Enhanced with firmware update procedures and troubleshooting guides
- Updated Component Inventory with detailed UG65 specifications

### Version 1.2 Changes

- Added comprehensive DevTank OpenSmartMonitor sensor integration (Section 11)
- Documented DevTank binary payload format and JavaScript decoder
- Added DevTank-specific Snowflake tables and Dynamic Tables
- Included complete deployment and maintenance procedures for DevTank sensors
- Updated Component Inventory to include DevTank OSM device
- Updated Data Source Coverage with DevTank sensor types
- Enhanced Tenant Onboarding Checklist with DevTank-specific steps

### Version 1.1 Changes

- Clarified that ingestion method selection is driven by data source protocols
- Added clear protocol-to-component mapping showing when IoT Core/Kinesis vs API Gateway is required
- Updated MQTT devices require AWS IoT Core (cannot connect directly to Snowflake)
- Updated MQTT section from "extension" to primary ingestion option for MQTT-based devices
- Added decision tree for selecting appropriate ingestion method

---

## Document Control

| Attribute            | Value                                    |
| -------------------- | ---------------------------------------- |
| **Status**           | Draft - Candidate Design                 |
| **Classification**   | Internal Use Only                        |
| **Purpose**          | Technical design for SMDH implementation |
| **Next Review Date** | 13 February 2026                         |

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Architecture Overview](#2-architecture-overview)
3. [Data Ingestion Layer](#3-data-ingestion-layer)
4. [Snowflake Data Platform](#4-snowflake-data-platform)
5. [Analytics and Visualisation](#5-analytics-and-visualisation)
6. [Security Architecture](#6-security-architecture)
7. [Multi-Tenancy Strategy](#7-multi-tenancy-strategy)
8. [Implementation Guide](#8-implementation-guide)
9. [Operational Procedures](#9-operational-procedures)
10. [MQTT Ingestion Extension](#10-mqtt-ingestion-extension)
11. [DevTank Sensor Integration](#11-devtank-sensor-integration)
12. [Milesight UG65 Gateway Configuration](#12-milesight-ug65-gateway-configuration)
13. [Appendices](#13-appendices)

---

## 1. Executive Summary

### 1.1 Document Purpose

This document provides the technical design for the Smart Manufacturing Data Hub Infrastructure components. The architecture design is driven by the specific requirements of different data sources and their transport protocols.

### 1.2 Data Source Requirements Drive Architecture

The SMDH platform must accommodate diverse data sources, each with specific transport protocol requirements:

**Protocol-Driven Ingestion Paths:**

- **MQTT-based sensors** (LoRaWAN gateways): Require AWS IoT Core for MQTT broker functionality
- **HTTP/REST API sources** (legacy systems, some RFID): Can use API Gateway for direct ingestion
- **File-based uploads** (CSV, Excel, manual entry): Use Streamlit web interface for user uploads
- **Streaming requirements**: Kinesis or Kafka needed when buffering/ordering matters

### 1.3 Architecture Options Based on Data Transport

- **Real-time MQTT sensors**: IoT Core → Kinesis → Snowflake
- **HTTP/REST sources**: API Gateway → Lambda → Snowflake
- **File uploads**: Streamlit interface → Snowflake stages

### 1.4 Key Architecture Decisions

| Decision Point        | Selected Approach       | Rationale                                                 |
| --------------------- | ----------------------- | --------------------------------------------------------- |
| **MQTT Support**      | AWS IoT Core required   | Native MQTT broker for LoRaWAN gateways                   |
| **Stream Processing** | Kinesis for buffering   | Message ordering and reliability for high-frequency data  |
| **HTTP Ingestion**    | API Gateway + Lambda    | Validation and multi-tenant security                      |
| **File Uploads**      | Streamlit native upload | User-friendly interface with direct Snowflake integration |
| **Data Platform**     | Snowflake-centric       | Unified processing, storage, and analytics                |

### 1.5 Protocol-to-Component Mapping

| Data Source              | Protocol    | Required Components    | Snowflake Integration          |
| ------------------------ | ----------- | ---------------------- | ------------------------------ |
| **LoRaWAN Sensors**      | MQTT        | IoT Core → Kinesis     | Openflow Connector or Snowpipe |
| **Modbus Energy Meters** | MQTT/TCP    | IoT Core or Direct TCP | Kinesis → Snowflake            |
| **RFID/Barcode**         | HTTP/REST   | API Gateway            | Lambda → Snowpipe API          |
| **Legacy Systems**       | File Upload | Streamlit              | Direct stage write             |
| **Manual Entry**         | Web Forms   | Streamlit              | Direct table insert            |

### 1.6 Architecture Principles

1. **Protocol-Appropriate Ingestion**: Match ingestion path to data source requirements
2. **Snowflake-Centric Processing**: Consolidate transformation and analytics in Snowflake
3. **Security-First Design**: Validate at ingestion points before Snowflake entry
4. **Operational Simplicity**: Minimize custom code; use managed services
5. **Multi-Tenant Isolation**: Enforce tenant boundaries at every layer

---

## 2. Architecture Overview

### 2.1 High-Level Architecture

The SMDH platform implements a **Protocol-Driven Multi-Path Architecture** where the ingestion method is determined by the data source's communication protocol:

**Data Flow Architecture:**

```
MQTT-BASED INGESTION (IoT Sensors, LoRaWAN Gateways)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Sensors → LoRaWAN → Gateway → AWS IoT Core (MQTT Broker)
                                       ↓
                                IoT Rules Engine
                                       ↓
                        Kinesis Data Streams (Buffering)
                                       ↓
                    Snowflake (via Openflow or Snowpipe)

HTTP/REST API INGESTION (Legacy Systems, Some Gateways)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Systems → HTTP POST → API Gateway → Lambda (Validation)
                                       ↓
                              Snowpipe Streaming API
                                       ↓
                             Snowflake Raw Tables

FILE-BASED INGESTION (Manual Uploads, Batch Exports)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Users → Streamlit Web Portal → File Upload Widget
                                       ↓
                              Snowflake Stages
                                       ↓
                    Snowpipe (Auto-Ingest) → Raw Tables

UNIFIED SNOWFLAKE PROCESSING
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
All Raw Tables → Streams → Tasks → Dynamic Tables
                                       ↓
                                 Cortex ML
                                       ↓
                    Analytics (Power BI, Streamlit, etc.)
```

**Key Design Decisions:**

- **MQTT requires IoT Core**: Cannot directly connect MQTT devices to Snowflake
- **Kinesis for streaming**: Provides buffering, ordering, and replay capabilities
- **API Gateway for HTTP**: Centralized security and rate limiting for REST APIs
- **Streamlit for user uploads**: Native Snowflake integration for file handling
- **Unified processing**: All data converges in Snowflake regardless of ingestion path

### 2.2 Technology Stack

| Layer                | Technology                           | Purpose                                | Hosting          |
| -------------------- | ------------------------------------ | -------------------------------------- | ---------------- |
| **IoT Connectivity** | AWS IoT Core                         | MQTT broker, device registry           | AWS Managed      |
| **Stream Buffering** | AWS Kinesis Data Streams             | Real-time data buffering               | AWS Managed      |
| **Stream Ingestion** | Snowflake Openflow Kinesis Connector | Native Kinesis → Snowflake ingestion   | Snowflake Native |
| **Batch Ingestion**  | Snowflake Streamlit File Upload      | CSV/Excel/JSON file uploads            | Snowflake Native |
| **Data Platform**    | Snowflake                            | Storage, processing, ML, orchestration | Snowflake SaaS   |
| **Identity**         | Snowflake IAM                        | User authentication and RBAC           | Snowflake Native |
| **Portal**           | Snowflake Streamlit                  | Web application + file upload          | Snowflake Native |
| **Analytics**        | Power BI                             | Advanced visualisations and reports    | Microsoft Cloud  |
| **Sensors**          | DevTank + LoRaWAN                    | IoT data collection (1 Hz)             | Edge Devices     |
| **Gateway**          | Milesight UG65                       | LoRaWAN to MQTT                        | On-Premises      |

### 2.3 Component Inventory

| Component                    | Status    | Version/Details             | Purpose                                                    |
| ---------------------------- | --------- | --------------------------- | ---------------------------------------------------------- |
| **DevTank OpenSmartMonitor** | VALIDATED | Firmware v4.1.0             | Multi-sensor IoT device (air quality, energy, environment) |
| **Milesight UG65**           | VALIDATED | Firmware v2.10              | LoRaWAN gateway with MQTT support                          |
| **AWS IoT Core**             | VALIDATED | MQTT v3.1.1/v5.0            | MQTT broker and device registry                            |
| **AWS Kinesis Data Streams** | VALIDATED | On-Demand capacity          | Real-time stream buffering                                 |
| **Snowflake Openflow**       | PREVIEW   | Kinesis Connector           | Native Kinesis → Snowflake ingestion                       |
| **Snowflake**                | VALIDATED | Standard Edition, eu-west-2 | Data platform                                              |
| **Snowpipe**                 | VALIDATED | File-based ingestion        | Batch file loading from stages                             |
| **Snowflake Streams**        | VALIDATED | Native CDC                  | Change data capture                                        |
| **Snowflake Tasks**          | VALIDATED | SQL/Python                  | ETL orchestration                                          |
| **Dynamic Tables**           | VALIDATED | Auto-refresh                | Real-time aggregations                                     |
| **Cortex ML**                | VALIDATED | Built-in functions          | Anomaly detection, forecasting                             |
| **Snowflake IAM**            | VALIDATED | SCIM 2.0, SAML 2.0          | Identity and access management                             |
| **Streamlit**                | VALIDATED | Python framework            | Web portal + file upload                                   |
| **Power BI**                 | VALIDATED | DirectQuery + Import        | Analytics and reporting                                    |

### 2.4 Data Source Coverage

| Data Source               | Device Type      | Volume                | Frequency              | Ingestion Path                | Protocol                     |
| ------------------------- | ---------------- | --------------------- | ---------------------- | ----------------------------- | ---------------------------- |
| **DevTank OSM Sensors**   | OpenSmartMonitor | 2-5 per site          | 1-15 minute intervals  | IoT Core → Kinesis → Openflow | LoRaWAN → MQTT or Wi-Fi MQTT |
| **Machine Sensors**       | Generic LoRaWAN  | 5-10 sensors per site | 1 Hz (continuous)      | IoT Core → Kinesis → Openflow | LoRaWAN → MQTT               |
| **Energy Monitors**       | Modbus/LoRaWAN   | 0-3 per site          | 15-second intervals    | IoT Core → Kinesis → Openflow | Modbus → MQTT                |
| **Air Quality Sensors**   | Generic LoRaWAN  | 0-2 per facility      | 1-minute intervals     | IoT Core → Kinesis → Openflow | LoRaWAN → MQTT               |
| **RFID/Barcode Events**   | N/A              | 500-2000 scans/day    | Event-driven           | Streamlit file upload         | CSV/JSON files               |
| **Legacy System Exports** | N/A              | 5-50 GB per company   | Weekly/Monthly batches | Streamlit file upload         | CSV/Excel/JSON               |
| **Manual Data Entry**     | N/A              | Variable              | Ad-hoc                 | Streamlit forms               | Web UI                       |

---

## 3. Data Ingestion Layer

### 3.1 Ingestion Architecture

The SMDH platform implements protocol-specific ingestion paths based on how data sources communicate. Different data sources have protocol and authentication requirements that dictate the ingestion architecture:

- **MQTT devices** cannot directly connect to Snowflake (requires MQTT broker)
- **HTTP/REST sources** can use API Gateway but need validation layer
- **File uploads** need user interface and staging area
- **Streaming data** requires buffering and ordering guarantees

### 3.2 Ingestion Path Selection Criteria

| Criteria           | MQTT Path (IoT Core)     | HTTP Path (API Gateway) | File Path (Streamlit) |
| ------------------ | ------------------------ | ----------------------- | --------------------- |
| **Protocol**       | MQTT v3.1.1/v5           | HTTP/REST               | Browser upload        |
| **Connection**     | Persistent               | Request-Response        | Interactive           |
| **Authentication** | X.509 certificates       | API keys                | Snowflake SSO         |
| **Volume**         | Medium (5-26M/day total) | Low-Medium              | Low-Medium            |
| **Latency**        | Near real-time           | Low latency             | Batch                 |
| **Ordering**       | Required                 | Optional                | Not required          |
| **Use Cases**      | IoT sensors, gateways    | Legacy APIs, webhooks   | Manual uploads        |

### 3.3 MQTT-Based Ingestion (IoT Core + Kinesis)

This ingestion path is **required for MQTT-based devices** including LoRaWAN gateways and IoT sensors that communicate via MQTT protocol.

**When to Use This Path:**

- Devices that only support MQTT protocol
- LoRaWAN gateways (e.g., Milesight UG65 in MQTT mode)
- High-frequency sensor data requiring persistent connections
- Scenarios requiring QoS guarantees and message ordering

#### 3.4.1 Architecture Flow

```
┌─────────────────┐
│  Sensor Device  │ LoRaWAN (868 MHz)
│  (1 Hz data)    │
└────────┬────────┘
         │
         ↓
┌─────────────────┐
│  UG65 Gateway   │ Decode + Transform
│  (MQTT Client)  │
└────────┬────────┘
         │ MQTT Publish (TLS 1.3)
         │ Topic: smdh/{tenant_id}/sensor-data
         ↓
┌─────────────────┐
│ AWS IoT Core    │ Device Registry + X.509 Auth
│ (MQTT Broker)   │ QoS 1 (at-least-once)
└────────┬────────┘
         │
         ↓
┌─────────────────┐
│ IoT Rules Engine│ SQL: SELECT topic(2) as tenant_id, * FROM 'smdh/+/sensor-data'
│                 │
└────────┬────────┘
         │
         ↓
┌─────────────────┐
│ Kinesis Data    │ Stream Buffer (On-Demand capacity)
│ Streams         │ Retention: 24 hours
└────────┬────────┘
         │
         ↓
┌─────────────────┐
│ Snowflake       │ Native Kinesis Connector
│ Openflow        │ Reads from Kinesis → Writes to Snowflake
│ Connector       │ Uses Snowpipe Streaming internally
└────────┬────────┘
         │
         ↓
┌─────────────────┐
│ Snowflake       │ Database: smdh_tenant_{tenant_id}
│ Raw Table       │ Table: raw.sensor_readings
└─────────────────┘
```

#### 3.3.2 AWS IoT Core Configuration

**IoT Thing Setup (per gateway):**

```bash
# Create IoT Thing for gateway
aws iot create-thing \
  --thing-name "smdh-gateway-${TENANT_ID}-${SITE_ID}" \
  --thing-type-name "LoRaWANGateway" \
  --attribute-payload '{
    "tenant_id":"'${TENANT_ID}'",
    "site_id":"'${SITE_ID}'",
    "deployment_type":"production"
  }' \
  --region eu-west-2

# Generate X.509 certificate
aws iot create-keys-and-certificate \
  --set-as-active \
  --certificate-pem-outfile ${TENANT_ID}-gateway-cert.pem \
  --public-key-outfile ${TENANT_ID}-gateway-public.key \
  --private-key-outfile ${TENANT_ID}-gateway-private.key \
  --region eu-west-2

# Store certificate ARN
CERT_ARN=$(aws iot create-keys-and-certificate --set-as-active --query 'certificateArn' --output text --region eu-west-2)

# Attach certificate to thing
aws iot attach-thing-principal \
  --thing-name "smdh-gateway-${TENANT_ID}-${SITE_ID}" \
  --principal "${CERT_ARN}" \
  --region eu-west-2

# Download Amazon Root CA
wget https://www.amazontrust.com/repository/AmazonRootCA1.pem
```

**IoT Policy (Least Privilege per Tenant):**

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "iot:Connect",
      "Resource": "arn:aws:iot:eu-west-2:${ACCOUNT_ID}:client/smdh-gateway-${TENANT_ID}-*"
    },
    {
      "Effect": "Allow",
      "Action": "iot:Publish",
      "Resource": [
        "arn:aws:iot:eu-west-2:${ACCOUNT_ID}:topic/smdh/${TENANT_ID}/sensor-data",
        "arn:aws:iot:eu-west-2:${ACCOUNT_ID}:topic/smdh/${TENANT_ID}/device-status"
      ]
    },
    {
      "Effect": "Allow",
      "Action": "iot:Subscribe",
      "Resource": "arn:aws:iot:eu-west-2:${ACCOUNT_ID}:topicfilter/smdh/${TENANT_ID}/commands/#"
    },
    {
      "Effect": "Allow",
      "Action": "iot:Receive",
      "Resource": "arn:aws:iot:eu-west-2:${ACCOUNT_ID}:topic/smdh/${TENANT_ID}/commands/*"
    }
  ]
}
```

```bash
# Create policy
aws iot create-policy \
  --policy-name "smdh-gateway-${TENANT_ID}-policy" \
  --policy-document file://iot-policy.json \
  --region eu-west-2

# Attach policy to certificate
aws iot attach-policy \
  --policy-name "smdh-gateway-${TENANT_ID}-policy" \
  --target "${CERT_ARN}" \
  --region eu-west-2
```

#### 3.4.3 UG65 Gateway MQTT Configuration

**Gateway Web Interface Configuration:**

```
Network Server > Application > MQTT Integration

MQTT Server: ${IOT_ENDPOINT}.iot.eu-west-2.amazonaws.com
Port: 8883 (MQTTS)
Protocol: MQTT v3.1.1
Client ID: smdh-gateway-${TENANT_ID}-${SITE_ID}

TLS/SSL Configuration:
  [YES] Enable TLS
  - CA Certificate: AmazonRootCA1.pem (upload)
  - Client Certificate: ${TENANT_ID}-gateway-cert.pem (upload)
  - Client Private Key: ${TENANT_ID}-gateway-private.key (upload)

MQTT Topics:
  - Publish Topic: smdh/${TENANT_ID}/sensor-data
  - QoS Level: 1 (At least once delivery)
  - Retain: false

Payload Settings:
  - Format: JSON
  - Include Device EUI: [YES]
  - Include Timestamp: [YES]
  - Include RSSI/SNR: [YES]
  - Codec: LoRaWAN (automatic decoding)

Connection:
  - Keep Alive: 60 seconds
  - Clean Session: false (persistent session)
  - Auto Reconnect: [YES]
  - Reconnect Interval: 5 seconds (exponential backoff)

Buffer Settings:
  - Offline Buffer: 10,000 messages
  - Buffer Strategy: Store-and-forward
```

**Example MQTT Payload:**

```json
{
  "applicationID": "1",
  "applicationName": "smdh_${TENANT_ID}",
  "deviceName": "machine-sensor-floor-1-press-A",
  "devEUI": "a840410000000123",
  "timestamp": "2025-11-13T10:30:45.123456Z",
  "fPort": 2,
  "data": {
    "temperature": 22.5,
    "vibration": 0.8,
    "state": "RUNNING",
    "cycle_count": 1542,
    "battery": 3.6
  },
  "rxInfo": [
    {
      "gatewayID": "smdh-gateway-company-a-site-001",
      "rssi": -85,
      "loRaSNR": 8.5,
      "channel": 3,
      "rfChain": 1
    }
  ]
}
```

#### 3.4.4 IoT Rules Engine Configuration

**Rule SQL Statement:**

```sql
SELECT
  topic(2) as tenant_id,
  timestamp() as iot_timestamp,
  clientId() as gateway_id,
  *
FROM 'smdh/+/sensor-data'
WHERE tenant_id IS NOT NULL
```

**Rule Action: Forward to Kinesis Data Streams**

```bash
# Create Kinesis stream (per tenant or shared with partitioning)
aws kinesis create-stream \
  --stream-name smdh-sensor-data-stream \
  --stream-mode-details Mode=ON_DEMAND \
  --region eu-west-2

# Create IAM role for IoT Rules → Kinesis
cat > iot-kinesis-trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "Service": "iot.amazonaws.com"
    },
    "Action": "sts:AssumeRole"
  }]
}
EOF

aws iam create-role \
  --role-name smdh-iot-kinesis-role \
  --assume-role-policy-document file://iot-kinesis-trust-policy.json

# Attach policy for Kinesis PutRecord
aws iam attach-role-policy \
  --role-name smdh-iot-kinesis-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonKinesisFullAccess

# Create IoT Rule
aws iot create-topic-rule \
  --rule-name smdh_sensor_to_kinesis \
  --topic-rule-payload '{
    "sql": "SELECT topic(2) as tenant_id, timestamp() as iot_timestamp, clientId() as gateway_id, * FROM '\''smdh/+/sensor-data'\'' WHERE tenant_id IS NOT NULL",
    "description": "Route sensor data from IoT Core to Kinesis Data Streams",
    "actions": [{
      "kinesis": {
        "roleArn": "arn:aws:iam::'${ACCOUNT_ID}':role/smdh-iot-kinesis-role",
        "streamName": "smdh-sensor-data-stream",
        "partitionKey": "${tenant_id}"
      }
    }],
    "errorAction": {
      "republish": {
        "roleArn": "arn:aws:iam::'${ACCOUNT_ID}':role/smdh-iot-kinesis-role",
        "topic": "smdh/errors",
        "qos": 1
      }
    },
    "ruleDisabled": false
  }' \
  --region eu-west-2
```

**Partition Key Strategy:**

- **Partition Key**: `${tenant_id}` ensures all messages from same tenant go to same shard
- **Benefits**: Maintains order per tenant; enables tenant-level scaling
- **Kinesis Capacity**: On-Demand mode auto-scales based on throughput

#### 3.4.5 Snowflake Openflow Kinesis Connector Setup

**Connector Configuration:**

```sql
-- 1. Create external AWS connection in Snowflake
CREATE OR REPLACE CONNECTION aws_kinesis_connection
    TYPE = 'AWS'
    CREDENTIALS = (
        AWS_KEY_ID = 'AKIAIOSFODNN7EXAMPLE'
        AWS_SECRET_KEY = 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY'
        AWS_ROLE = 'arn:aws:iam::123456789:role/snowflake-kinesis-read-role'
    );

-- 2. Create Openflow connector for Kinesis
CREATE OR REPLACE OPENFLOW CONNECTOR kinesis_sensor_ingestion
    TYPE = KINESIS
    CONNECTION = aws_kinesis_connection
    KINESIS_STREAM_NAME = 'smdh-sensor-data-stream'
    KINESIS_REGION = 'eu-west-2'
    TARGET_DATABASE = SMDH_TENANT_${TENANT_ID}
    TARGET_SCHEMA = RAW
    MESSAGE_FORMAT = JSON
    AUTO_RESUME = TRUE
    COMMENT = 'Ingest sensor data from Kinesis to Snowflake';

-- 3. Start the connector
ALTER OPENFLOW CONNECTOR kinesis_sensor_ingestion RESUME;

-- 4. Monitor connector status
SHOW OPENFLOW CONNECTORS LIKE 'kinesis_sensor_ingestion';

-- 5. View connector metrics
SELECT *
FROM SNOWFLAKE.ACCOUNT_USAGE.OPENFLOW_CONNECTOR_HISTORY
WHERE CONNECTOR_NAME = 'KINESIS_SENSOR_INGESTION'
ORDER BY START_TIME DESC
LIMIT 100;
```

**AWS IAM Role for Snowflake Openflow:**

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "kinesis:DescribeStream",
        "kinesis:DescribeStreamSummary",
        "kinesis:GetRecords",
        "kinesis:GetShardIterator",
        "kinesis:ListShards",
        "kinesis:ListStreams",
        "kinesis:SubscribeToShard"
      ],
      "Resource": "arn:aws:kinesis:eu-west-2:${ACCOUNT_ID}:stream/smdh-sensor-data-stream"
    },
    {
      "Effect": "Allow",
      "Action": [
        "dynamodb:CreateTable",
        "dynamodb:DescribeTable",
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:Scan",
        "dynamodb:UpdateItem",
        "dynamodb:DeleteItem"
      ],
      "Resource": "arn:aws:dynamodb:eu-west-2:${ACCOUNT_ID}:table/snowflake-kinesis-*"
    }
  ]
}
```

**Trust Relationship for Snowflake:**

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::${SNOWFLAKE_ACCOUNT}:root"
      },
      "Action": "sts:AssumeRole",
      "Condition": {
        "StringEquals": {
          "sts:ExternalId": "${SNOWFLAKE_EXTERNAL_ID}"
        }
      }
    }
  ]
}
```

#### 3.4.6 Snowflake Target Table Schema

```sql
-- Create raw sensor readings table
CREATE OR REPLACE TABLE smdh_tenant_${TENANT_ID}.raw.sensor_readings (
    -- IoT metadata (added by IoT Rules)
    tenant_id VARCHAR(100) NOT NULL,
    iot_timestamp TIMESTAMP_NTZ NOT NULL,
    gateway_id VARCHAR(255) NOT NULL,

    -- Sensor identification
    device_eui VARCHAR(50) NOT NULL,
    device_name VARCHAR(255),
    application_id VARCHAR(50),
    application_name VARCHAR(100),

    -- Timing
    sensor_timestamp TIMESTAMP_NTZ NOT NULL,

    -- Sensor payload (flexible schema)
    data VARIANT NOT NULL,

    -- LoRaWAN metadata
    rx_info VARIANT,
    f_port INTEGER,

    -- Ingestion metadata
    ingestion_timestamp TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    source_system VARCHAR(50) DEFAULT 'iot_core_kinesis',

    -- Primary key
    PRIMARY KEY (tenant_id, device_eui, sensor_timestamp)
)
CLUSTER BY (tenant_id, DATE_TRUNC('hour', sensor_timestamp), device_eui)
ENABLE_SCHEMA_EVOLUTION = TRUE
COMMENT = 'Raw sensor readings from IoT Core → Kinesis → Openflow';

-- Create stream for CDC
CREATE OR REPLACE STREAM smdh_tenant_${TENANT_ID}.raw.sensor_readings_stream
ON TABLE smdh_tenant_${TENANT_ID}.raw.sensor_readings
APPEND_ONLY = TRUE
COMMENT = 'Change data capture stream for sensor readings';
```

#### 3.3.7 Multi-Tenancy Strategy

**Option A: Single Kinesis Stream with Tenant Partitioning**

```
Kinesis Stream: smdh-sensor-data-stream
├─ Partition Key: tenant_id
├─ All tenants share stream
├─ Snowflake Openflow reads all messages
└─ Snowflake routes to tenant database via tenant_id field

Pros:
[YES] Simpler AWS infrastructure
[YES] Lower Kinesis cost (single stream)
[YES] Single Openflow connector

Cons:
[NO] No strict AWS-level tenant isolation
[NO] Snowflake Openflow must route to multiple databases
```

**Option B: Per-Tenant Kinesis Stream**

```
Kinesis Stream: smdh-sensor-data-${TENANT_ID}
├─ Dedicated stream per tenant
├─ Dedicated Openflow connector per tenant
└─ Direct write to tenant database

Pros:
[YES] Strict AWS-level tenant isolation
[YES] Independent scaling per tenant
[YES] Simpler Snowflake routing

Cons:
[NO] More AWS resources to manage
[NO] Higher Kinesis costs
[NO] Multiple Openflow connectors
```

**Recommended: Option A** for cost efficiency and operational simplicity, with Snowflake database-level isolation providing sufficient security.

#### 3.3.8 Data Flow Latency

```
Component                          Latency
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Sensor → Gateway (LoRaWAN)         <100 ms
Gateway → IoT Core (MQTT)          10-50 ms
IoT Rules → Kinesis                10-30 ms
Kinesis → Openflow (buffering)     1-5 seconds
Openflow → Snowflake Table         2-8 seconds
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
TOTAL END-TO-END:                  3-13 seconds

(Data queryable in Snowflake within ~5-15 seconds of sensor reading)
```

### 3.4 File-Based Ingestion (Streamlit Portal)

This ingestion path handles **file uploads, manual data entry, and batch imports** through the Snowflake Streamlit portal.

**When to Use This Path:**

- CSV/Excel exports from legacy systems
- Manual data uploads by users
- Batch processing of historical data
- RFID scan logs delivered as files
- Any data not available via real-time APIs

#### 3.4.1 Architecture Flow

```
┌─────────────────┐
│  User Browser   │ HTTPS (SSO via Snowflake IAM)
│                 │
└────────┬────────┘
         │
         ↓
┌─────────────────┐
│ Snowflake       │ Python-based Web Application
│ Streamlit App   │ Authentication: Snowflake SSO
│                 │
└────────┬────────┘
         │
         ↓
┌─────────────────┐
│ file_uploader() │ Streamlit Widget
│ Widget          │ Formats: CSV, Excel, JSON, PDF, PNG
└────────┬────────┘
         │
         ↓
┌─────────────────┐
│ Snowflake Stage │ Internal named stage
│ @upload_stage   │ Encryption: Server-side AES-256
└────────┬────────┘
         │
         ↓
┌─────────────────┐
│ Snowpipe        │ File-based auto-ingest
│                 │ Latency: Seconds (micro-batch)
└────────┬────────┘
         │
         ↓
┌─────────────────┐
│ Snowflake       │ Database: smdh_tenant_{tenant_id}
│ Raw Table       │ Table: raw.uploaded_files
└─────────────────┘
```

#### 3.4.2 Streamlit File Upload Implementation

**Streamlit App File Upload Page:**

```python
"""
pages/file_upload.py
Batch file upload for legacy systems, RFID logs, manual data entry
"""

import streamlit as st
import pandas as pd
from snowflake.snowpark.context import get_active_session
from datetime import datetime
import json

def render(session, tenant_id):
    """
    Render file upload page

    Args:
        session: Snowflake Snowpark session (auto-authenticated)
        tenant_id: Extracted from user's role
    """

    st.title(" Batch Data Upload")

    if not tenant_id:
        st.error("Access denied: No tenant context available")
        return

    st.write(f"**Tenant:** {tenant_id}")
    st.write("Upload CSV, Excel, or JSON files for batch processing")

    # File type selector
    upload_type = st.selectbox(
        "Select Data Type",
        ["RFID Scan Logs", "Energy Meter Exports", "Production Logs", "Quality Inspection Data", "Custom Data"]
    )

    # File uploader
    uploaded_file = st.file_uploader(
        "Choose a file",
        type=['csv', 'xlsx', 'xls', 'json'],
        help="Supported formats: CSV, Excel (.xlsx, .xls), JSON"
    )

    if uploaded_file is not None:
        # Display file info
        st.write(f"**Filename:** {uploaded_file.name}")
        st.write(f"**Size:** {uploaded_file.size / 1024:.2f} KB")
        st.write(f"**Type:** {uploaded_file.type}")

        # Read and preview data
        try:
            df = read_file(uploaded_file)

            st.subheader("Data Preview")
            st.write(f"**Rows:** {len(df):,}")
            st.write(f"**Columns:** {len(df.columns)}")
            st.dataframe(df.head(20))

            # Data quality checks
            st.subheader("Data Quality Check")
            col1, col2, col3 = st.columns(3)

            with col1:
                null_count = df.isnull().sum().sum()
                st.metric("Null Values", f"{null_count:,}")

            with col2:
                duplicate_count = df.duplicated().sum()
                st.metric("Duplicate Rows", f"{duplicate_count:,}")

            with col3:
                data_types = df.dtypes.value_counts()
                st.metric("Column Types", len(data_types))

            # Upload button
            if st.button("[YES] Upload to Snowflake", type="primary"):
                with st.spinner("Uploading to Snowflake..."):
                    try:
                        # Upload to Snowflake
                        result = upload_to_snowflake(
                            session,
                            df,
                            tenant_id,
                            upload_type,
                            uploaded_file.name
                        )

                        st.success(f" Successfully uploaded {len(df):,} rows!")

                        # Show upload details
                        st.info(f"""
                        **Upload Details:**
                        - Table: `smdh_tenant_{tenant_id}.raw.uploaded_files`
                        - Rows: {len(df):,}
                        - Upload Type: {upload_type}
                        - Processing: Data will be available in 10-30 seconds
                        """)

                        # Show next steps
                        st.write("**Next Steps:**")
                        st.write("1. Data is being processed by Snowflake Tasks")
                        st.write("2. Check the 'Data Quality' tab for validation results")
                        st.write("3. View processed data in the relevant dashboard")

                    except Exception as e:
                        st.error(f" Upload failed: {str(e)}")
                        st.exception(e)

        except Exception as e:
            st.error(f" Failed to read file: {str(e)}")
            st.exception(e)

def read_file(uploaded_file):
    """Read uploaded file into pandas DataFrame"""

    if uploaded_file.name.endswith('.csv'):
        df = pd.read_csv(uploaded_file)

    elif uploaded_file.name.endswith(('.xlsx', '.xls')):
        df = pd.read_excel(uploaded_file)

    elif uploaded_file.name.endswith('.json'):
        df = pd.read_json(uploaded_file)

    else:
        raise ValueError(f"Unsupported file type: {uploaded_file.name}")

    return df

def upload_to_snowflake(session, df, tenant_id, upload_type, filename):
    """
    Upload DataFrame to Snowflake using Snowpark

    This writes directly to a Snowflake table without intermediate staging
    """

    # Add metadata columns
    df['tenant_id'] = tenant_id
    df['upload_type'] = upload_type
    df['original_filename'] = filename
    df['upload_timestamp'] = datetime.utcnow()
    df['uploaded_by'] = session.sql("SELECT CURRENT_USER()").collect()[0][0]
    df['processing_status'] = 'PENDING'

    # Create Snowpark DataFrame
    snowpark_df = session.create_dataframe(df)

    # Write to Snowflake table
    table_name = f"smdh_tenant_{tenant_id}.raw.uploaded_files"

    snowpark_df.write.mode("append").save_as_table(table_name)

    # Trigger processing task (async)
    session.sql(f"""
        EXECUTE TASK smdh_tenant_{tenant_id}.raw.task_process_uploaded_files
    """).collect()

    return {
        'rows': len(df),
        'table': table_name,
        'timestamp': datetime.utcnow()
    }
```

#### 3.4.3 Alternative: Stage-Based Upload with Snowpipe

For very large files (>100 MB), use Snowflake stages with Snowpipe auto-ingest:

```python
def upload_large_file_to_stage(session, uploaded_file, tenant_id):
    """
    Upload large file to Snowflake stage and trigger Snowpipe
    """

    # Create stage if not exists
    stage_name = f"@smdh_tenant_{tenant_id}.raw.upload_stage"

    session.sql(f"""
        CREATE STAGE IF NOT EXISTS {stage_name}
        ENCRYPTION = (TYPE = 'SNOWFLAKE_SSE')
        COMMENT = 'Batch file upload stage';
    """).collect()

    # Upload file to stage using PUT command
    # Note: Streamlit runs in Snowflake, so PUT is available
    file_path = f"/tmp/{uploaded_file.name}"

    with open(file_path, 'wb') as f:
        f.write(uploaded_file.getbuffer())

    session.sql(f"""
        PUT file://{file_path} {stage_name}
        AUTO_COMPRESS = TRUE
        OVERWRITE = TRUE
    """).collect()

    # Snowpipe will auto-ingest from stage
    st.info("File uploaded to stage. Snowpipe will process within 1-2 minutes.")

    return stage_name
```

#### 3.4.4 Snowflake Target Table for Uploaded Files

```sql
-- Create table for uploaded batch files
CREATE OR REPLACE TABLE smdh_tenant_${TENANT_ID}.raw.uploaded_files (
    -- Upload metadata
    tenant_id VARCHAR(100) NOT NULL,
    upload_type VARCHAR(100) NOT NULL,
    original_filename VARCHAR(500) NOT NULL,
    upload_timestamp TIMESTAMP_NTZ NOT NULL,
    uploaded_by VARCHAR(255) NOT NULL,
    processing_status VARCHAR(50) NOT NULL, -- PENDING, PROCESSING, COMPLETED, FAILED

    -- File content (flexible schema)
    file_data VARIANT NOT NULL,

    -- Processing metadata
    processing_timestamp TIMESTAMP_NTZ,
    processing_error VARCHAR(5000),
    rows_processed INTEGER,

    PRIMARY KEY (tenant_id, upload_timestamp, original_filename)
)
CLUSTER BY (tenant_id, DATE_TRUNC('day', upload_timestamp))
COMMENT = 'Batch uploaded files from Streamlit portal';

-- Create stream for CDC
CREATE OR REPLACE STREAM smdh_tenant_${TENANT_ID}.raw.uploaded_files_stream
ON TABLE smdh_tenant_${TENANT_ID}.raw.uploaded_files
APPEND_ONLY = TRUE
COMMENT = 'CDC stream for uploaded files';

-- Create task to process uploaded files
CREATE OR REPLACE TASK smdh_tenant_${TENANT_ID}.raw.task_process_uploaded_files
    WAREHOUSE = etl_wh
    SCHEDULE = '1 MINUTE'
    WHEN SYSTEM$STREAM_HAS_DATA('smdh_tenant_${TENANT_ID}.raw.uploaded_files_stream')
AS
    CALL smdh_tenant_${TENANT_ID}.raw.sp_process_uploaded_files();

-- Resume task
ALTER TASK smdh_tenant_${TENANT_ID}.raw.task_process_uploaded_files RESUME;
```

#### 3.4.5 File Processing Stored Procedure

```sql
CREATE OR REPLACE PROCEDURE smdh_tenant_${TENANT_ID}.raw.sp_process_uploaded_files()
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.10'
PACKAGES = ('snowflake-snowpark-python', 'pandas')
HANDLER = 'process_files'
AS
$$
def process_files(session):
    from snowflake.snowpark.functions import col, when, current_timestamp

    # Read from stream
    stream_df = session.table("raw.uploaded_files_stream")

    # Filter pending files
    pending = stream_df.filter(col('PROCESSING_STATUS') == 'PENDING')

    if pending.count() == 0:
        return "No pending files to process"

    # Process each upload type
    for row in pending.collect():
        upload_type = row['UPLOAD_TYPE']

        if upload_type == 'RFID Scan Logs':
            process_rfid_logs(session, row)

        elif upload_type == 'Energy Meter Exports':
            process_energy_logs(session, row)

        elif upload_type == 'Production Logs':
            process_production_logs(session, row)

        # Mark as completed
        session.sql(f"""
            UPDATE raw.uploaded_files
            SET processing_status = 'COMPLETED',
                processing_timestamp = CURRENT_TIMESTAMP(),
                rows_processed = {len(row['FILE_DATA'])}
            WHERE upload_timestamp = '{row['UPLOAD_TIMESTAMP']}'
              AND original_filename = '{row['ORIGINAL_FILENAME']}'
        """).collect()

    return f"Processed {pending.count()} files"

def process_rfid_logs(session, row):
    """Transform RFID logs into normalized format"""
    # Implementation specific to RFID data format
    pass

def process_energy_logs(session, row):
    """Transform energy meter data into normalized format"""
    pass

def process_production_logs(session, row):
    """Transform production logs into normalized format"""
    pass
$$;
```

#### 3.4.6 Supported Use Cases

| Use Case                    | Frequency | Typical File Size | Format    | Processing                                 |
| --------------------------- | --------- | ----------------- | --------- | ------------------------------------------ |
| **RFID Scan Logs**          | Daily     | 1-10 MB           | CSV       | Parse scans → job tracking table           |
| **Energy Meter Exports**    | Weekly    | 5-50 MB           | CSV/Excel | Parse readings → energy table              |
| **Production Logs**         | Daily     | 10-100 MB         | CSV       | Parse production events → production table |
| **Quality Inspection Data** | Weekly    | 1-20 MB           | Excel     | Parse inspections → quality table          |
| **Manual Data Entry**       | Ad-hoc    | <1 MB             | JSON      | Direct insert → relevant table             |
| **Legacy System Exports**   | Monthly   | 50-500 MB         | CSV       | ETL transform → normalized tables          |

#### 3.4.7 Data Flow Latency (File-Based Ingestion)

```
Component                          Latency
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
User selects file                  0 ms
Streamlit reads file               <1 second
Snowpark write to table            1-5 seconds
Stream detects change              <1 second
Task triggers processing           <60 seconds (scheduled)
Processing completes               10-120 seconds (depends on file size)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
TOTAL END-TO-END:                  10-180 seconds

(Data queryable in Snowflake within 10 seconds - 3 minutes of upload)
```

### 3.5 HTTP/REST API Ingestion (API Gateway + Lambda)

This ingestion path handles **HTTP-based data sources** that cannot use MQTT but need real-time or near-real-time ingestion.

**When to Use This Path:**

- Gateways configured for HTTP POST (e.g., Milesight UG65 in HTTP mode)
- Legacy systems with webhook capabilities
- Third-party APIs and integrations
- RFID systems with HTTP endpoints
- Any REST API data sources

#### 3.5.1 Architecture Flow

```
┌─────────────────┐
│  Data Source    │ HTTP/REST API
│  (Gateway/API)  │
└────────┬────────┘
         │ HTTP POST with API Key
         ↓
┌─────────────────┐
│ API Gateway     │ Rate Limiting + Auth
│                 │
└────────┬────────┘
         │
         ↓
┌─────────────────┐
│ Lambda Function │ Validation + JWT Generation
│                 │
└────────┬────────┘
         │
         ↓
┌─────────────────┐
│ Snowpipe        │ Streaming API
│ Streaming       │
└────────┬────────┘
         │
         ↓
┌─────────────────┐
│ Snowflake       │ Raw Tables
│                 │
└─────────────────┘
```

### 3.6 Comparison of Ingestion Methods

| Aspect                  | MQTT (IoT Core + Kinesis)              | HTTP (API Gateway + Lambda) | File Upload (Streamlit) |
| ----------------------- | -------------------------------------- | --------------------------- | ----------------------- |
| **Data Type**           | High-frequency streams                 | Event-driven/webhooks       | Batch files/manual      |
| **Volume**              | 5-26M msgs/day total (150-300 sensors) | 100K-1M requests/day        | 5-50 GB/month           |
| **Frequency**           | Continuous (1 Hz)                      | Real-time events            | Daily/Weekly/Monthly    |
| **Latency**             | 5-15 seconds                           | 1-5 seconds                 | 10 seconds - 3 minutes  |
| **Protocol**            | MQTT v3.1.1/v5                         | HTTP/REST                   | Browser upload          |
| **Authentication**      | X.509 certificates                     | API keys                    | Snowflake SSO           |
| **AWS Services**        | IoT Core, Kinesis                      | API Gateway, Lambda         | None                    |
| **Snowflake Ingestion** | Openflow/Snowpipe                      | Snowpipe Streaming API      | Direct write            |
| **Cost Driver**         | Messages + streaming                   | API calls + compute         | Storage only            |
| **Best For**            | IoT sensors                            | Legacy APIs                 | Manual uploads          |

### 3.7 Selecting the Right Ingestion Method

**Decision Tree for Ingestion Method Selection:**

1. **What protocol does your data source support?**

   - MQTT only → Must use IoT Core + Kinesis path
   - HTTP/REST → Can use API Gateway + Lambda path
   - File-based → Use Streamlit upload interface

2. **What is your data frequency?**

   - Continuous streaming (>1 Hz) → MQTT path with Kinesis buffering
   - Event-driven → HTTP path with API Gateway
   - Batch/scheduled → File upload via Streamlit

3. **What are your security requirements?**
   - Device certificates → IoT Core (X.509)
   - API key management → API Gateway
   - User authentication → Streamlit (SSO)

**Important Considerations:**

- Some gateways (like Milesight UG65) support both MQTT and HTTP - choose based on your requirements
- MQTT provides persistent connections and QoS guarantees
- HTTP is simpler but requires more overhead for high-frequency data
- File uploads are best for historical data and manual processes

#### 3.7.1 Example: Milesight UG65 Gateway Configuration Options

The Milesight UG65 gateway can be configured for either MQTT or HTTP transport:

```
Gateway Settings:
├─ Protocol: HTTPS
├─ Method: POST
├─ URL: https://{api-id}.execute-api.eu-west-2.amazonaws.com/prod/ingest
├─ Headers:
│  ├─ x-api-key: {tenant-specific-api-key}
│  └─ Content-Type: application/json
├─ Payload Format: JSON (decoded sensor data)
└─ Retry: Store-and-forward (10,000 message buffer)
```

**Example Payload:**

```json
{
  "applicationID": "1",
  "applicationName": "tenant_company_a",
  "deviceName": "temp-sensor-floor-1",
  "devEUI": "a840410000000123",
  "rxInfo": [
    {
      "gatewayID": "ug65-site-001",
      "time": "2025-11-13T10:30:45.123456Z",
      "rssi": -85,
      "loRaSNR": 8.5
    }
  ],
  "object": {
    "temperature": 22.5,
    "humidity": 45,
    "battery": 3.6
  }
}
```

#### 3.7.2 HTTP/REST Implementation Details

**AWS API Gateway Configuration:**

```
API Gateway Design:
├─ Type: Regional REST API
├─ Endpoint: https://{api-id}.execute-api.eu-west-2.amazonaws.com/prod
├─ Authentication: API Key (x-api-key header)
├─ Usage Plans:
│  ├─ Throttle: 1,000 requests/second per tenant
│  └─ Quota: 100M requests/month per tenant
├─ Integration: Lambda Proxy
├─ Timeout: 29 seconds
└─ CORS: Disabled (IoT only)
```

**API Key Management:**

```bash
# Generate tenant-specific API key
API_KEY="smdh-prod-$(openssl rand -hex 32)"

# Create in API Gateway
aws apigateway create-api-key \
  --name "smdh-tenant-${TENANT_ID}-prod" \
  --enabled \
  --value "$API_KEY" \
  --region eu-west-2

# Associate with usage plan
aws apigateway create-usage-plan-key \
  --usage-plan-id ${USAGE_PLAN_ID} \
  --key-id ${API_KEY_ID} \
  --key-type API_KEY
```

**Lambda Function for HTTP Ingestion:**

```python
"""
SMDH Lambda Ingestion Function
Purpose: JWT generation, tenant validation, Snowpipe Streaming ingestion
Runtime: Python 3.12 on arm64
Memory: 512 MB
Timeout: 30 seconds
"""

import json
import time
import boto3
import requests
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.backends import default_backend
import jwt

# Global variables for warm start optimization
secrets_client = boto3.client('secretsmanager', region_name='eu-west-2')
dynamodb = boto3.resource('dynamodb', region_name='eu-west-2')
table = dynamodb.Table('smdh_api_key_mapping')

# Cache for private key and JWT
private_key_cache = None
jwt_token_cache = None
jwt_expiry_cache = None

def lambda_handler(event, context):
    """
    Main Lambda handler for sensor data ingestion
    """
    try:
        # 1. Extract API key from headers
        api_key = event['headers'].get('x-api-key')
        if not api_key:
            return {
                'statusCode': 403,
                'body': json.dumps({'error': 'Missing API key'})
            }

        # 2. Resolve tenant_id from API key
        tenant_id = resolve_tenant_id(api_key)
        if not tenant_id:
            return {
                'statusCode': 403,
                'body': json.dumps({'error': 'Invalid API key'})
            }

        # 3. Parse request body
        body = json.loads(event['body'])

        # 4. CRITICAL: Validate tenant_id match
        payload_tenant = body.get('applicationName', '').replace('tenant_', '')
        if payload_tenant != tenant_id:
            # Log security violation
            print(f"SECURITY VIOLATION: API key tenant {tenant_id} != payload tenant {payload_tenant}")

            # Send to DLQ for investigation
            send_to_dlq(body, f"Tenant mismatch: {tenant_id} vs {payload_tenant}")

            return {
                'statusCode': 403,
                'body': json.dumps({'error': 'Tenant validation failed'})
            }

        # 5. Transform payload for Snowflake
        snowflake_payload = transform_payload(body, tenant_id)

        # 6. Generate JWT token (cached for 55 minutes)
        jwt_token = get_jwt_token()

        # 7. Send to Snowpipe Streaming
        response = send_to_snowpipe_streaming(
            snowflake_payload,
            jwt_token,
            tenant_id
        )

        return {
            'statusCode': 200,
            'body': json.dumps({'message': 'Data ingested successfully'})
        }

    except Exception as e:
        print(f"Error processing request: {str(e)}")

        # Send to DLQ for retry
        send_to_dlq(event, str(e))

        return {
            'statusCode': 500,
            'body': json.dumps({'error': 'Internal server error'})
        }

def resolve_tenant_id(api_key):
    """
    Resolve tenant_id from API key using DynamoDB lookup
    """
    try:
        response = table.get_item(Key={'api_key': api_key})
        if 'Item' in response:
            return response['Item']['tenant_id']
        return None
    except Exception as e:
        print(f"Error resolving tenant: {str(e)}")
        return None

def get_jwt_token():
    """
    Generate or return cached JWT token for Snowflake authentication
    Token cached for 55 minutes (5-minute safety margin)
    """
    global jwt_token_cache, jwt_expiry_cache

    current_time = int(time.time())

    # Return cached token if still valid
    if jwt_token_cache and (jwt_expiry_cache - current_time) > 300:
        return jwt_token_cache

    # Generate new token
    private_key = get_private_key()

    account_name = "YOUR_SNOWFLAKE_ACCOUNT"
    username = "smdh_lambda_user"
    qualified_username = f"{account_name}.{username}".upper()

    now = int(time.time())
    expiry = now + 3600  # 1 hour

    payload = {
        "iss": qualified_username,
        "sub": qualified_username,
        "iat": now,
        "exp": expiry
    }

    # Sign with RS256
    token = jwt.encode(payload, private_key, algorithm="RS256")

    # Cache token
    jwt_token_cache = token
    jwt_expiry_cache = expiry

    return token

def get_private_key():
    """
    Retrieve Snowflake private key from Secrets Manager
    Cached in Lambda memory across invocations
    """
    global private_key_cache

    if private_key_cache is not None:
        return private_key_cache

    # Retrieve secret
    response = secrets_client.get_secret_value(
        SecretId="smdh/snowflake/private_key"
    )

    # Parse PEM-formatted private key
    private_key = serialization.load_pem_private_key(
        response['SecretString'].encode('utf-8'),
        password=None,
        backend=default_backend()
    )

    # Cache for subsequent invocations
    private_key_cache = private_key
    return private_key

def transform_payload(body, tenant_id):
    """
    Transform gateway payload to Snowflake schema
    """
    return {
        'tenant_id': tenant_id,
        'sensor_id': body['devEUI'],
        'sensor_type': infer_sensor_type(body),
        'timestamp': body['rxInfo'][0]['time'],
        'payload': body['object'],
        'device_metadata': {
            'gateway_id': body['rxInfo'][0]['gatewayID'],
            'rssi': body['rxInfo'][0]['rssi'],
            'snr': body['rxInfo'][0]['loRaSNR']
        },
        'source_system': 'lorawan_gateway',
        'message_id': f"{body['devEUI']}_{body['rxInfo'][0]['time']}"
    }

def infer_sensor_type(body):
    """
    Infer sensor type from payload structure
    """
    obj = body.get('object', {})

    if 'power' in obj or 'energy' in obj or 'voltage' in obj:
        return 'ENERGY'
    elif 'co2' in obj or 'voc' in obj or 'pm25' in obj:
        return 'AIR_QUALITY'
    elif 'state' in obj or 'utilization' in obj:
        return 'MACHINE'
    else:
        return 'GENERIC'

def send_to_snowpipe_streaming(payload, jwt_token, tenant_id):
    """
    Send data to Snowpipe Streaming REST API
    """
    url = f"https://{SNOWFLAKE_ACCOUNT}.snowflakecomputing.com/api/v2/snowpipe/streaming"

    headers = {
        'Authorization': f'Bearer {jwt_token}',
        'Content-Type': 'application/json'
    }

    data = {
        'channel': f'smdh_channel_{tenant_id}',
        'rows': [payload]
    }

    response = requests.post(url, headers=headers, json=data, timeout=25)
    response.raise_for_status()

    return response.json()

def send_to_dlq(event, error_message):
    """
    Send failed messages to SQS Dead Letter Queue
    """
    sqs = boto3.client('sqs', region_name='eu-west-2')

    sqs.send_message(
        QueueUrl=DLQ_URL,
        MessageBody=json.dumps({
            'event': event,
            'error': error_message,
            'timestamp': time.time()
        })
    )
```

**Lambda Configuration:**

```yaml
Function Name: smdh-ingestion-lambda
Runtime: python3.12
Architecture: arm64
Memory: 512 MB
Timeout: 30 seconds
Environment Variables:
  - SNOWFLAKE_ACCOUNT: your_account_identifier
  - DLQ_URL: https://sqs.eu-west-2.amazonaws.com/123456789/smdh-dlq
IAM Role:
  - secretsmanager:GetSecretValue (smdh/snowflake/private_key)
  - dynamodb:GetItem (smdh_api_key_mapping)
  - sqs:SendMessage (smdh-dlq)
  - logs:CreateLogGroup, logs:CreateLogStream, logs:PutLogEvents
VPC: No (public Snowflake endpoint)
Reserved Concurrency: 100
```

---

## 3.8 Data Flow Examples

### 3.8.1 MQTT Sensor Data Flow

```
1. Sensor → Gateway (LoRaWAN)
   └─ Protocol: LoRaWAN 868 MHz
   └─ Latency: <100ms

2. Gateway → IoT Core (MQTT)
   └─ Protocol: MQTT v3.1.1/v5
   └─ Authentication: X.509 certificates
   └─ QoS: 1 (at-least-once)

3. IoT Core → Kinesis
   └─ Via IoT Rules Engine
   └─ Partitioned by tenant_id
   └─ Buffering for ordering

4. Kinesis → Snowflake
   └─ Openflow Connector or Snowpipe
   └─ Batch ingestion
   └─ Automatic schema detection

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
TOTAL LATENCY: 5-15 seconds
```

### 3.8.2 HTTP API Data Flow

```
1. System → API Gateway (HTTPS POST)
   └─ Authentication: API key
   └─ Rate limiting applied

2. API Gateway → Lambda
   └─ Validation layer
   └─ Multi-tenant checks

3. Lambda → Snowpipe Streaming
   └─ JWT authentication
   └─ Direct ingestion

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
TOTAL LATENCY: 1-5 seconds
```

### 3.8.3 File Upload Data Flow

```
1. User → Streamlit Portal
   └─ SSO authentication
   └─ File selection

2. Streamlit → Snowflake Stage
   └─ Direct write
   └─ Encrypted storage

3. Snowpipe → Raw Tables
   └─ Auto-ingest
   └─ Schema inference

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
TOTAL LATENCY: 10 seconds - 3 minutes
```

## 3.9 Error Handling and Reliability

**Error Handling Strategy:**

| Error Type               | Detection         | Handling                               | Recovery                             |
| ------------------------ | ----------------- | -------------------------------------- | ------------------------------------ |
| **Invalid API Key**      | API Gateway       | 403 response immediately               | Admin corrects gateway config        |
| **Rate Limit Exceeded**  | API Gateway       | 429 response with Retry-After header   | Gateway auto-retries after delay     |
| **Tenant Mismatch**      | Lambda validation | 403 + send to DLQ + alert              | Investigate API key configuration    |
| **DynamoDB Throttle**    | Lambda            | Exponential backoff retry (3 attempts) | Auto-scales with On-Demand billing   |
| **JWT Generation Fail**  | Lambda            | Retry + fallback to new token          | Alert if Secrets Manager unavailable |
| **Snowpipe Unavailable** | Lambda            | Retry 3× + send to DLQ                 | Manual DLQ replay after recovery     |
| **Lambda Timeout**       | AWS               | Automatic retry (2×)                   | Alert if persistent failures         |

**Dead Letter Queue Processing:**

```python
"""
DLQ Processor Lambda (triggered manually or scheduled)
Purpose: Replay failed messages after issue resolution
"""

def process_dlq_messages(event, context):
    sqs = boto3.client('sqs')

    # Receive batch of messages
    response = sqs.receive_message(
        QueueUrl=DLQ_URL,
        MaxNumberOfMessages=10,
        WaitTimeSeconds=5
    )

    for message in response.get('Messages', []):
        try:
            # Parse failed message
            body = json.loads(message['Body'])
            original_event = body['event']

            # Retry ingestion
            lambda_handler(original_event, context)

            # Delete from DLQ on success
            sqs.delete_message(
                QueueUrl=DLQ_URL,
                ReceiptHandle=message['ReceiptHandle']
            )

        except Exception as e:
            print(f"Failed to replay message: {str(e)}")
            # Leave in DLQ for manual investigation
```

---

## 4. Snowflake Data Platform

### 4.1 Database Architecture

The Snowflake platform uses a **database-per-tenant** architecture for strongest multi-tenant isolation:

```
Snowflake Account: smdh_production
├─ Database: smdh_tenant_company_a
│  ├─ Schema: raw
│  │  └─ Table: sensor_readings (VARIANT payload)
│  ├─ Schema: normalized
│  │  └─ Dynamic Table: sensor_readings_normalized
│  ├─ Schema: aggregated
│  │  ├─ Dynamic Table: machine_utilization_hourly
│  │  ├─ Dynamic Table: air_quality_current
│  │  └─ Dynamic Table: production_flow_analysis
│  └─ Schema: analytics
│     ├─ View: dashboard_metrics
│     └─ View: ml_predictions
│
├─ Database: smdh_tenant_company_b
│  └─ (same schema structure)
│
└─ Database: smdh_shared
   ├─ Schema: config
   │  └─ Table: tenant_configuration
   └─ Schema: monitoring
      └─ Table: ingestion_metrics
```

**Benefits of Database-Level Segregation:**

1. **Fail-Closed Security**: Incorrect database name → SQL error (not data leak)
2. **Independent Operations**: Tenant-specific maintenance without affecting others
3. **Clear Compliance**: Physical separation for regulatory requirements
4. **Surgical Incident Response**: Isolated tenant without platform-wide impact
5. **Independent Retention**: Per-tenant Time Travel and data retention policies

### 4.2 Data Model

**Raw Sensor Readings Table:**

```sql
-- Raw ingestion table (per tenant database)
CREATE OR REPLACE TABLE smdh_tenant_${TENANT_ID}.raw.sensor_readings (
    -- Sensor identification
    sensor_id VARCHAR(100) NOT NULL,
    sensor_type VARCHAR(50) NOT NULL, -- 'MACHINE', 'AIR_QUALITY', 'ENERGY', 'RFID'

    -- Temporal
    timestamp TIMESTAMP_NTZ NOT NULL,

    -- Raw payload - flexible schema
    payload VARIANT NOT NULL,

    -- Metadata
    device_metadata VARIANT,
    ingestion_timestamp TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),

    -- Data lineage
    source_system VARCHAR(100) DEFAULT 'lorawan_gateway',
    message_id VARCHAR(255) NOT NULL,

    PRIMARY KEY (sensor_id, timestamp, message_id)
)
CLUSTER BY (sensor_type, DATE_TRUNC('day', timestamp))
ENABLE_SCHEMA_EVOLUTION = TRUE
COMMENT = 'Raw sensor readings with VARIANT payload for flexible schema';

-- Stream for change data capture
CREATE OR REPLACE STREAM smdh_tenant_${TENANT_ID}.raw.sensor_readings_stream
ON TABLE smdh_tenant_${TENANT_ID}.raw.sensor_readings
APPEND_ONLY = TRUE
COMMENT = 'CDC stream for triggering downstream transformations';
```

**Normalized Sensor Readings (Dynamic Table):**

```sql
-- Normalized readings with extracted metrics
CREATE OR REPLACE DYNAMIC TABLE smdh_tenant_${TENANT_ID}.normalized.sensor_readings_normalized
TARGET_LAG = '1 minute'
WAREHOUSE = streaming_wh
AS
SELECT
    sensor_id,
    sensor_type,
    timestamp,

    -- Extract metrics from VARIANT payload
    f.key::STRING as metric_key,
    f.value::FLOAT as metric_value,

    -- Quality and context
    payload:quality_score::FLOAT as quality_score,
    device_metadata,
    ingestion_timestamp,
    source_system,
    message_id
FROM smdh_tenant_${TENANT_ID}.raw.sensor_readings,
LATERAL FLATTEN(input => payload) f
WHERE quality_score > 0.7 OR quality_score IS NULL;
```

**Machine Utilization Aggregations:**

```sql
-- Hourly machine utilisation metrics
CREATE OR REPLACE DYNAMIC TABLE smdh_tenant_${TENANT_ID}.aggregated.machine_utilization_hourly
TARGET_LAG = '5 minutes'
WAREHOUSE = analytics_wh
AS
SELECT
    sensor_id as machine_id,
    DATE_TRUNC('hour', timestamp) as hour,

    -- Aggregated metrics
    AVG(CASE WHEN metric_key = 'utilization' THEN metric_value END) as avg_utilization,
    SUM(CASE WHEN metric_key = 'energy_kwh' THEN metric_value END) as total_energy_kwh,
    COUNT(DISTINCT CASE WHEN metric_key = 'state_change' THEN message_id END) as state_changes,
    MAX(CASE WHEN metric_key = 'cycle_count' THEN metric_value::INTEGER END) as cycle_count,

    -- Availability calculation
    SUM(CASE WHEN metric_key = 'running' THEN metric_value ELSE 0 END) / COUNT(*) * 100 as availability_pct,

    -- Quality metrics
    AVG(quality_score) as avg_quality,
    COUNT(*) as reading_count
FROM smdh_tenant_${TENANT_ID}.normalized.sensor_readings_normalized
WHERE sensor_type = 'MACHINE'
GROUP BY 1, 2;
```

**Air Quality with Anomaly Detection:**

```sql
-- Current air quality with Snowflake Cortex ML anomaly detection
CREATE OR REPLACE DYNAMIC TABLE smdh_tenant_${TENANT_ID}.aggregated.air_quality_current
TARGET_LAG = '1 minute'
WAREHOUSE = streaming_wh
AS
WITH latest_readings AS (
    SELECT
        sensor_id as location_id,
        timestamp,
        MAX(CASE WHEN metric_key = 'co2_ppm' THEN metric_value END) as co2_level,
        MAX(CASE WHEN metric_key = 'voc_ppb' THEN metric_value END) as voc_level,
        MAX(CASE WHEN metric_key = 'pm25_ugm3' THEN metric_value END) as pm25_level,
        MAX(CASE WHEN metric_key = 'temperature_c' THEN metric_value END) as temperature,
        MAX(CASE WHEN metric_key = 'humidity_pct' THEN metric_value END) as humidity
    FROM smdh_tenant_${TENANT_ID}.normalized.sensor_readings_normalized
    WHERE sensor_type = 'AIR_QUALITY'
      AND timestamp > DATEADD(minute, -10, CURRENT_TIMESTAMP())
    GROUP BY sensor_id, timestamp
)
SELECT
    location_id,
    timestamp,
    co2_level,
    voc_level,
    pm25_level,
    temperature,
    humidity,

    -- Anomaly detection using Snowflake Cortex ML
    SNOWFLAKE.ML.DETECT_ANOMALIES(
        pm25_level
        OVER (PARTITION BY location_id
              ORDER BY timestamp
              ROWS BETWEEN 60 PRECEDING AND CURRENT ROW)
    ) as pm25_anomaly_score,

    -- Calculate Air Quality Index
    CASE
        WHEN pm25_level > 55 THEN 'Poor'
        WHEN co2_level > 1000 THEN 'Moderate'
        WHEN voc_level > 500 THEN 'Moderate'
        ELSE 'Good'
    END as air_quality_index
FROM latest_readings;
```

### 4.3 Task-Based Orchestration

**ETL Task DAG:**

```sql
-- Root task: Data quality validation
CREATE OR REPLACE TASK smdh_tenant_${TENANT_ID}.raw.task_validate_data_quality
    WAREHOUSE = etl_wh
    SCHEDULE = '1 MINUTE'
    WHEN SYSTEM$STREAM_HAS_DATA('smdh_tenant_${TENANT_ID}.raw.sensor_readings_stream')
AS
    CALL smdh_tenant_${TENANT_ID}.raw.sp_validate_sensor_data();

-- Child task: Detect anomalies using Cortex ML
CREATE OR REPLACE TASK smdh_tenant_${TENANT_ID}.raw.task_detect_anomalies
    WAREHOUSE = ml_wh
    AFTER smdh_tenant_${TENANT_ID}.raw.task_validate_data_quality
AS
    CALL smdh_tenant_${TENANT_ID}.analytics.sp_run_anomaly_detection();

-- Child task: Generate threshold alerts
CREATE OR REPLACE TASK smdh_tenant_${TENANT_ID}.raw.task_generate_alerts
    WAREHOUSE = etl_wh
    AFTER smdh_tenant_${TENANT_ID}.raw.task_detect_anomalies
AS
    CALL smdh_tenant_${TENANT_ID}.analytics.sp_check_threshold_alerts();

-- Resume task DAG (bottom-up)
ALTER TASK smdh_tenant_${TENANT_ID}.raw.task_generate_alerts RESUME;
ALTER TASK smdh_tenant_${TENANT_ID}.raw.task_detect_anomalies RESUME;
ALTER TASK smdh_tenant_${TENANT_ID}.raw.task_validate_data_quality RESUME;
```

**Data Validation Stored Procedure:**

```sql
CREATE OR REPLACE PROCEDURE smdh_tenant_${TENANT_ID}.raw.sp_validate_sensor_data()
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.10'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'validate_data'
AS
$$
def validate_data(session):
    from snowflake.snowpark.functions import col, when, current_timestamp

    # Read from stream
    stream_df = session.table("raw.sensor_readings_stream")

    # Apply validation rules
    validated = stream_df.with_column(
        'data_quality_flags',
        when(
            (col('payload').is_null()) |
            (col('timestamp') > current_timestamp()),
            'INVALID'
        ).when(
            col('sensor_id').is_null(),
            'MISSING_SENSOR_ID'
        ).otherwise('VALID')
    )

    # Filter only valid records for downstream processing
    valid_records = validated.filter(col('data_quality_flags') == 'VALID')

    # Log invalid records to audit table
    invalid_records = validated.filter(col('data_quality_flags') != 'VALID')
    if invalid_records.count() > 0:
        invalid_records.write.mode('append').save_as_table('raw.invalid_readings_audit')

    return f"Validated {valid_records.count()} valid records, {invalid_records.count()} invalid"
$$;
```

### 4.4 Compute Resources

**Warehouse Configuration:**

```sql
-- Streaming warehouse for Snowpipe and real-time Dynamic Tables
CREATE OR REPLACE WAREHOUSE streaming_wh
    WAREHOUSE_SIZE = 'SMALL'
    MIN_CLUSTER_COUNT = 1
    MAX_CLUSTER_COUNT = 2
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = FALSE
    COMMENT = 'Always-on warehouse for streaming ingestion and real-time aggregations';

-- ETL warehouse for Task execution
CREATE OR REPLACE WAREHOUSE etl_wh
    WAREHOUSE_SIZE = 'MEDIUM'
    MIN_CLUSTER_COUNT = 1
    MAX_CLUSTER_COUNT = 3
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE
    COMMENT = 'Auto-scaling warehouse for ETL tasks and data transformations';

-- Analytics warehouse for BI queries (Power BI, Streamlit)
CREATE OR REPLACE WAREHOUSE analytics_wh
    WAREHOUSE_SIZE = 'LARGE'
    MIN_CLUSTER_COUNT = 1
    MAX_CLUSTER_COUNT = 5
    SCALING_POLICY = 'STANDARD'
    AUTO_SUSPEND = 300
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE
    COMMENT = 'Multi-cluster warehouse for concurrent BI queries';

-- ML warehouse for Cortex ML workloads
CREATE OR REPLACE WAREHOUSE ml_wh
    WAREHOUSE_SIZE = 'LARGE'
    MIN_CLUSTER_COUNT = 1
    MAX_CLUSTER_COUNT = 2
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE
    COMMENT = 'Dedicated warehouse for machine learning workloads';
```

**Warehouse Usage Patterns:**

- **Streaming Warehouse**: Continuous ingestion workload
- **ETL Warehouse**: Task execution and data transformations
- **Analytics Warehouse**: BI tool queries and ad-hoc analysis
- **ML Warehouse**: Cortex ML functions and model execution

---

## 5. Analytics and Visualisation

### 5.1 Snowflake Streamlit Portal

Snowflake Streamlit provides a native Python-based web application framework that runs entirely within the Snowflake environment.

**Key Benefits:**

- **Native Integration**: Direct access to Snowflake data without external APIs
- **Unified Identity**: Uses Snowflake IAM for authentication and authorisation
- **Rapid Development**: Python-based framework with extensive widget library
- **Automatic Scaling**: Managed by Snowflake, no infrastructure to deploy
- **Row-Level Security**: Inherits Snowflake RBAC and row access policies

**Portal Architecture:**

```
Snowflake Streamlit App:
├─ Authentication: Snowflake IAM (SSO via SAML)
├─ Authorization: Snowflake RBAC roles
├─ Data Access: Direct SQL queries (inherits RLS)
├─ File Uploads: Streamlit file_uploader → Snowflake stages
├─ Dashboards: Plotly/Altair visualisations
└─ Session State: Managed by Streamlit framework
```

**Example Streamlit App Structure:**

```python
"""
SMDH Streamlit Portal
Main application entry point
"""

import streamlit as st
import pandas as pd
from snowflake.snowpark.context import get_active_session

# Get Snowflake session (automatically authenticated)
session = get_active_session()

# Set page config
st.set_page_config(
    page_title="SMDH Manufacturing Analytics",
    page_icon="",
    layout="wide",
    initial_sidebar_state="expanded"
)

# Main navigation
st.sidebar.title("SMDH Portal")
page = st.sidebar.radio(
    "Navigation",
    ["Dashboard", "Machine Utilization", "Air Quality", "Job Tracking", "File Upload", "Reports"]
)

# Get current user and tenant context
current_user = session.sql("SELECT CURRENT_USER()").collect()[0][0]
current_role = session.sql("SELECT CURRENT_ROLE()").collect()[0][0]

# Extract tenant_id from role (e.g., tenant_company_a_user_role → company_a)
if 'tenant_' in current_role.lower():
    tenant_id = current_role.lower().split('tenant_')[1].split('_')[0]
else:
    tenant_id = None

st.sidebar.write(f"**User:** {current_user}")
st.sidebar.write(f"**Role:** {current_role}")
st.sidebar.write(f"**Tenant:** {tenant_id or 'N/A'}")

# Page routing
if page == "Dashboard":
    import pages.dashboard as dashboard
    dashboard.render(session, tenant_id)

elif page == "Machine Utilization":
    import pages.machine_utilization as machine
    machine.render(session, tenant_id)

elif page == "Air Quality":
    import pages.air_quality as air
    air.render(session, tenant_id)

elif page == "Job Tracking":
    import pages.job_tracking as jobs
    jobs.render(session, tenant_id)

elif page == "File Upload":
    import pages.file_upload as upload
    upload.render(session, tenant_id)

elif page == "Reports":
    import pages.reports as reports
    reports.render(session, tenant_id)
```

**Dashboard Page Example:**

```python
"""
pages/dashboard.py
Main dashboard with key metrics
"""

import streamlit as st
import plotly.express as px
from datetime import datetime, timedelta

def render(session, tenant_id):
    st.title(" Manufacturing Dashboard")

    if not tenant_id:
        st.error("Access denied: No tenant context available")
        return

    # Date range selector
    col1, col2 = st.columns(2)
    with col1:
        start_date = st.date_input("Start Date", datetime.now() - timedelta(days=7))
    with col2:
        end_date = st.date_input("End Date", datetime.now())

    # Fetch key metrics
    metrics_query = f"""
    SELECT
        COUNT(DISTINCT machine_id) as total_machines,
        AVG(avg_utilization) as avg_utilization,
        SUM(total_energy_kwh) as total_energy,
        COUNT(*) as total_hours
    FROM smdh_tenant_{tenant_id}.aggregated.machine_utilization_hourly
    WHERE hour BETWEEN '{start_date}' AND '{end_date}'
    """

    metrics = session.sql(metrics_query).to_pandas()

    # Display KPI cards
    col1, col2, col3, col4 = st.columns(4)

    with col1:
        st.metric(
            label="Total Machines",
            value=int(metrics['TOTAL_MACHINES'].iloc[0])
        )

    with col2:
        st.metric(
            label="Avg Utilization",
            value=f"{metrics['AVG_UTILIZATION'].iloc[0]:.1f}%"
        )

    with col3:
        st.metric(
            label="Total Energy",
            value=f"{metrics['TOTAL_ENERGY'].iloc[0]:.1f} kWh"
        )

    with col4:
        st.metric(
            label="Operating Hours",
            value=int(metrics['TOTAL_HOURS'].iloc[0])
        )

    # Utilization trend chart
    st.subheader("Machine Utilization Trend")

    trend_query = f"""
    SELECT
        hour,
        machine_id,
        avg_utilization
    FROM smdh_tenant_{tenant_id}.aggregated.machine_utilization_hourly
    WHERE hour BETWEEN '{start_date}' AND '{end_date}'
    ORDER BY hour
    """

    trend_data = session.sql(trend_query).to_pandas()

    fig = px.line(
        trend_data,
        x='HOUR',
        y='AVG_UTILIZATION',
        color='MACHINE_ID',
        title='Hourly Machine Utilization',
        labels={'AVG_UTILIZATION': 'Utilization (%)', 'HOUR': 'Time'}
    )

    st.plotly_chart(fig, use_container_width=True)

    # Air quality status
    st.subheader("Current Air Quality")

    air_query = f"""
    SELECT
        location_id,
        co2_level,
        pm25_level,
        temperature,
        humidity,
        air_quality_index
    FROM smdh_tenant_{tenant_id}.aggregated.air_quality_current
    ORDER BY timestamp DESC
    LIMIT 10
    """

    air_data = session.sql(air_query).to_pandas()

    st.dataframe(
        air_data,
        use_container_width=True,
        hide_index=True
    )
```

**File Upload Page:**

```python
"""
pages/file_upload.py
Batch file upload to Snowflake stages
"""

import streamlit as st
import pandas as pd
from io import BytesIO

def render(session, tenant_id):
    st.title(" File Upload")

    if not tenant_id:
        st.error("Access denied: No tenant context available")
        return

    st.write("Upload CSV, Excel, or JSON files for batch processing")

    # File uploader
    uploaded_file = st.file_uploader(
        "Choose a file",
        type=['csv', 'xlsx', 'json'],
        help="Supported formats: CSV, Excel, JSON"
    )

    if uploaded_file is not None:
        # Display file info
        st.write(f"**Filename:** {uploaded_file.name}")
        st.write(f"**Size:** {uploaded_file.size / 1024:.2f} KB")

        # Preview data
        if uploaded_file.name.endswith('.csv'):
            df = pd.read_csv(uploaded_file)
        elif uploaded_file.name.endswith('.xlsx'):
            df = pd.read_excel(uploaded_file)
        elif uploaded_file.name.endswith('.json'):
            df = pd.read_json(uploaded_file)

        st.subheader("Data Preview")
        st.dataframe(df.head(10))

        # Upload button
        if st.button("Upload to Snowflake"):
            with st.spinner("Uploading..."):
                try:
                    # Write to Snowflake stage
                    stage_name = f"@smdh_tenant_{tenant_id}.raw.upload_stage"
                    table_name = f"smdh_tenant_{tenant_id}.raw.uploaded_files"

                    # Create Snowpark DataFrame and write to table
                    snowpark_df = session.create_dataframe(df)
                    snowpark_df.write.mode("append").save_as_table(table_name)

                    st.success(f" Successfully uploaded {len(df)} rows!")

                    # Trigger processing task
                    session.sql(f"""
                        EXECUTE TASK smdh_tenant_{tenant_id}.raw.task_process_uploaded_files
                    """).collect()

                    st.info(" File processing task triggered. Data will be available in 1-2 minutes.")

                except Exception as e:
                    st.error(f" Upload failed: {str(e)}")
```

### 5.2 Power BI Integration

Power BI connects to Snowflake using native DirectQuery or Import mode with Snowflake IAM authentication.

**Connection Configuration:**

```
Power BI Desktop:
├─ Data Source: Snowflake
├─ Server: your_account.snowflakecomputing.com
├─ Warehouse: analytics_wh
├─ Database: smdh_tenant_{tenant_id}
├─ Authentication: Microsoft Account (SSO via SAML)
├─ Connection Mode: DirectQuery (real-time) or Import (scheduled refresh)
└─ Row-Level Security: Inherited from Snowflake
```

**Power BI Service Configuration:**

```yaml
Workspace Settings:
  - Premium Capacity: P1 or higher
  - Gateway: Not required (cloud-to-cloud)
  - Refresh Schedule: Hourly (Import mode) or Real-time (DirectQuery)
  - Row-Level Security: Synchronized with Snowflake roles
  - Embedding: Enabled for multi-tenant portal
```

**Example Power BI Report Structure:**

```
SMDH Manufacturing Analytics.pbix
├─ Page 1: Executive Dashboard
│  ├─ Card: Total Machines
│  ├─ Card: Avg Utilization
│  ├─ Line Chart: Utilization Trend (7 days)
│  └─ Map: Machine Locations with Status
│
├─ Page 2: Machine Utilization
│  ├─ Table: Machine List with Metrics
│  ├─ Gantt Chart: Machine Timeline
│  ├─ Bar Chart: Energy Consumption by Machine
│  └─ Scatter: Utilization vs Energy Efficiency
│
├─ Page 3: Air Quality
│  ├─ Gauge: Current AQI by Location
│  ├─ Line Chart: CO2 Trend (24 hours)
│  ├─ Heatmap: PM2.5 by Location and Hour
│  └─ Table: Alert History
│
└─ Page 4: Job Tracking
   ├─ Sankey Diagram: Production Flow
   ├─ Bar Chart: Cycle Time by Station
   ├─ Table: Current Jobs in Progress
   └─ KPI: On-Time Completion Rate
```

**Power BI Tenant Isolation:**

```sql
-- Snowflake view for Power BI (enforces tenant context)
CREATE OR REPLACE SECURE VIEW smdh_tenant_${TENANT_ID}.analytics.v_powerbi_machine_metrics
AS
SELECT
    machine_id,
    hour,
    avg_utilization,
    total_energy_kwh,
    availability_pct,
    -- Add tenant_id for additional filtering
    '${TENANT_ID}' as tenant_id
FROM smdh_tenant_${TENANT_ID}.aggregated.machine_utilization_hourly;

-- Grant access to Power BI service user role
GRANT SELECT ON VIEW smdh_tenant_${TENANT_ID}.analytics.v_powerbi_machine_metrics
TO ROLE tenant_${TENANT_ID}_powerbi_role;
```

---

## 6. Security Architecture

### 6.1 Network Security

**Simplified Network Design:**

```
Internet
   ↓
AWS API Gateway (HTTPS only, TLS 1.3)
   ↓
AWS Lambda (No VPC - public Snowflake endpoint)
   ↓
Snowflake (HTTPS, TLS 1.3, optional PrivateLink)
   ↑
Power BI (HTTPS, TLS 1.3, cloud-to-cloud)
   ↑
Streamlit Portal (HTTPS, TLS 1.3, Snowflake-hosted)
```

**Security Controls:**

- All communication over HTTPS with TLS 1.3
- No public IP addresses or EC2 instances
- API Gateway regional endpoint (not edge-optimised)
- Optional: Snowflake PrivateLink for private connectivity
- Lambda in public subnet (no VPC egress costs)

### 6.2 Identity and Access Management

**Snowflake IAM Architecture:**

```
Snowflake Account: smdh_production
├─ Users:
│  ├─ Service Users:
│  │  ├─ smdh_lambda_user (key-pair auth, no password)
│  │  └─ smdh_powerbi_service (OAuth, no password)
│  │
│  └─ Human Users (SSO via SAML 2.0):
│     ├─ john.smith@company-a.com (tenant_company_a_admin_role)
│     ├─ jane.doe@company-a.com (tenant_company_a_user_role)
│     └─ admin@smdh-platform.com (accountadmin)
│
├─ Roles (Hierarchical):
│  ├─ ACCOUNTADMIN (platform administrators)
│  ├─ SYSADMIN (system operations)
│  ├─ SECURITYADMIN (security management)
│  │
│  ├─ tenant_company_a_admin_role
│  │  ├─ Full access to smdh_tenant_company_a database
│  │  ├─ Can manage tenant users
│  │  └─ Can configure alerts and reports
│  │
│  ├─ tenant_company_a_user_role
│  │  ├─ Read access to analytics views
│  │  ├─ Can run Streamlit apps
│  │  └─ Can view Power BI reports
│  │
│  ├─ tenant_company_a_powerbi_role
│  │  ├─ Read access to Power BI views
│  │  └─ Uses analytics_wh warehouse
│  │
│  └─ smdh_ingest_role_company_a
│     ├─ INSERT into raw.sensor_readings
│     └─ Uses streaming_wh warehouse
│
└─ Network Policies:
   ├─ Block IP ranges (if needed)
   └─ Restrict to specific regions
```

**Role Hierarchy SQL:**

```sql
-- Create role hierarchy for tenant
CREATE ROLE IF NOT EXISTS tenant_${TENANT_ID}_admin_role;
CREATE ROLE IF NOT EXISTS tenant_${TENANT_ID}_user_role;
CREATE ROLE IF NOT EXISTS tenant_${TENANT_ID}_powerbi_role;
CREATE ROLE IF NOT EXISTS smdh_ingest_role_${TENANT_ID};

-- Grant role hierarchy (admin includes user privileges)
GRANT ROLE tenant_${TENANT_ID}_user_role TO ROLE tenant_${TENANT_ID}_admin_role;

-- Grant database access to admin role
GRANT USAGE ON DATABASE smdh_tenant_${TENANT_ID} TO ROLE tenant_${TENANT_ID}_admin_role;
GRANT ALL PRIVILEGES ON SCHEMA smdh_tenant_${TENANT_ID}.raw TO ROLE tenant_${TENANT_ID}_admin_role;
GRANT ALL PRIVILEGES ON SCHEMA smdh_tenant_${TENANT_ID}.normalized TO ROLE tenant_${TENANT_ID}_admin_role;
GRANT ALL PRIVILEGES ON SCHEMA smdh_tenant_${TENANT_ID}.aggregated TO ROLE tenant_${TENANT_ID}_admin_role;
GRANT ALL PRIVILEGES ON SCHEMA smdh_tenant_${TENANT_ID}.analytics TO ROLE tenant_${TENANT_ID}_admin_role;

-- Grant read-only access to user role
GRANT USAGE ON DATABASE smdh_tenant_${TENANT_ID} TO ROLE tenant_${TENANT_ID}_user_role;
GRANT USAGE ON SCHEMA smdh_tenant_${TENANT_ID}.analytics TO ROLE tenant_${TENANT_ID}_user_role;
GRANT SELECT ON ALL VIEWS IN SCHEMA smdh_tenant_${TENANT_ID}.analytics TO ROLE tenant_${TENANT_ID}_user_role;

-- Grant Power BI role access to specific views
GRANT USAGE ON DATABASE smdh_tenant_${TENANT_ID} TO ROLE tenant_${TENANT_ID}_powerbi_role;
GRANT USAGE ON SCHEMA smdh_tenant_${TENANT_ID}.analytics TO ROLE tenant_${TENANT_ID}_powerbi_role;
GRANT SELECT ON ALL VIEWS IN SCHEMA smdh_tenant_${TENANT_ID}.analytics TO ROLE tenant_${TENANT_ID}_powerbi_role;
GRANT USAGE ON WAREHOUSE analytics_wh TO ROLE tenant_${TENANT_ID}_powerbi_role;

-- Grant ingestion role (Lambda service user)
GRANT USAGE ON DATABASE smdh_tenant_${TENANT_ID} TO ROLE smdh_ingest_role_${TENANT_ID};
GRANT USAGE ON SCHEMA smdh_tenant_${TENANT_ID}.raw TO ROLE smdh_ingest_role_${TENANT_ID};
GRANT INSERT ON TABLE smdh_tenant_${TENANT_ID}.raw.sensor_readings TO ROLE smdh_ingest_role_${TENANT_ID};
GRANT USAGE ON WAREHOUSE streaming_wh TO ROLE smdh_ingest_role_${TENANT_ID};
```

**SSO Configuration (SAML 2.0):**

```sql
-- Configure SAML SSO for tenant (using Azure AD example)
CREATE SECURITY INTEGRATION saml_company_a
    TYPE = SAML2
    ENABLED = TRUE
    SAML2_ISSUER = 'https://sts.windows.net/{tenant-id}/'
    SAML2_SSO_URL = 'https://login.microsoftonline.com/{tenant-id}/saml2'
    SAML2_PROVIDER = 'CUSTOM'
    SAML2_X509_CERT = '-----BEGIN CERTIFICATE-----
MIIDdzCCAl+gAwIBAgIEAgAAuTANBgkqhkiG9w0BAQUFADBaMQswCQYDVQQGEwJJ...
-----END CERTIFICATE-----'
    SAML2_SP_INITIATED_LOGIN_PAGE_LABEL = 'Company A Login'
    SAML2_ENABLE_SP_INITIATED = TRUE
    SAML2_SNOWFLAKE_ISSUER_URL = 'https://smdh_production.snowflakecomputing.com'
    SAML2_SNOWFLAKE_ACS_URL = 'https://smdh_production.snowflakecomputing.com/fed/login';

-- Create user with SSO and assign role
CREATE USER IF NOT EXISTS "john.smith@company-a.com"
    LOGIN_NAME = 'john.smith@company-a.com'
    DISPLAY_NAME = 'John Smith'
    EMAIL = 'john.smith@company-a.com'
    DEFAULT_ROLE = tenant_company_a_admin_role
    DEFAULT_WAREHOUSE = analytics_wh
    MUST_CHANGE_PASSWORD = FALSE;

GRANT ROLE tenant_company_a_admin_role TO USER "john.smith@company-a.com";
```

### 6.3 Data Security

**Encryption:**

- **At Rest**: Automatic AES-256 encryption (Snowflake managed keys)
- **In Transit**: TLS 1.3 for all connections
- **Optional**: Tri-Secret Secure (customer-managed keys in AWS KMS)

**Data Masking (PII Protection):**

```sql
-- Create masking policy for email addresses
CREATE OR REPLACE MASKING POLICY email_mask AS (val STRING) RETURNS STRING ->
    CASE
        WHEN CURRENT_ROLE() IN ('ACCOUNTADMIN', 'tenant_company_a_admin_role') THEN val
        ELSE REGEXP_REPLACE(val, '(.{2})[^@]+@', '\\1***@')
    END;

-- Apply to columns containing PII
ALTER TABLE smdh_tenant_company_a.raw.operator_info
    MODIFY COLUMN email SET MASKING POLICY email_mask;
```

**Audit Logging:**

```sql
-- Enable query and access history
ALTER ACCOUNT SET ENABLE_ACCOUNT_DATABASE_QUERY_HISTORY = TRUE;

-- Query audit trail (available for 1 year)
SELECT
    query_text,
    user_name,
    role_name,
    database_name,
    schema_name,
    start_time,
    execution_status
FROM snowflake.account_usage.query_history
WHERE database_name = 'SMDH_TENANT_COMPANY_A'
  AND start_time > DATEADD(day, -7, CURRENT_TIMESTAMP())
ORDER BY start_time DESC;

-- Access history (for compliance audits)
SELECT
    user_name,
    query_start_time,
    direct_objects_accessed,
    base_objects_accessed
FROM snowflake.account_usage.access_history
WHERE query_start_time > DATEADD(day, -30, CURRENT_TIMESTAMP())
  AND ARRAY_CONTAINS('SMDH_TENANT_COMPANY_A'::VARIANT, direct_objects_accessed);
```

---

## 7. Multi-Tenancy Strategy

### 7.1 Database-Level Segregation

The SMDH platform uses **database-per-tenant** architecture for maximum security and operational isolation.

**Security Guarantees:**

| Property                   | Implementation                  | Benefit                                |
| -------------------------- | ------------------------------- | -------------------------------------- |
| **Physical Isolation**     | Separate database per tenant    | No shared tables                       |
| **INSERT Validation**      | Implicit (database name in DDL) | Incorrect database → SQL error         |
| **Fail Mode**              | **Fail Closed**                 | Lambda bug causes error, not data leak |
| **Compliance Audit**       | Clear separation                | Meets GDPR, ISO 27001 requirements     |
| **Incident Response**      | Surgical tenant isolation       | No platform-wide impact                |
| **Independent Operations** | Per-tenant maintenance windows  | Zero cross-tenant impact               |

**Tenant Onboarding Procedure:**

```sql
-- 1. Create tenant database
CREATE DATABASE IF NOT EXISTS smdh_tenant_${TENANT_ID}
    DATA_RETENTION_TIME_IN_DAYS = 90
    COMMENT = 'Tenant: ${TENANT_NAME}';

-- 2. Create schemas
CREATE SCHEMA IF NOT EXISTS smdh_tenant_${TENANT_ID}.raw;
CREATE SCHEMA IF NOT EXISTS smdh_tenant_${TENANT_ID}.normalized;
CREATE SCHEMA IF NOT EXISTS smdh_tenant_${TENANT_ID}.aggregated;
CREATE SCHEMA IF NOT EXISTS smdh_tenant_${TENANT_ID}.analytics;

-- 3. Create tables (sensor_readings, etc.)
-- (See Section 4.2 for complete table DDL)

-- 4. Create roles
CREATE ROLE IF NOT EXISTS tenant_${TENANT_ID}_admin_role;
CREATE ROLE IF NOT EXISTS tenant_${TENANT_ID}_user_role;
CREATE ROLE IF NOT EXISTS smdh_ingest_role_${TENANT_ID};

-- 5. Grant permissions
-- (See Section 6.2 for complete grants)

-- 6. Create service user for Lambda ingestion
CREATE USER IF NOT EXISTS smdh_lambda_${TENANT_ID}
    PASSWORD = NULL
    DEFAULT_ROLE = smdh_ingest_role_${TENANT_ID}
    DEFAULT_WAREHOUSE = streaming_wh;

-- Register public key for JWT authentication
ALTER USER smdh_lambda_${TENANT_ID}
    SET RSA_PUBLIC_KEY = '{PUBLIC_KEY}';

GRANT ROLE smdh_ingest_role_${TENANT_ID} TO USER smdh_lambda_${TENANT_ID};
```

### 7.2 Lambda Tenant Validation

**Multi-Tenant Validation Logic:**

The Lambda function enforces tenant isolation BEFORE data reaches Snowflake:

```python
def validate_tenant(api_key, payload):
    """
    CRITICAL SECURITY FUNCTION
    Validates that API key tenant matches payload tenant
    """
    # 1. Resolve tenant_id from API key (DynamoDB)
    api_key_tenant = resolve_tenant_id(api_key)

    if not api_key_tenant:
        log_security_violation("invalid_api_key", api_key[:10])
        return False, "Invalid API key"

    # 2. Extract tenant from payload
    payload_tenant = extract_tenant_from_payload(payload)

    # 3. CRITICAL: Compare tenants
    if api_key_tenant != payload_tenant:
        log_security_violation(
            "tenant_mismatch",
            {
                "api_key_tenant": api_key_tenant,
                "payload_tenant": payload_tenant,
                "api_key_prefix": api_key[:10]
            }
        )

        # Send to DLQ for investigation
        send_to_dlq(payload, f"Tenant mismatch: {api_key_tenant} vs {payload_tenant}")

        return False, "Tenant validation failed"

    # 4. Success - proceed with ingestion
    return True, api_key_tenant
```

**Security Benefits:**

- **Fail-Closed**: Validation failure blocks ingestion (403 error)
- **Early Detection**: Catches configuration errors before Snowflake
- **Audit Trail**: CloudWatch logs all validation failures
- **Investigation Support**: DLQ contains failed messages for forensics

### 7.3 Cost Attribution

**Snowflake Resource Monitors:**

```sql
-- Create resource monitor for tenant
CREATE OR REPLACE RESOURCE MONITOR tenant_${TENANT_ID}_monitor
    WITH CREDIT_QUOTA = 500  -- Monthly credit limit
    FREQUENCY = MONTHLY
    START_TIMESTAMP = CURRENT_TIMESTAMP()
    TRIGGERS
        ON 75 PERCENT DO NOTIFY
        ON 90 PERCENT DO NOTIFY
        ON 100 PERCENT DO SUSPEND
        ON 110 PERCENT DO SUSPEND_IMMEDIATE;

-- Assign to tenant warehouses
ALTER WAREHOUSE streaming_wh SET RESOURCE_MONITOR = tenant_${TENANT_ID}_monitor;
ALTER WAREHOUSE analytics_wh SET RESOURCE_MONITOR = tenant_${TENANT_ID}_monitor;
```

**Cost Tracking Query:**

```sql
-- Monthly cost breakdown by tenant
WITH tenant_costs AS (
    SELECT
        warehouse_name,
        CASE
            WHEN warehouse_name LIKE '%company_a%' THEN 'company_a'
            WHEN warehouse_name LIKE '%company_b%' THEN 'company_b'
            ELSE 'shared'
        END as tenant_id,
        SUM(credits_used) as credits_used,
        SUM(credits_used) * 3.00 as cost_gbp  -- £3 per credit
    FROM snowflake.account_usage.warehouse_metering_history
    WHERE start_time >= DATE_TRUNC('month', CURRENT_TIMESTAMP())
    GROUP BY warehouse_name, tenant_id
)
SELECT
    tenant_id,
    SUM(credits_used) as total_credits,
    SUM(cost_gbp) as total_cost_gbp
FROM tenant_costs
GROUP BY tenant_id
ORDER BY total_cost_gbp DESC;
```

---

## 8. Implementation Guide

### 8.1 Prerequisites

**Required Access:**

- AWS Account with Administrator access (or specific IAM permissions)
- Snowflake Account with ACCOUNTADMIN role
- Milesight UG65 gateway admin credentials
- Domain for API Gateway (optional custom domain)

**Required Tools:**

- AWS CLI v2+ (configured with credentials)
- Snowflake SnowSQL CLI
- Python 3.12+ (for Lambda development)
- Terraform v1.5+ (infrastructure as code)
- Git (version control)

### 8.2 Phase 1: AWS Infrastructure Deployment

**Step 1: Create Snowflake Private Key**

```bash
# Generate RSA-2048 key pair
openssl genrsa -out snowflake_private_key.pem 2048
openssl rsa -in snowflake_private_key.pem -pubout -out snowflake_public_key.pem

# Extract public key for Snowflake (single line, no headers)
grep -v "BEGIN PUBLIC KEY" snowflake_public_key.pem | \
  grep -v "END PUBLIC KEY" | \
  tr -d '\n' > snowflake_public_key_single_line.txt

# Store private key in AWS Secrets Manager
aws secretsmanager create-secret \
  --name smdh/snowflake/private_key \
  --secret-string file://snowflake_private_key.pem \
  --region eu-west-2

# Securely delete local key
shred -vfz -n 10 snowflake_private_key.pem
```

**Step 2: Deploy Lambda Function**

```bash
# Package Lambda dependencies
cd lambda
pip install -r requirements.txt -t package/
cd package
zip -r ../lambda_function.zip .
cd ..
zip -g lambda_function.zip lambda_function.py

# Create Lambda function
aws lambda create-function \
  --function-name smdh-ingestion-lambda \
  --runtime python3.12 \
  --architectures arm64 \
  --role arn:aws:iam::123456789:role/smdh-lambda-execution-role \
  --handler lambda_function.lambda_handler \
  --zip-file fileb://lambda_function.zip \
  --memory-size 512 \
  --timeout 30 \
  --environment Variables="{SNOWFLAKE_ACCOUNT=your_account,DLQ_URL=https://sqs.eu-west-2.amazonaws.com/123456789/smdh-dlq}" \
  --region eu-west-2
```

**Step 3: Create API Gateway**

```bash
# Create REST API
aws apigateway create-rest-api \
  --name smdh-ingestion-api \
  --region eu-west-2 \
  --endpoint-configuration types=REGIONAL

# Create /ingest resource and POST method
# (Use AWS Console or Terraform for detailed configuration)

# Create API key for tenant
API_KEY="smdh-prod-$(openssl rand -hex 32)"

aws apigateway create-api-key \
  --name smdh-tenant-company-a-prod \
  --enabled \
  --value "$API_KEY" \
  --region eu-west-2

# Deploy API to prod stage
aws apigateway create-deployment \
  --rest-api-id {api-id} \
  --stage-name prod \
  --region eu-west-2
```

**Step 4: Create DynamoDB Table**

```bash
# Create API key mapping table
aws dynamodb create-table \
  --table-name smdh_api_key_mapping \
  --attribute-definitions \
      AttributeName=api_key,AttributeType=S \
  --key-schema \
      AttributeName=api_key,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region eu-west-2

# Insert tenant mapping
aws dynamodb put-item \
  --table-name smdh_api_key_mapping \
  --item '{
    "api_key": {"S": "'$API_KEY'"},
    "tenant_id": {"S": "company_a"},
    "tenant_name": {"S": "Company A Manufacturing Ltd"},
    "status": {"S": "active"},
    "created_at": {"S": "'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'"}
  }' \
  --region eu-west-2
```

### 8.3 Phase 2: Snowflake Configuration

**Step 1: Create Service User**

```sql
-- Create service user for Lambda
CREATE USER IF NOT EXISTS smdh_lambda_user
    PASSWORD = NULL
    DEFAULT_ROLE = smdh_ingest_role
    DEFAULT_WAREHOUSE = streaming_wh
    COMMENT = 'Lambda service user for SMDH ingestion';

-- Register public key (from snowflake_public_key_single_line.txt)
ALTER USER smdh_lambda_user
    SET RSA_PUBLIC_KEY = 'MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA...';

-- Verify configuration
DESC USER smdh_lambda_user;
```

**Step 2: Create Warehouses**

```sql
-- Streaming warehouse
CREATE OR REPLACE WAREHOUSE streaming_wh
    WAREHOUSE_SIZE = 'SMALL'
    MIN_CLUSTER_COUNT = 1
    MAX_CLUSTER_COUNT = 2
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = FALSE;

-- ETL warehouse
CREATE OR REPLACE WAREHOUSE etl_wh
    WAREHOUSE_SIZE = 'MEDIUM'
    MIN_CLUSTER_COUNT = 1
    MAX_CLUSTER_COUNT = 3
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE;

-- Analytics warehouse
CREATE OR REPLACE WAREHOUSE analytics_wh
    WAREHOUSE_SIZE = 'LARGE'
    MIN_CLUSTER_COUNT = 1
    MAX_CLUSTER_COUNT = 5
    SCALING_POLICY = 'STANDARD'
    AUTO_SUSPEND = 300
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE;
```

**Step 3: Create Tenant Database**

```sql
-- Execute tenant onboarding script
-- (See Section 7.1 for complete SQL)

-- Create database
CREATE DATABASE IF NOT EXISTS smdh_tenant_company_a
    DATA_RETENTION_TIME_IN_DAYS = 90;

-- Create schemas
CREATE SCHEMA smdh_tenant_company_a.raw;
CREATE SCHEMA smdh_tenant_company_a.normalized;
CREATE SCHEMA smdh_tenant_company_a.aggregated;
CREATE SCHEMA smdh_tenant_company_a.analytics;

-- Create tables (see Section 4.2)
-- Create Dynamic Tables (see Section 4.2)
-- Create Tasks (see Section 4.3)
-- Create roles and grants (see Section 6.2)
```

### 8.4 Phase 3: Gateway Configuration

**UG65 Configuration Steps:**

1. **Access Gateway Web Interface**

   ```
   URL: http://192.168.1.1
   Username: admin
   Password: [gateway password]
   ```

2. **Navigate to Application**

   ```
   Path: Network Server > Application > [+] Add Application
   ```

3. **Configure Application**

   ```
   Name: company_a_production
   Description: SMDH - Company A
   Metadata: Enable (adds deviceEUI, deviceName to payload)
   Payload Codec: LoRaWAN (or custom JavaScript)
   ```

4. **Add HTTP Transmission**

   ```
   Protocol: HTTPS
   URL: https://{api-id}.execute-api.eu-west-2.amazonaws.com/prod/ingest
   Method: POST
   ```

5. **Configure Headers (CRITICAL)**

   ```
   Header 1:
     Name: x-api-key
     Value: smdh-prod-abc123def456... (from Step 4 of Phase 1)

   Header 2:
     Name: Content-Type
     Value: application/json
   ```

6. **Save and Test**
   ```
   Click: Save > Apply
   Click: Test button
   Expected: HTTP 200 OK response
   ```

### 8.5 Phase 4: Streamlit Portal Deployment

**Step 1: Create Streamlit App in Snowflake**

```sql
-- Create Streamlit app
CREATE STREAMLIT smdh_tenant_company_a.analytics.portal_app
    FROM = '@smdh_tenant_company_a.analytics.streamlit_stage'
    MAIN_FILE = 'app.py'
    QUERY_WAREHOUSE = analytics_wh
    TITLE = 'SMDH Manufacturing Portal'
    COMMENT = 'Main web portal for tenant Company A';

-- Grant access to tenant users
GRANT USAGE ON STREAMLIT smdh_tenant_company_a.analytics.portal_app
    TO ROLE tenant_company_a_user_role;
```

**Step 2: Upload Streamlit Code**

```bash
# Upload app files to Snowflake stage
snow stage put file://app.py @smdh_tenant_company_a.analytics.streamlit_stage
snow stage put file://pages/*.py @smdh_tenant_company_a.analytics.streamlit_stage/pages/
snow stage put file://requirements.txt @smdh_tenant_company_a.analytics.streamlit_stage
```

### 8.6 Phase 5: Power BI Configuration

**Step 1: Configure Snowflake Connector**

```
Power BI Desktop:
1. Get Data > Snowflake
2. Server: your_account.snowflakecomputing.com
3. Warehouse: analytics_wh
4. Authentication: Microsoft Account (SSO)
5. Advanced Options:
   - Role: tenant_company_a_powerbi_role
   - Connection Mode: DirectQuery
```

**Step 2: Create Report**

```
1. Select tables/views from smdh_tenant_company_a.analytics
2. Build visualisations
3. Configure RLS (inherited from Snowflake)
4. Publish to Power BI Service
5. Configure scheduled refresh (if using Import mode)
```

---

## 9. Operational Procedures

### 9.1 Monitoring and Alerting

**CloudWatch Dashboards:**

```json
{
  "widgets": [
    {
      "type": "metric",
      "properties": {
        "metrics": [
          ["AWS/ApiGateway", "Count", { "stat": "Sum" }],
          [".", "4XXError", { "stat": "Sum" }],
          [".", "5XXError", { "stat": "Sum" }]
        ],
        "period": 300,
        "stat": "Sum",
        "region": "eu-west-2",
        "title": "API Gateway Requests"
      }
    },
    {
      "type": "metric",
      "properties": {
        "metrics": [
          ["AWS/Lambda", "Invocations", { "stat": "Sum" }],
          [".", "Errors", { "stat": "Sum" }],
          [".", "Throttles", { "stat": "Sum" }],
          [".", "Duration", { "stat": "Average" }]
        ],
        "period": 300,
        "stat": "Sum",
        "region": "eu-west-2",
        "title": "Lambda Performance"
      }
    }
  ]
}
```

**Snowflake Monitoring Queries:**

```sql
-- Real-time ingestion rate
SELECT
    DATE_TRUNC('minute', ingestion_timestamp) as minute,
    COUNT(*) as records_ingested
FROM smdh_tenant_company_a.raw.sensor_readings
WHERE ingestion_timestamp > DATEADD(hour, -1, CURRENT_TIMESTAMP())
GROUP BY minute
ORDER BY minute DESC;

-- Task execution history
SELECT
    name,
    state,
    scheduled_time,
    completed_time,
    DATEDIFF('second', scheduled_time, completed_time) as duration_seconds,
    error_code,
    error_message
FROM snowflake.account_usage.task_history
WHERE name LIKE 'smdh_tenant_company_a%'
  AND scheduled_time > DATEADD(day, -1, CURRENT_TIMESTAMP())
ORDER BY scheduled_time DESC;

-- Warehouse credit usage (last 24 hours)
SELECT
    warehouse_name,
    SUM(credits_used) as credits_used,
    SUM(credits_used) * 3.00 as cost_gbp
FROM snowflake.account_usage.warehouse_metering_history
WHERE start_time > DATEADD(day, -1, CURRENT_TIMESTAMP())
  AND warehouse_name LIKE '%company_a%'
GROUP BY warehouse_name;
```

**Alert Configuration:**

```sql
-- Create alert for high error rate
CREATE OR REPLACE ALERT smdh_tenant_company_a.analytics.alert_high_error_rate
    WAREHOUSE = analytics_wh
    SCHEDULE = '5 MINUTE'
    IF (EXISTS (
        SELECT 1
        FROM smdh_tenant_company_a.raw.sensor_readings
        WHERE ingestion_timestamp > DATEADD(minute, -5, CURRENT_TIMESTAMP())
        GROUP BY sensor_id
        HAVING SUM(CASE WHEN payload IS NULL THEN 1 ELSE 0 END) > 10
    ))
    THEN
        CALL system$send_email(
            'smdh-alerts',
            'admin@company-a.com',
            'High Error Rate Detected',
            'More than 10 null payloads in last 5 minutes'
        );

-- Resume alert
ALTER ALERT smdh_tenant_company_a.analytics.alert_high_error_rate RESUME;
```

### 9.2 Incident Response Procedures

**High API Error Rate (4XX/5XX):**

1. **Detect**: CloudWatch alarm triggers
2. **Investigate**:

   ```bash
   # Check Lambda logs
   aws logs tail /aws/lambda/smdh-ingestion-lambda --follow

   # Check API Gateway logs
   aws logs tail /aws/apigateway/smdh-ingestion-api --follow
   ```

3. **Diagnose**:
   - 403 errors → API key issue or tenant validation failure
   - 429 errors → Rate limiting (check usage plan)
   - 500 errors → Lambda execution error
4. **Resolve**:
   - Incorrect API key → Update gateway configuration
   - Tenant mismatch → Check DynamoDB mapping
   - Lambda error → Review CloudWatch logs, check Secrets Manager

**Data Not Appearing in Snowflake:**

1. **Check Lambda execution**: No errors in CloudWatch?
2. **Check Snowpipe Streaming**:
   ```sql
   SELECT *
   FROM snowflake.account_usage.pipe_usage_history
   WHERE pipe_name LIKE '%company_a%'
   ORDER BY start_time DESC
   LIMIT 10;
   ```
3. **Check Task execution**:
   ```sql
   SELECT *
   FROM snowflake.account_usage.task_history
   WHERE name LIKE '%company_a%'
   ORDER BY scheduled_time DESC
   LIMIT 10;
   ```
4. **Check DLQ**:
   ```bash
   aws sqs receive-message --queue-url https://sqs.eu-west-2.amazonaws.com/123456789/smdh-dlq
   ```

### 9.3 Backup and Recovery

**Snowflake Time Travel:**

```sql
-- Restore table to 1 hour ago
CREATE OR REPLACE TABLE smdh_tenant_company_a.raw.sensor_readings_restored
CLONE smdh_tenant_company_a.raw.sensor_readings
AT(OFFSET => -3600);

-- Query historical data (3 days ago)
SELECT *
FROM smdh_tenant_company_a.raw.sensor_readings
AT(TIMESTAMP => DATEADD(day, -3, CURRENT_TIMESTAMP()));

-- Restore dropped table (within 7-day Fail-safe period)
UNDROP TABLE smdh_tenant_company_a.raw.sensor_readings;
```

**Database Replication (Disaster Recovery):**

```sql
-- Create replication group for DR
CREATE REPLICATION GROUP smdh_prod_replication_group
    OBJECT_TYPES = DATABASES, INTEGRATIONS, ROLES
    ALLOWED_ACCOUNTS = dr_account_identifier
    REPLICATION_SCHEDULE = '60 MINUTE';

-- Add tenant database to replication
ALTER REPLICATION GROUP smdh_prod_replication_group
    ADD smdh_tenant_company_a;

-- Failover to DR account (if needed)
ALTER DATABASE smdh_tenant_company_a ENABLE FAILOVER TO ACCOUNTS dr_account_identifier;
```

---

## 10. Implementation Considerations

### 10.1 Protocol Selection Guidelines

The choice between MQTT, HTTP, and file-based ingestion depends on your specific data sources and requirements:

### 10.2 When to Use Each Protocol

#### MQTT via IoT Core

**Best for:**

- IoT devices with native MQTT support
- High-frequency sensor data (>1 Hz)
- Devices requiring persistent connections
- Scenarios needing QoS guarantees

**Considerations:**

- Requires AWS IoT Core (additional service)
- Certificate-based authentication
- More complex but more reliable for IoT

#### HTTP via API Gateway

**Best for:**

- Legacy systems with webhook capabilities
- Gateways that support HTTP but not MQTT
- Lower frequency data (<1 Hz)
- Simple request-response patterns

**Considerations:**

- Simpler to implement
- API key management required
- Higher overhead for high-frequency data

#### File Upload via Streamlit

**Best for:**

- Manual data uploads
- Batch processing
- Historical data import
- Non-technical users

**Considerations:**

- Not suitable for real-time data
- Requires user interaction
- Best for ad-hoc uploads

### 10.3 Multi-Protocol Architecture Benefits

The SMDH platform supports all three protocols simultaneously, allowing:

- Flexibility in device integration
- Gradual migration between protocols
- Optimal path for each data source
- Future-proof architecture

### 10.4 AWS IoT Core Configuration

#### 10.4.1 IoT Thing Setup

**Create IoT Thing (per gateway):**

```bash
# Create IoT Thing
aws iot create-thing \
  --thing-name "smdh-gateway-company-a-site-001" \
  --thing-type-name "LoRaWANGateway" \
  --attribute-payload '{"tenant_id":"company_a","site_id":"site-001"}' \
  --region eu-west-2

# Create and attach certificate
aws iot create-keys-and-certificate \
  --set-as-active \
  --certificate-pem-outfile gateway-cert.pem \
  --public-key-outfile gateway-public.key \
  --private-key-outfile gateway-private.key \
  --region eu-west-2

# Attach certificate to thing
aws iot attach-thing-principal \
  --thing-name "smdh-gateway-company-a-site-001" \
  --principal "arn:aws:iot:eu-west-2:123456789:cert/CERTIFICATE_ID" \
  --region eu-west-2
```

**IoT Policy (Least Privilege):**

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "iot:Connect",
      "Resource": "arn:aws:iot:eu-west-2:123456789:client/smdh-gateway-company-a-*"
    },
    {
      "Effect": "Allow",
      "Action": "iot:Publish",
      "Resource": "arn:aws:iot:eu-west-2:123456789:topic/smdh/company_a/sensor-data"
    }
  ]
}
```

#### 10.4.2 IoT Rules Engine Configuration

**IoT Rule for Sensor Data Ingestion:**

```sql
-- Rule SQL
SELECT
  topic(2) as tenant_id,
  *
FROM 'smdh/+/sensor-data'
WHERE tenant_id IS NOT NULL
```

**Rule Action Configuration:**

```bash
# Create IoT Rule
aws iot create-topic-rule \
  --rule-name smdh_sensor_ingestion \
  --topic-rule-payload '{
    "sql": "SELECT topic(2) as tenant_id, * FROM '\''smdh/+/sensor-data'\''",
    "description": "Route sensor data to Lambda for Snowflake ingestion",
    "actions": [{
      "lambda": {
        "functionArn": "arn:aws:lambda:eu-west-2:123456789:function:smdh-ingestion-lambda"
      }
    }],
    "errorAction": {
      "republish": {
        "roleArn": "arn:aws:iam::123456789:role/iot-republish-role",
        "topic": "smdh/errors",
        "qos": 1
      }
    },
    "ruleDisabled": false
  }' \
  --region eu-west-2

# Grant IoT permission to invoke Lambda
aws lambda add-permission \
  --function-name smdh-ingestion-lambda \
  --statement-id iot-invoke \
  --action lambda:InvokeFunction \
  --principal iot.amazonaws.com \
  --source-arn "arn:aws:iot:eu-west-2:123456789:rule/smdh_sensor_ingestion" \
  --region eu-west-2
```

### 10.5 Gateway Configuration Examples

#### 10.5.1 Milesight UG65 Dual-Protocol Support

The Milesight UG65 gateway supports both MQTT and HTTP protocols, allowing flexibility in choosing the appropriate ingestion path:

**MQTT Settings (Gateway Web Interface):**

```
Network Server > Application > MQTT Integration

MQTT Server: your-iot-endpoint.iot.eu-west-2.amazonaws.com
Port: 8883 (TLS)
Protocol: MQTT v3.1.1 or v5.0
Client ID: smdh-gateway-company-a-site-001

TLS/SSL: Enabled
  - CA Certificate: AmazonRootCA1.pem
  - Client Certificate: gateway-cert.pem
  - Client Private Key: gateway-private.key

Topic Template: smdh/company_a/sensor-data
QoS: 1 (At least once delivery)
Retain: false

Payload Format: JSON
```

**Protocol Configuration Comparison:**

| Setting              | HTTP Configuration | MQTT Configuration          |
| -------------------- | ------------------ | --------------------------- |
| **Endpoint**         | API Gateway URL    | IoT Core endpoint           |
| **Port**             | 443 (HTTPS)        | 8883 (MQTTS)                |
| **Authentication**   | API Key in header  | X.509 certificate           |
| **Connection Type**  | Request-Response   | Persistent                  |
| **Path/Topic**       | `/ingest` endpoint | `smdh/{tenant}/sensor-data` |
| **Message Delivery** | Per-request        | QoS levels (0,1,2)          |
| **Retry Logic**      | Gateway-managed    | Protocol-level              |

### 10.6 Lambda Function Modifications

The Lambda function requires minimal changes to support both HTTP (API Gateway) and MQTT (IoT Core) sources:

```python
def lambda_handler(event, context):
    """
    Unified handler for both API Gateway and IoT Core sources
    """
    try:
        # Detect event source
        if 'requestContext' in event:
            # API Gateway event (HTTP)
            return handle_api_gateway_event(event, context)
        elif 'tenant_id' in event:
            # IoT Core event (MQTT)
            return handle_iot_core_event(event, context)
        else:
            return {
                'statusCode': 400,
                'body': json.dumps({'error': 'Unknown event source'})
            }

    except Exception as e:
        print(f"Error processing request: {str(e)}")
        send_to_dlq(event, str(e))
        return {
            'statusCode': 500,
            'body': json.dumps({'error': 'Internal server error'})
        }

def handle_api_gateway_event(event, context):
    """
    Handle HTTP request from API Gateway (existing logic)
    """
    # Extract API key from headers
    api_key = event['headers'].get('x-api-key')
    if not api_key:
        return {
            'statusCode': 403,
            'body': json.dumps({'error': 'Missing API key'})
        }

    # Resolve tenant_id from API key
    tenant_id = resolve_tenant_id(api_key)
    if not tenant_id:
        return {
            'statusCode': 403,
            'body': json.dumps({'error': 'Invalid API key'})
        }

    # Parse request body
    body = json.loads(event['body'])

    # Continue with existing validation and ingestion logic...
    return process_sensor_data(body, tenant_id)

def handle_iot_core_event(event, context):
    """
    Handle MQTT message from IoT Core (new logic)
    """
    # Extract tenant_id from IoT Rule (already in event)
    tenant_id = event.get('tenant_id')
    if not tenant_id:
        print("SECURITY VIOLATION: Missing tenant_id in IoT event")
        send_to_dlq(event, "Missing tenant_id")
        return {'statusCode': 403}

    # Validate tenant_id against IoT Thing attributes
    thing_name = event.get('clientId')  # IoT client ID
    if thing_name:
        validated = validate_iot_thing(thing_name, tenant_id)
        if not validated:
            print(f"SECURITY VIOLATION: Thing {thing_name} not authorised for tenant {tenant_id}")
            send_to_dlq(event, f"Unauthorised thing for tenant {tenant_id}")
            return {'statusCode': 403}

    # Continue with existing ingestion logic...
    return process_sensor_data(event, tenant_id)

def validate_iot_thing(thing_name, tenant_id):
    """
    Validate that IoT Thing is authorised for tenant
    """
    iot_client = boto3.client('iot', region_name='eu-west-2')

    try:
        # Get thing attributes
        response = iot_client.describe_thing(thingName=thing_name)
        thing_tenant_id = response['attributes'].get('tenant_id')

        # Validate match
        return thing_tenant_id == tenant_id

    except Exception as e:
        print(f"Error validating IoT thing: {str(e)}")
        return False

def process_sensor_data(payload, tenant_id):
    """
    Common processing logic for both HTTP and MQTT sources
    (existing logic - no changes)
    """
    # Validate tenant match in payload
    payload_tenant = payload.get('applicationName', '').replace('tenant_', '')
    if payload_tenant and payload_tenant != tenant_id:
        print(f"SECURITY VIOLATION: Tenant mismatch {tenant_id} vs {payload_tenant}")
        send_to_dlq(payload, f"Tenant mismatch")
        return {'statusCode': 403}

    # Transform payload for Snowflake
    snowflake_payload = transform_payload(payload, tenant_id)

    # Generate JWT token
    jwt_token = get_jwt_token()

    # Send to Snowpipe Streaming
    response = send_to_snowpipe_streaming(snowflake_payload, jwt_token, tenant_id)

    return {'statusCode': 200, 'body': json.dumps({'message': 'Success'})}
```

### 10.7 Additional AWS Services Required

| Service                 | Purpose                         | Configuration Effort            |
| ----------------------- | ------------------------------- | ------------------------------- |
| **AWS IoT Core**        | MQTT broker and device registry | Medium - Certificate management |
| **IAM Policies**        | IoT Core → Lambda permissions   | Low - Single policy             |
| **IoT Rules Engine**    | Message routing                 | Low - SQL-based rules           |
| **IoT Registry**        | Device/Thing management         | Medium - Per-gateway setup      |
| **Certificate Manager** | X.509 certificate lifecycle     | Medium - Rotation procedures    |

### 10.8 Comparison Matrix

| Aspect                    | HTTP (Current)            | MQTT (Extension)              | Winner                  |
| ------------------------- | ------------------------- | ----------------------------- | ----------------------- |
| **Gateway Compatibility** | Universal (HTTP)          | MQTT-capable gateways         | **HTTP** (broader)      |
| **Authentication**        | API Key (simple)          | X.509 Certificates (complex)  | **HTTP** (simpler)      |
| **Connection Model**      | Stateless (per-request)   | Persistent connection         | **MQTT** (efficiency)   |
| **Bandwidth**             | Higher (HTTP overhead)    | Lower (binary protocol)       | **MQTT** (efficient)    |
| **Credential Rotation**   | Simple (DynamoDB update)  | Complex (certificate renewal) | **HTTP** (simpler)      |
| **Message Delivery**      | Synchronous (HTTP 200)    | Asynchronous (QoS levels)     | **Depends on use case** |
| **Offline Buffering**     | Gateway buffer (10k msgs) | Gateway + IoT Core            | **MQTT** (dual buffer)  |
| **AWS Services**          | 3 services                | 4 services                    | **HTTP** (fewer)        |
| **Debugging**             | Easy (HTTP logs)          | Moderate (MQTT traces)        | **HTTP** (easier)       |
| **Scalability**           | Excellent                 | Excellent                     | **Tie**                 |
| **Real-time Capability**  | Good (<1s latency)        | Excellent (<100ms latency)    | **MQTT** (faster)       |

### 10.9 Implementation Effort

#### Additional Implementation Tasks for MQTT

**Infrastructure Setup:**

- [ ] Create AWS IoT Core endpoints
- [ ] Generate root CA certificate
- [ ] Create IoT Thing Type definition
- [ ] Configure IoT Rules Engine
- [ ] Create IAM policies for IoT Core

**Per-Tenant Setup:**

- [ ] Create IoT Thing per gateway
- [ ] Generate X.509 certificates
- [ ] Securely deliver certificates to gateway
- [ ] Configure MQTT settings on gateway
- [ ] Attach IoT policy to certificate
- [ ] Test MQTT connection

**Lambda Modifications:**

- [ ] Update Lambda function with dual-source handler
- [ ] Add IoT Thing validation logic
- [ ] Update IAM role for IoT describe permissions
- [ ] Test with both HTTP and MQTT sources

**Operational Procedures:**

- [ ] Certificate rotation procedure
- [ ] IoT Thing lifecycle management
- [ ] MQTT connection monitoring
- [ ] Certificate revocation process

### 10.10 Security Considerations

#### Certificate Management

**Security Benefits:**

- Stronger authentication than API keys (PKI-based)
- Mutual TLS authentication
- Built-in certificate lifecycle management
- Revocation without gateway reconfiguration

**Security Challenges:**

- Certificate storage on gateway (physical security required)
- Certificate rotation complexity
- Root CA management
- Certificate revocation distribution

**Recommended Approach:**

```python
# Certificate rotation procedure
def rotate_gateway_certificate(thing_name):
    """
    Rotate certificate for IoT Thing with zero downtime
    """
    iot_client = boto3.client('iot')

    # 1. Create new certificate
    new_cert = iot_client.create_keys_and_certificate(setAsActive=True)

    # 2. Attach new certificate to thing
    iot_client.attach-thing_principal(
        thingName=thing_name,
        principal=new_cert['certificateArn']
    )

    # 3. Update gateway with new certificate (manual step)
    # Gateway now has two valid certificates

    # 4. Wait for confirmation gateway is using new certificate
    # (check MQTT connections)

    # 5. Detach and deactivate old certificate
    iot_client.detach_thing_principal(
        thingName=thing_name,
        principal=old_cert_arn
    )
    iot_client.update_certificate(
        certificateId=old_cert_id,
        newStatus='INACTIVE'
    )
```

### 10.11 Cost Implications

**Additional AWS Costs for MQTT:**

| Component                 | Estimated Usage        | Notes                         |
| ------------------------- | ---------------------- | ----------------------------- |
| **IoT Core Connectivity** | Persistent connections | Charged per connection-minute |
| **IoT Core Messaging**    | Message volume         | Charged per message           |
| **IoT Rules**             | Rule execution         | Included in messaging cost    |
| **Certificate Storage**   | Minimal                | Negligible cost               |

**Note:** Actual costs depend on message volume, connection patterns, and data transfer. For typical SMDH workload (1 Hz sensors), MQTT costs may be comparable to API Gateway costs.

### 10.12 Recommendation

**When to Use HTTP (Current Approach):**

- Simpler operational model preferred
- Stateless architecture required
- Easier credential management needed
- Universal gateway compatibility important
- Minimal AWS service footprint desired

**When to Use MQTT (Extension):**

- Persistent connections beneficial (high-frequency data)
- Lower bandwidth consumption required
- Sub-second latency critical
- Gateways have native MQTT support
- Certificate-based security preferred

**Hybrid Approach (Both Supported):**

The architecture can support **both HTTP and MQTT ingestion simultaneously** with minimal Lambda modifications. This allows:

- Different gateways to use preferred protocol
- Gradual migration from HTTP to MQTT (or vice versa)
- A/B testing of both approaches
- Tenant-specific protocol selection

```
                        ┌─────────────────┐
Sensors → Gateway A ────┤ API Gateway     ├──┐
                        │ (HTTP)          │  │
                        └─────────────────┘  │
                                             ├──→ Lambda → Snowpipe → Snowflake
                        ┌─────────────────┐  │
Sensors → Gateway B ────┤ AWS IoT Core    ├──┘
                        │ (MQTT)          │
                        └─────────────────┘
```

### 10.13 Migration Path

If migrating from HTTP to MQTT (or vice versa):

**Phase 1: Preparation**

1. Deploy updated Lambda function with dual-source support
2. Test MQTT setup with one pilot gateway
3. Document certificate management procedures

**Phase 2: Gradual Rollout**

1. Migrate one tenant at a time
2. Run both protocols in parallel during transition
3. Monitor for data quality and latency

**Phase 3: Cutover**

1. Confirm all gateways migrated successfully
2. Optionally decommission old protocol infrastructure
3. Update documentation

---

## 11. DevTank Sensor Integration

### 11.1 Overview

The SMDH platform supports DevTank OpenSmartMonitor (OSM) sensors as a validated device type for comprehensive environmental, air quality, and energy monitoring. DevTank OSM devices are multi-sensor IoT devices that transmit binary-encoded data via LoRaWAN or Wi-Fi MQTT protocols.

**DevTank OSM Capabilities:**

| Measurement Type | Sensors                         | Use Cases                                 |
| ---------------- | ------------------------------- | ----------------------------------------- |
| **Air Quality**  | PM1, PM2.5, PM4, PM10, VOC, NOx | Indoor air quality monitoring, compliance |
| **Environment**  | Temperature, Humidity           | Ambient conditions, comfort monitoring    |
| **Energy**       | CC1, CC2, CC3 (current clamps)  | Energy consumption, equipment monitoring  |
| **Device**       | Battery, Light, Sound           | Device health, operational status         |

**Communication Options:**

```
Option 1: LoRaWAN Communication
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
DevTank OSM → LoRaWAN (868 MHz) → Milesight UG65 Gateway → AWS IoT Core → Kinesis → Snowflake

Option 2: Wi-Fi MQTT Communication
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
DevTank OSM → Wi-Fi → AWS IoT Core (MQTT) → Kinesis → Snowflake
```

### 11.2 Data Format and Payload Structure

DevTank devices transmit binary-encoded sensor data using a compact protocol:

**Binary Payload Structure:**

```
[Protocol Version: 1 byte] [Measurement Name: 4 bytes] [Value: 2 bytes little-endian] ...
```

**Example Raw Payload (Hex):**

```
01 42 41 54 00 28 0E CC 31 00 23 01 48 55 4D 49 94 11 54 45 4D 50 DC 08
```

**Decoded JSON Output:**

```json
{
  "BAT": 3624,
  "CC1": 291,
  "HUMI": 4500,
  "TEMP": 2268,
  "PM25": 12,
  "VOC": 150
}
```

**Value Scaling Factors:**

| Measurement           | Raw Value | Scaling | Actual Value | Unit  |
| --------------------- | --------- | ------- | ------------ | ----- |
| **TEMP**              | 2268      | ÷ 100   | 22.68        | °C    |
| **HUMI**              | 4500      | ÷ 100   | 45.00        | %     |
| **BAT**               | 3624      | ÷ 1000  | 3.624        | V     |
| **CC1/CC2/CC3**       | 291       | ÷ 1     | 291          | mA    |
| **PM1/PM25/PM4/PM10** | 12        | ÷ 1     | 12           | µg/m³ |
| **VOC**               | 150       | ÷ 1     | 150          | ppb   |
| **NOX**               | 25        | ÷ 1     | 25           | ppb   |

### 11.3 JavaScript Payload Decoder

The following JavaScript decoder must be configured in the LoRaWAN network server:

```javascript
function decodeUplink(bytes) {
  var pos = 0;
  var data = {};

  // Check protocol version
  var protocol_version = bytes[pos++];
  if (protocol_version !== 1) {
    return data;
  }

  var name;
  while (pos < bytes.length) {
    // Read measurement name (4 bytes ASCII)
    name = "";
    for (var i = 0; i < 4; i++) {
      if (bytes[pos] !== 0) {
        name += String.fromCharCode(bytes[pos]);
      }
      pos++;
    }

    if (name.length === 0) {
      break;
    }

    // Read value (2 bytes, little-endian)
    var value = bytes[pos] | (bytes[pos + 1] << 8);
    pos += 2;

    // Handle signed values for temperature
    if (name === "TEMP" || name.startsWith("TMP")) {
      if (value > 32767) {
        value = value - 65536;
      }
    }

    data[name] = value;
  }

  return {
    data: data,
  };
}

// Alternative format for TTN v3
function Decoder(bytes, fPort) {
  return decodeUplink(bytes).data;
}
```

### 11.4 Snowflake Data Model for DevTank Sensors

#### 11.4.1 Raw DevTank Readings Table

```sql
-- DevTank-specific raw data table (extends standard sensor_readings)
CREATE OR REPLACE TABLE smdh_tenant_${TENANT_ID}.raw.devtank_raw_readings (
    -- IoT metadata
    tenant_id VARCHAR(100) NOT NULL,
    device_id VARCHAR(100) NOT NULL,
    iot_timestamp TIMESTAMP_NTZ NOT NULL,

    -- DevTank identification
    dev_eui VARCHAR(50),
    thing_name VARCHAR(255),

    -- Raw binary payload (decoded)
    raw_payload VARIANT NOT NULL,

    -- LoRaWAN metadata
    gateway_id VARCHAR(255),
    rssi INTEGER,
    snr FLOAT,

    -- Ingestion metadata
    ingestion_timestamp TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    source_system VARCHAR(50) DEFAULT 'devtank_osm',

    PRIMARY KEY (tenant_id, device_id, iot_timestamp)
)
CLUSTER BY (tenant_id, DATE_TRUNC('day', iot_timestamp), device_id)
ENABLE_SCHEMA_EVOLUTION = TRUE
COMMENT = 'Raw DevTank OSM sensor readings with binary payload decoded';

-- Create stream for CDC
CREATE OR REPLACE STREAM smdh_tenant_${TENANT_ID}.raw.devtank_raw_readings_stream
ON TABLE smdh_tenant_${TENANT_ID}.raw.devtank_raw_readings
APPEND_ONLY = TRUE;
```

#### 11.4.2 Normalized DevTank Readings Dynamic Table

```sql
-- Normalized DevTank readings with scaled values
CREATE OR REPLACE DYNAMIC TABLE smdh_tenant_${TENANT_ID}.normalized.devtank_readings
TARGET_LAG = '1 minute'
WAREHOUSE = streaming_wh
AS
SELECT
    tenant_id,
    device_id,
    iot_timestamp as timestamp,

    -- Temperature (scaled from centidegrees to degrees)
    raw_payload:TEMP::FLOAT / 100 as temperature_c,

    -- Humidity (scaled from centipercent to percent)
    raw_payload:HUMI::FLOAT / 100 as humidity_pct,

    -- Air Quality (particulate matter in µg/m³)
    raw_payload:PM1::INTEGER as pm1_ugm3,
    raw_payload:PM25::INTEGER as pm25_ugm3,
    raw_payload:PM4::INTEGER as pm4_ugm3,
    raw_payload:PM10::INTEGER as pm10_ugm3,

    -- Air Quality (gases in ppb)
    raw_payload:VOC::INTEGER as voc_ppb,
    raw_payload:NOX::INTEGER as nox_ppb,

    -- Energy Monitoring (current clamps in mA)
    raw_payload:CC1::INTEGER as current_clamp_1_ma,
    raw_payload:CC2::INTEGER as current_clamp_2_ma,
    raw_payload:CC3::INTEGER as current_clamp_3_ma,

    -- Device Status
    raw_payload:BAT::FLOAT / 1000 as battery_v,
    raw_payload:LGHT::INTEGER as light_level,
    raw_payload:SND::INTEGER as sound_level,

    -- Calculate Air Quality Index (AQI)
    CASE
        WHEN raw_payload:PM25::INTEGER > 55 THEN 'Poor'
        WHEN raw_payload:VOC::INTEGER > 500 THEN 'Moderate'
        WHEN raw_payload:NOX::INTEGER > 100 THEN 'Moderate'
        ELSE 'Good'
    END as air_quality_index,

    -- Metadata
    gateway_id,
    rssi,
    snr,
    'devtank_osm' as source_system,
    ingestion_timestamp

FROM smdh_tenant_${TENANT_ID}.raw.devtank_raw_readings
WHERE raw_payload IS NOT NULL;
```

#### 11.4.3 DevTank Air Quality Aggregations

```sql
-- Hourly air quality metrics from DevTank sensors
CREATE OR REPLACE DYNAMIC TABLE smdh_tenant_${TENANT_ID}.aggregated.devtank_air_quality_hourly
TARGET_LAG = '5 minutes'
WAREHOUSE = analytics_wh
AS
SELECT
    device_id as location_id,
    DATE_TRUNC('hour', timestamp) as hour,

    -- Air Quality Averages
    AVG(pm1_ugm3) as avg_pm1,
    AVG(pm25_ugm3) as avg_pm25,
    AVG(pm4_ugm3) as avg_pm4,
    AVG(pm10_ugm3) as avg_pm10,
    AVG(voc_ppb) as avg_voc,
    AVG(nox_ppb) as avg_nox,

    -- Air Quality Peaks
    MAX(pm25_ugm3) as max_pm25,
    MAX(voc_ppb) as max_voc,

    -- Environmental Conditions
    AVG(temperature_c) as avg_temperature,
    AVG(humidity_pct) as avg_humidity,

    -- Device Health
    AVG(battery_v) as avg_battery,
    MIN(battery_v) as min_battery,

    -- Data Quality
    COUNT(*) as reading_count,
    AVG(rssi) as avg_signal_strength

FROM smdh_tenant_${TENANT_ID}.normalized.devtank_readings
GROUP BY device_id, DATE_TRUNC('hour', timestamp);
```

#### 11.4.4 DevTank Energy Monitoring (Current Clamps)

```sql
-- Energy monitoring from current clamps
CREATE OR REPLACE DYNAMIC TABLE smdh_tenant_${TENANT_ID}.aggregated.devtank_energy_monitoring
TARGET_LAG = '1 minute'
WAREHOUSE = analytics_wh
AS
SELECT
    device_id as equipment_id,
    DATE_TRUNC('minute', timestamp) as minute,

    -- Current Measurements
    AVG(current_clamp_1_ma) as avg_current_1_ma,
    AVG(current_clamp_2_ma) as avg_current_2_ma,
    AVG(current_clamp_3_ma) as avg_current_3_ma,

    -- Peak Current
    MAX(current_clamp_1_ma) as peak_current_1_ma,
    MAX(current_clamp_2_ma) as peak_current_2_ma,
    MAX(current_clamp_3_ma) as peak_current_3_ma,

    -- Equipment Status Detection
    CASE
        WHEN AVG(current_clamp_1_ma) > 100 THEN 'ACTIVE'
        WHEN AVG(current_clamp_1_ma) > 10 THEN 'STANDBY'
        ELSE 'OFF'
    END as equipment_status,

    -- Data Quality
    COUNT(*) as reading_count

FROM smdh_tenant_${TENANT_ID}.normalized.devtank_readings
WHERE current_clamp_1_ma IS NOT NULL
GROUP BY device_id, DATE_TRUNC('minute', timestamp);
```

### 11.5 Deployment Procedures

#### 11.5.1 Roles and Responsibilities

**IT Operations Team (Remote):**

- AWS IoT Core administration
- Certificate generation and management
- IoT Policy creation
- Snowflake database administration
- LoRaWAN network server configuration

**Onsite Configurer (On-site):**

- Physical device installation
- Device configuration via OSM Config GUI
- Wi-Fi network configuration
- Initial device testing
- Site survey and coverage validation

#### 11.5.2 New Tenant Onboarding with DevTank Sensors

**Step 1: AWS IoT Core Setup (IT Operations)**

```bash
# Set tenant and device variables
export TENANT_ID="company_b"
export SITE_ID="site_001"
export DEVICE_ID="osm_001"
export AWS_REGION="eu-west-2"

# Create IoT Thing Type (first time only)
aws iot create-thing-type \
  --thing-type-name "DevTankOSM" \
  --thing-type-properties '{
    "thingTypeDescription": "DevTank OpenSmartMonitor sensor device",
    "searchableAttributes": ["tenant_id", "site_id", "device_type"]
  }' \
  --region ${AWS_REGION}

# Create IoT Thing for device
aws iot create-thing \
  --thing-name "smdh-osm-${TENANT_ID}-${SITE_ID}-${DEVICE_ID}" \
  --thing-type-name "DevTankOSM" \
  --attribute-payload '{
    "attributes": {
      "tenant_id": "'${TENANT_ID}'",
      "site_id": "'${SITE_ID}'",
      "device_type": "OpenSmartMonitor",
      "sensor_types": "air_quality,energy,environment"
    }
  }' \
  --region ${AWS_REGION}

# Generate X.509 certificates
aws iot create-keys-and-certificate \
  --set-as-active \
  --certificate-pem-outfile "${TENANT_ID}-${DEVICE_ID}-cert.pem" \
  --public-key-outfile "${TENANT_ID}-${DEVICE_ID}-public.key" \
  --private-key-outfile "${TENANT_ID}-${DEVICE_ID}-private.key" \
  --region ${AWS_REGION}

# Store certificate ARN
export CERT_ARN="<output-from-previous-command>"

# Download Amazon Root CA
wget -O AmazonRootCA1.pem https://www.amazontrust.com/repository/AmazonRootCA1.pem

# Attach certificate to thing
aws iot attach-thing-principal \
  --thing-name "smdh-osm-${TENANT_ID}-${SITE_ID}-${DEVICE_ID}" \
  --principal "${CERT_ARN}" \
  --region ${AWS_REGION}

# Attach IoT policy to certificate
aws iot attach-policy \
  --policy-name "smdh-osm-${TENANT_ID}-policy" \
  --target "${CERT_ARN}" \
  --region ${AWS_REGION}

# Get IoT endpoint for device configuration
aws iot describe-endpoint \
  --endpoint-type iot:Data-ATS \
  --region ${AWS_REGION} \
  --query 'endpointAddress' \
  --output text
```

**Step 2: Snowflake Database Setup (IT Operations)**

```sql
-- Create DevTank-specific tables in tenant database
USE DATABASE smdh_tenant_${TENANT_ID};

-- Create raw DevTank table
CREATE OR REPLACE TABLE raw.devtank_raw_readings (
    -- (See Section 11.4.1 for complete DDL)
);

-- Create normalized Dynamic Table
CREATE OR REPLACE DYNAMIC TABLE normalized.devtank_readings
    -- (See Section 11.4.2 for complete DDL)
;

-- Create aggregation Dynamic Tables
CREATE OR REPLACE DYNAMIC TABLE aggregated.devtank_air_quality_hourly
    -- (See Section 11.4.3 for complete DDL)
;

CREATE OR REPLACE DYNAMIC TABLE aggregated.devtank_energy_monitoring
    -- (See Section 11.4.4 for complete DDL)
;

-- Grant access to tenant roles
GRANT SELECT ON TABLE raw.devtank_raw_readings
    TO ROLE tenant_${TENANT_ID}_admin_role;

GRANT SELECT ON TABLE normalized.devtank_readings
    TO ROLE tenant_${TENANT_ID}_user_role;

GRANT SELECT ON TABLE aggregated.devtank_air_quality_hourly
    TO ROLE tenant_${TENANT_ID}_user_role;

GRANT SELECT ON TABLE aggregated.devtank_energy_monitoring
    TO ROLE tenant_${TENANT_ID}_user_role;
```

**Step 3: LoRaWAN Network Server Configuration (IT Operations)**

For LoRaWAN devices, configure the network server (TTN, ChirpStack, or Helium):

```javascript
// Add DevTank payload decoder to network server
// Navigate to: Application > Payload Formatters > Uplink

function decodeUplink(bytes) {
  // (See Section 11.3 for complete decoder function)
}
```

**Step 4: Device Configuration Package (IT Operations)**

```bash
# Create device credentials package
mkdir -p "device_package_${DEVICE_ID}"

# Create device info file
cat > "device_package_${DEVICE_ID}/device_info.json" << EOF
{
  "thing_name": "smdh-osm-${TENANT_ID}-${SITE_ID}-${DEVICE_ID}",
  "tenant_id": "${TENANT_ID}",
  "site_id": "${SITE_ID}",
  "device_id": "${DEVICE_ID}",
  "iot_endpoint": "$(aws iot describe-endpoint --endpoint-type iot:Data-ATS --region ${AWS_REGION} --query 'endpointAddress' --output text)",
  "mqtt_port": 8883,
  "device_type": "DevTank_OpenSmartMonitor",
  "created_date": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

# Copy certificates (for Wi-Fi devices)
mkdir -p "device_package_${DEVICE_ID}/certificates"
cp "${TENANT_ID}-${DEVICE_ID}-cert.pem" "device_package_${DEVICE_ID}/certificates/"
cp "${TENANT_ID}-${DEVICE_ID}-private.key" "device_package_${DEVICE_ID}/certificates/"
cp AmazonRootCA1.pem "device_package_${DEVICE_ID}/certificates/"

# Create README
cat > "device_package_${DEVICE_ID}/README.txt" << EOF
DevTank OSM Device Credentials Package
======================================

Device: ${DEVICE_ID}
Tenant: ${TENANT_ID}
Site: ${SITE_ID}
Device Type: DevTank OpenSmartMonitor

For Wi-Fi devices:
- Configure device via OSM Config GUI at https://osm-config.devtank.co.uk
- MQTT Address: (see device_info.json)
- MQTT Port: 8883
- Upload certificates from certificates/ directory

For LoRaWAN devices:
- Configure device via OSM Config GUI
- Generate DevEUI and AppKey
- Send DevEUI/AppKey to IT Operations for network server registration

Contact IT Operations for assistance.
EOF

# Create ZIP package
zip -r "device_package_${DEVICE_ID}.zip" "device_package_${DEVICE_ID}/"

echo "Package ready: device_package_${DEVICE_ID}.zip"
echo "Deliver this package to the Onsite Configurer"
```

**Step 5: Onsite Device Configuration (Onsite Configurer)**

1. **Physical Installation:**

   - Mount DevTank OSM at designated location
   - Ensure adequate coverage (Wi-Fi or LoRaWAN gateway range)
   - Connect power supply

2. **Connect to Device:**

   - Connect device to laptop via USB-C cable
   - Open Chrome browser: https://osm-config.devtank.co.uk
   - Click "Connect via USB" and select device

3. **Configure Communication Method:**

   **For Wi-Fi Devices:**

   ```
   - Select site Wi-Fi network (SSID)
   - Enter Wi-Fi password
   - MQTT Address: (from device_info.json)
   - MQTT Port: 8883
   - MQTT Scheme: TCP (TLS)
   - Click "Send"
   ```

   **For LoRaWAN Devices:**

   ```
   - Click "Generate LoRa Dev EUI"
   - Click "Generate LoRa App Key"
   - Select Region: EU868 (4)
   - Record DevEUI and AppKey
   - Send to IT Operations
   - Click "Send"
   ```

4. **Configure Measurement Intervals:**

   ```
   Recommended intervals:
   - TEMP, HUMI: 5 minutes
   - PM1, PM25, PM4, PM10: 15 minutes
   - VOC, NOX: 15 minutes
   - CC1, CC2, CC3: 1 minute
   - BAT: 60 minutes
   ```

5. **Save Configuration:**
   - Click "Save Configuration"
   - Download backup: `osm_${TENANT_ID}_${SITE_ID}_${DEVICE_ID}_config.json`

**Step 6: LoRaWAN Device Registration (IT Operations)**

After receiving DevEUI/AppKey from Onsite Configurer:

```bash
# Register device in LoRaWAN network server (example for TTN)
# 1. Login to TTN Console: https://console.cloud.thethings.network
# 2. Navigate to application: smdh-${TENANT_ID}
# 3. Add End Device → Manually
# 4. Enter DevEUI, AppKey (from Onsite Configurer)
# 5. Add payload decoder (Section 11.3)
# 6. Save device

# Notify Onsite Configurer
echo "Device ${DEVICE_ID} registered in network server"
echo "Please verify device shows 'Connected' status"
```

**Step 7: Validation (Both Roles)**

```sql
-- IT Operations: Verify data in Snowflake
SELECT
    device_id,
    iot_timestamp,
    temperature_c,
    humidity_pct,
    pm25_ugm3,
    voc_ppb,
    battery_v
FROM smdh_tenant_${TENANT_ID}.normalized.devtank_readings
WHERE device_id = '${DEVICE_ID}'
ORDER BY iot_timestamp DESC
LIMIT 10;

-- Expected latency: 5-15 seconds from sensor reading to Snowflake
```

### 11.6 Maintenance Procedures

#### 11.6.1 Adding New DevTank Devices to Existing Tenant

**Quick Checklist:**

- [ ] Create new IoT Thing in AWS
- [ ] Generate and attach X.509 certificate
- [ ] Prepare device credentials package
- [ ] Ship credentials to onsite team
- [ ] Configure device via OSM Config GUI
- [ ] Register in LoRaWAN network server (if applicable)
- [ ] Verify data appears in Snowflake

**No Snowflake changes required** - new devices write to existing tenant tables.

#### 11.6.2 Firmware Updates

```bash
# Check firmware version via OSM Config GUI
# Compare with latest available firmware SHA
# If different, click "Flash Firmware" button
# For LoRaWAN devices, also update comms firmware: "Flash Comms Firmware" (RAK3172 v4.1.0)
```

#### 11.6.3 Certificate Rotation (Wi-Fi Devices)

```bash
# Generate new certificate
aws iot create-keys-and-certificate \
  --set-as-active \
  --certificate-pem-outfile "${TENANT_ID}-${DEVICE_ID}-cert-new.pem" \
  --private-key-outfile "${TENANT_ID}-${DEVICE_ID}-private-new.key" \
  --region ${AWS_REGION}

# Attach new certificate to thing (allows dual certificates during rotation)
aws iot attach-thing-principal \
  --thing-name "smdh-osm-${TENANT_ID}-${SITE_ID}-${DEVICE_ID}" \
  --principal "${NEW_CERT_ARN}" \
  --region ${AWS_REGION}

# Deliver new certificate to device
# Wait for confirmation device is using new certificate

# Detach and deactivate old certificate
aws iot detach-thing-principal \
  --thing-name "smdh-osm-${TENANT_ID}-${SITE_ID}-${DEVICE_ID}" \
  --principal "${OLD_CERT_ARN}" \
  --region ${AWS_REGION}

aws iot update-certificate \
  --certificate-id ${OLD_CERT_ID} \
  --new-status INACTIVE \
  --region ${AWS_REGION}
```

#### 11.6.4 Monitoring Device Health

```sql
-- DevTank device health dashboard query
SELECT
    device_id,
    MAX(timestamp) as last_seen,
    DATEDIFF('minute', MAX(timestamp), CURRENT_TIMESTAMP()) as minutes_since_last_reading,
    AVG(battery_v) as avg_battery_voltage,
    AVG(rssi) as avg_signal_strength,
    CASE
        WHEN DATEDIFF('minute', MAX(timestamp), CURRENT_TIMESTAMP()) > 30 THEN 'OFFLINE'
        WHEN AVG(battery_v) < 3.0 THEN 'LOW_BATTERY'
        WHEN AVG(rssi) < -100 THEN 'WEAK_SIGNAL'
        ELSE 'HEALTHY'
    END as device_status
FROM smdh_tenant_${TENANT_ID}.normalized.devtank_readings
WHERE timestamp > DATEADD(day, -1, CURRENT_TIMESTAMP())
GROUP BY device_id
ORDER BY minutes_since_last_reading DESC;
```

### 11.7 Troubleshooting

| Symptom                         | Possible Cause                 | Solution                                                 |
| ------------------------------- | ------------------------------ | -------------------------------------------------------- |
| **No data in Snowflake**        | Device not joined network      | Check device status in OSM Config GUI                    |
| **No data in Snowflake**        | Payload decoder not configured | Add JavaScript decoder to network server                 |
| **Invalid sensor values**       | Scaling not applied            | Verify Dynamic Table uses scaling factors (Section 11.2) |
| **Device shows "Disconnected"** | Wrong MQTT endpoint/port       | Re-enter IoT endpoint from AWS                           |
| **LoRaWAN join rejected**       | Wrong AppKey                   | Verify AppKey matches network server registration        |
| **All values "n/a"**            | Sensor not equipped on device  | Only configured sensors return values                    |

### 11.8 Cost Implications

**DevTank Sensor Costs (per device/month):**

| Component             | Cost Driver                   | Estimate                      |
| --------------------- | ----------------------------- | ----------------------------- |
| **AWS IoT Core**      | Connection minutes + messages | £1-3/device                   |
| **AWS Kinesis**       | Data throughput (shared)      | Allocated across all devices  |
| **Snowflake Storage** | Raw + normalized + aggregated | ~100 MB/device/month          |
| **Snowflake Compute** | Dynamic Table refreshes       | Minimal (streaming warehouse) |

**Note:** Costs scale linearly with number of devices. Bulk deployments benefit from shared infrastructure (Kinesis, warehouses).

### 11.9 Integration with Existing SMDH Architecture

DevTank sensors integrate seamlessly with the existing SMDH architecture:

```
DevTank OSM Device
        ↓
   (Wi-Fi or LoRaWAN)
        ↓
   AWS IoT Core (existing infrastructure)
        ↓
   IoT Rules Engine (existing rules)
        ↓
   Kinesis Data Streams (existing stream)
        ↓
   Snowflake Openflow (existing connector)
        ↓
   Tenant Database (existing database + DevTank-specific tables)
        ↓
   Streamlit Portal / Power BI (existing analytics)
```

**No architectural changes required** - DevTank devices leverage existing ingestion infrastructure with device-specific Snowflake tables for optimised querying and analytics.

---

## 12. Milesight UG65 Gateway Configuration

### 12.1 Overview

The Milesight UG65 is a commercial-grade LoRaWAN gateway that serves as the critical bridge between LoRaWAN sensor devices and the SMDH cloud infrastructure. The UG65 features an integrated LoRaWAN Network Server, eliminating the need for separate network server infrastructure and simplifying deployment.

**Key Capabilities:**

| Feature              | Specification                           | SMDH Application                |
| -------------------- | --------------------------------------- | ------------------------------- |
| **LoRaWAN Protocol** | Class A/B/C, LoRaWAN 1.0.2/1.0.3        | DevTank OSM and other sensors   |
| **Radio Channels**   | 8 channels (EU868), 16 channels (US915) | Multi-sensor support            |
| **Network Server**   | Built-in (up to 2000 devices)           | Centralized device management   |
| **Connectivity**     | Ethernet, Wi-Fi, 4G LTE                 | Flexible deployment options     |
| **Protocols**        | MQTT, HTTP/HTTPS, TCP/UDP               | Dual ingestion path support     |
| **Operating Temp**   | -40°C to +70°C                          | Industrial environment suitable |
| **Power**            | PoE (802.3af) or 12V DC                 | Simple installation             |
| **IP Rating**        | IP30 (indoor)                           | Office/factory environments     |

**Communication Architecture:**

```
┌──────────────────────────────────────────────────────────────┐
│                    Milesight UG65 Gateway                    │
│                                                              │
│  ┌─────────────┐    ┌──────────────┐    ┌───────────────┐  │
│  │   LoRaWAN   │───▶│   Network    │───▶│  Application  │  │
│  │   Radio     │    │   Server     │    │   Server      │  │
│  │  (868 MHz)  │    │  (Built-in)  │    │  (Built-in)   │  │
│  └─────────────┘    └──────────────┘    └───────────────┘  │
│        ▲                                         │           │
│        │                                         ▼           │
│   [Sensors]                          ┌──────────────────┐   │
│                                      │  MQTT/HTTP Client│   │
│                                      └──────────────────┘   │
│                                                │             │
└────────────────────────────────────────────────┼─────────────┘
                                                 │
                                                 ▼
                           ┌─────────────────────────────────┐
                           │   AWS IoT Core (MQTT)           │
                           │   or                            │
                           │   API Gateway (HTTP)            │
                           └─────────────────────────────────┘
```

**Dual Protocol Support:**

The UG65 can operate in two distinct modes for cloud connectivity:

| Mode          | Protocol         | Use Case                                   | Configuration Complexity | Latency   |
| ------------- | ---------------- | ------------------------------------------ | ------------------------ | --------- |
| **MQTT Mode** | MQTT v3.1.1/v5.0 | Persistent connection, high-frequency data | Medium (certificates)    | <100 ms   |
| **HTTP Mode** | HTTPS POST       | Request-response, simpler setup            | Low (API key)            | <1 second |

### 12.2 Technical Specifications

#### 12.2.1 Hardware Specifications

**Physical:**

- Dimensions: 142 × 105 × 38 mm
- Weight: 300g
- Mounting: Wall-mount bracket included
- Antenna: RP-SMA connector (3dBi fiberglass antenna included)
- Indicators: Power (green), LoRa (blue), Network (yellow)

**Interfaces:**

- 1× RJ45 Ethernet (10/100 Mbps)
- 1× RP-SMA (LoRaWAN antenna)
- 1× RP-SMA (Optional 4G/Wi-Fi antenna)
- 1× USB-C (Console/debug)

**Power:**

- Input: 12V DC (2A) or PoE (802.3af)
- Power consumption: 6W typical, 12W peak
- PoE injector included

#### 12.2.2 LoRaWAN Radio Specifications

**EU868 Configuration:**

```
Frequency Plan: EU863-870 (ETSI EN300.220)
Channels:
  - CH0: 868.1 MHz (SF7-SF12, 125 kHz)
  - CH1: 868.3 MHz (SF7-SF12, 125 kHz)
  - CH2: 868.5 MHz (SF7-SF12, 125 kHz)
  - CH3: 867.1 MHz (SF7-SF12, 125 kHz)
  - CH4: 867.3 MHz (SF7-SF12, 125 kHz)
  - CH5: 867.5 MHz (SF7-SF12, 125 kHz)
  - CH6: 867.7 MHz (SF7-SF12, 125 kHz)
  - CH7: 867.9 MHz (SF7-SF12, 125 kHz)

TX Power: 27 dBm (500 mW) max
RX Sensitivity: -142.5 dBm @ SF12
Range: Indoor: 100-500m, Outdoor: 2-5 km (line of sight)
Duty Cycle: <1% per sub-band (ETSI compliance)
```

**Link Budget Calculation:**

```
TX Power (Gateway):        +27 dBm
TX Antenna Gain:           +3 dBi
Free Space Path Loss:      -130 dB (2 km @ 868 MHz)
RX Antenna Gain (sensor):  +2 dBi
Margin:                    +10 dB
─────────────────────────────────────
Required RX Sensitivity:   -128 dBm
UG65 Sensitivity:          -142.5 dBm @ SF12
Link Budget Margin:        14.5 dB ✓
```

#### 12.2.3 Supported Sensor Devices

**Validated Device Compatibility:**

| Device Type          | Manufacturer | Protocol        | Codec                        | SMDH Status |
| -------------------- | ------------ | --------------- | ---------------------------- | ----------- |
| **DevTank OSM**      | DevTank      | LoRaWAN Class A | Custom binary (Section 11.3) | VALIDATED   |
| **Milesight EM300**  | Milesight    | LoRaWAN Class A | Built-in                     | COMPATIBLE  |
| **Dragino LHT65**    | Dragino      | LoRaWAN Class A | Built-in                     | COMPATIBLE  |
| **Tektelic Sensors** | Tektelic     | LoRaWAN Class A | Built-in                     | COMPATIBLE  |
| **RAK Wireless**     | RAK          | LoRaWAN Class A | Built-in                     | COMPATIBLE  |
| **Generic LoRaWAN**  | Various      | LoRaWAN Class A | Custom codec required        | SUPPORTED   |

### 12.3 Network Server Configuration

The UG65 includes an integrated LoRaWAN Network Server that manages device join procedures, encryption, and payload routing.

#### 12.3.1 Initial Gateway Setup

**Step 1: Physical Installation**

```
Requirements:
- Ethernet connection (DHCP or static IP)
- Power: PoE or 12V DC adapter
- Antenna: RP-SMA LoRaWAN antenna (included)
- Location: Central to coverage area, elevated if possible
- Avoid: Metal enclosures, dense concrete walls, RF interference sources

Installation:
1. Mount gateway on wall using bracket (screws included)
2. Connect LoRaWAN antenna to RP-SMA connector
3. Connect Ethernet cable
4. Apply power (PoE or 12V adapter)
5. Wait 60 seconds for boot sequence
6. Verify LEDs:
   - Power (Green): Solid
   - Network (Yellow): Solid (Ethernet) or Blinking (acquiring IP)
   - LoRa (Blue): Blinking (radio active)
```

**Step 2: Access Web Interface**

```
Discovery Methods:

Method 1: DHCP-assigned IP
- Login to your DHCP server/router
- Find device: "UG65-XXXXXX" (MAC address)
- Note IP address (e.g., 192.168.1.100)

Method 2: Milesight Toolbox (Windows/Mac)
- Download: https://www.milesight-iot.com/support/downloads/
- Run Milesight Device Manager
- Scan network for UG65 devices
- Double-click device to open web interface

Method 3: Default IP (if static IP configured)
- Default: 192.168.1.1/24
- Connect laptop directly to gateway Ethernet port
- Set laptop IP: 192.168.1.100/24

Login Credentials:
URL: http://<gateway-ip>
Username: admin
Password: <printed on gateway label>
```

**Step 3: Initial Configuration**

```
Web Interface Navigation:

1. Change Admin Password (REQUIRED):
   Settings > System > Password
   - New password: [Strong password 12+ characters]
   - Confirm password
   - Click "Apply"

2. Set Hostname:
   Settings > System > General
   - Device Name: ug65-smdh-<tenant_id>-<site_id>
   - Description: SMDH Gateway - <Tenant Name> - <Site Name>
   - Click "Apply"

3. Configure Network:
   Settings > Network > Ethernet
   - Static IP: <site-specific IP>
   - Subnet Mask: <site-specific>
   - Gateway: <site-specific>
   - Primary DNS: 8.8.8.8
   - Secondary DNS: 1.1.1.1
   - Click "Apply"

4. Set Time Zone:
   Settings > System > Time
   - Time Zone: Europe/London (or site-specific)
   - NTP Server: pool.ntp.org
   - Enable NTP: [YES]
   - Click "Apply"

5. Configure LoRaWAN Region:
   Network Server > General
   - Region: EU868 (for UK/Europe)
   - Sub-Band: All channels (default)
   - Class B Beacon: Disabled
   - Class C Timeout: 60 seconds
   - Click "Apply"
```

#### 12.3.2 LoRaWAN Network Server Settings

**Create Application Profile:**

```
Navigate: Network Server > Application > [+] Add Application

Application Configuration:
┌────────────────────────────────────────────────────────┐
│ Application Name: smdh_<tenant_id>_production         │
│ Description: SMDH - <Tenant Name>                     │
│ Auto-Add Devices: Disabled                            │
│ Payload Format: LoRaWAN                               │
│ Payload Codec: JavaScript (Section 12.3.5)           │
└────────────────────────────────────────────────────────┘

[Save Application]
```

**Configure Payload Codec (for DevTank/Custom Sensors):**

```
Navigate: Network Server > Application > smdh_<tenant_id>_production > Codec

Codec Type: JavaScript Decoder

Paste JavaScript Decoder Function:
(See Section 11.3 for DevTank decoder)
(See Section 12.3.5 for generic codec template)

[Save Codec]
```

#### 12.3.3 Device Registration (LoRaWAN Sensors)

**OTAA (Over-The-Air Activation) - Recommended:**

```
Navigate: Network Server > Application > smdh_<tenant_id>_production > [+] Add Device

Device Configuration:
┌────────────────────────────────────────────────────────┐
│ Device Profile                                         │
│ ├─ Name: devtank_osm_<device_id>                      │
│ ├─ Description: DevTank OSM - <Location>              │
│ ├─ Activation: OTAA                                   │
│ └─ Class: Class A                                     │
│                                                        │
│ Device EUI (DevEUI): [64-bit hex]                     │
│   Example: A840410000000123                           │
│   Source: Device label or OSM Config GUI              │
│                                                        │
│ Application Key (AppKey): [128-bit hex]               │
│   Example: 00112233445566778899AABBCCDDEEFF           │
│   Source: Generated by OSM Config GUI                 │
│   Security: Store securely, never transmit in clear   │
│                                                        │
│ Device Profile Settings:                              │
│ ├─ MAC Version: 1.0.3                                 │
│ ├─ Regional Parameters: RP001 Regional Parameters 1.0.3│
│ ├─ Max EIRP: 16 dBm                                   │
│ ├─ Supports Join: Yes                                 │
│ ├─ RX1 Delay: 1 second                                │
│ └─ RX2 Frequency: 869.525 MHz (EU868)                │
└────────────────────────────────────────────────────────┘

[Save Device]
```

**ABP (Activation by Personalization) - Not Recommended:**

```
Only use ABP for testing or legacy devices that don't support OTAA.

Required Parameters:
- Device Address (32-bit)
- Application Session Key (128-bit)
- Network Session Key (128-bit)
- Frame Counters (must track manually)

Security Warning: ABP devices cannot recover from frame counter mismatch.
```

#### 12.3.4 Multi-Tenancy Device Organization

**Organizational Structure:**

```
UG65 Gateway: ug65-smdh-multisite-001
│
├─ Application: smdh_company_a_production
│  ├─ Device: company_a_site_001_osm_001
│  ├─ Device: company_a_site_001_osm_002
│  └─ Device: company_a_site_002_osm_001
│
├─ Application: smdh_company_b_production
│  ├─ Device: company_b_warehouse_osm_001
│  └─ Device: company_b_warehouse_osm_002
│
└─ Application: smdh_company_c_production
   └─ Device: company_c_factory_osm_001
```

**Best Practices:**

1. **Separate Application per Tenant**: Ensures payload routing isolation
2. **Consistent Naming Convention**: `<tenant_id>_<site_id>_<device_type>_<number>`
3. **Documentation**: Maintain spreadsheet of DevEUI → Device mappings
4. **Security**: Different AppKeys per tenant application

#### 12.3.5 Payload Codec Management

**Generic JavaScript Decoder Template:**

```javascript
/**
 * SMDH Generic LoRaWAN Payload Decoder
 * Purpose: Decode sensor binary payloads to JSON
 * Gateway: Milesight UG65
 */

function decodeUplink(input) {
  var bytes = input.bytes;
  var fPort = input.fPort;

  var decoded = {
    data: {},
    warnings: [],
    errors: [],
  };

  try {
    // Example: DevTank OSM decoder (binary protocol)
    if (fPort === 2) {
      decoded.data = decodeDevTankPayload(bytes);
    }
    // Example: Milesight EM300 (built-in decoder)
    else if (fPort === 85) {
      decoded.data = decodeMilesightEM300(bytes);
    }
    // Generic catch-all: return raw hex
    else {
      decoded.data = {
        raw: bytesToHex(bytes),
      };
      decoded.warnings.push("Unknown fPort: " + fPort);
    }
  } catch (error) {
    decoded.errors.push("Decode error: " + error.message);
  }

  return decoded;
}

// DevTank OSM binary decoder (see Section 11.3 for complete implementation)
function decodeDevTankPayload(bytes) {
  var pos = 0;
  var data = {};

  // Protocol version
  var protocol_version = bytes[pos++];
  if (protocol_version !== 1) {
    throw new Error("Unsupported protocol version: " + protocol_version);
  }

  // Parse measurements (4-byte name + 2-byte value little-endian)
  while (pos < bytes.length) {
    var name = "";
    for (var i = 0; i < 4; i++) {
      if (bytes[pos] !== 0) {
        name += String.fromCharCode(bytes[pos]);
      }
      pos++;
    }

    if (name.length === 0) break;

    var value = bytes[pos] | (bytes[pos + 1] << 8);
    pos += 2;

    // Handle signed temperature
    if (name === "TEMP" && value > 32767) {
      value = value - 65536;
    }

    data[name] = value;
  }

  return data;
}

// Utility: Convert byte array to hex string
function bytesToHex(bytes) {
  return Array.from(bytes)
    .map((byte) => ("0" + byte.toString(16)).slice(-2))
    .join("");
}

// Export for TTN v3 compatibility
function Decoder(bytes, fPort) {
  return decodeUplink({ bytes: bytes, fPort: fPort }).data;
}
```

**Codec Testing:**

```
Navigate: Network Server > Application > Codec > Test

Test Input:
┌────────────────────────────────────────────────────────┐
│ FPort: 2                                               │
│ Payload (Hex): 01424154002800CC31002301              │
│                                                        │
│ [Test Decoder]                                         │
│                                                        │
│ Expected Output:                                       │
│ {                                                      │
│   "BAT": 10280,    // 10.28V (÷1000)                 │
│   "CC1": 291       // 291 mA                          │
│ }                                                      │
└────────────────────────────────────────────────────────┘
```

### 12.4 MQTT Cloud Integration (AWS IoT Core)

#### 12.4.1 MQTT Configuration Overview

**Architecture:**

```
UG65 Gateway → MQTT/TLS → AWS IoT Core → IoT Rules Engine → Kinesis → Snowflake
```

**Step 1: Generate AWS IoT Core Certificates (IT Operations)**

```bash
# Set variables
export TENANT_ID="company_a"
export SITE_ID="site_001"
export GATEWAY_ID="ug65_001"
export AWS_REGION="eu-west-2"

# Create IoT Thing for gateway
aws iot create-thing \
  --thing-name "smdh-gateway-${TENANT_ID}-${SITE_ID}-${GATEWAY_ID}" \
  --thing-type-name "LoRaWANGateway" \
  --attribute-payload '{
    "attributes": {
      "tenant_id": "'${TENANT_ID}'",
      "site_id": "'${SITE_ID}'",
      "gateway_type": "Milesight_UG65"
    }
  }' \
  --region ${AWS_REGION}

# Generate X.509 certificates
aws iot create-keys-and-certificate \
  --set-as-active \
  --certificate-pem-outfile "${TENANT_ID}-${GATEWAY_ID}-cert.pem" \
  --public-key-outfile "${TENANT_ID}-${GATEWAY_ID}-public.key" \
  --private-key-outfile "${TENANT_ID}-${GATEWAY_ID}-private.key" \
  --region ${AWS_REGION}

# Store certificate ARN from output
export CERT_ARN="arn:aws:iot:eu-west-2:123456789:cert/CERT_ID"

# Download Amazon Root CA certificate
wget https://www.amazontrust.com/repository/AmazonRootCA1.pem

# Attach certificate to thing
aws iot attach-thing-principal \
  --thing-name "smdh-gateway-${TENANT_ID}-${SITE_ID}-${GATEWAY_ID}" \
  --principal "${CERT_ARN}" \
  --region ${AWS_REGION}

# Get IoT endpoint
export IOT_ENDPOINT=$(aws iot describe-endpoint \
  --endpoint-type iot:Data-ATS \
  --region ${AWS_REGION} \
  --query 'endpointAddress' \
  --output text)

echo "IoT Endpoint: ${IOT_ENDPOINT}"
```

**Step 2: Create IoT Policy**

```bash
# Create policy file
cat > iot-gateway-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "iot:Connect",
      "Resource": "arn:aws:iot:${AWS_REGION}:${ACCOUNT_ID}:client/smdh-gateway-${TENANT_ID}-*"
    },
    {
      "Effect": "Allow",
      "Action": "iot:Publish",
      "Resource": [
        "arn:aws:iot:${AWS_REGION}:${ACCOUNT_ID}:topic/smdh/${TENANT_ID}/sensor-data",
        "arn:aws:iot:${AWS_REGION}:${ACCOUNT_ID}:topic/smdh/${TENANT_ID}/gateway-status"
      ]
    },
    {
      "Effect": "Allow",
      "Action": "iot:Subscribe",
      "Resource": "arn:aws:iot:${AWS_REGION}:${ACCOUNT_ID}:topicfilter/smdh/${TENANT_ID}/commands/#"
    },
    {
      "Effect": "Allow",
      "Action": "iot:Receive",
      "Resource": "arn:aws:iot:${AWS_REGION}:${ACCOUNT_ID}:topic/smdh/${TENANT_ID}/commands/*"
    }
  ]
}
EOF

# Create policy
aws iot create-policy \
  --policy-name "smdh-gateway-${TENANT_ID}-policy" \
  --policy-document file://iot-gateway-policy.json \
  --region ${AWS_REGION}

# Attach policy to certificate
aws iot attach-policy \
  --policy-name "smdh-gateway-${TENANT_ID}-policy" \
  --target "${CERT_ARN}" \
  --region ${AWS_REGION}
```

**Step 3: Prepare Certificate Package**

```bash
# Create certificate package directory
mkdir -p "ug65_certs_${TENANT_ID}_${GATEWAY_ID}"

# Copy certificates
cp "${TENANT_ID}-${GATEWAY_ID}-cert.pem" "ug65_certs_${TENANT_ID}_${GATEWAY_ID}/client-cert.pem"
cp "${TENANT_ID}-${GATEWAY_ID}-private.key" "ug65_certs_${TENANT_ID}_${GATEWAY_ID}/client-key.key"
cp AmazonRootCA1.pem "ug65_certs_${TENANT_ID}_${GATEWAY_ID}/root-ca.pem"

# Create configuration file
cat > "ug65_certs_${TENANT_ID}_${GATEWAY_ID}/mqtt_config.txt" <<EOF
MQTT Configuration for UG65 Gateway
===================================

Gateway: ${GATEWAY_ID}
Tenant: ${TENANT_ID}
Site: ${SITE_ID}

MQTT Settings:
--------------
MQTT Broker: ${IOT_ENDPOINT}
Port: 8883
Protocol: MQTT v3.1.1 or v5.0
Client ID: smdh-gateway-${TENANT_ID}-${SITE_ID}-${GATEWAY_ID}

TLS/SSL: Enabled
  - CA Certificate: root-ca.pem
  - Client Certificate: client-cert.pem
  - Client Private Key: client-key.key

Topics:
  - Publish: smdh/${TENANT_ID}/sensor-data
  - QoS: 1 (At least once)
  - Retain: false

Security: X.509 certificate authentication
EOF

# Create ZIP package
zip -r "ug65_certs_${TENANT_ID}_${GATEWAY_ID}.zip" "ug65_certs_${TENANT_ID}_${GATEWAY_ID}/"

echo "Certificate package created: ug65_certs_${TENANT_ID}_${GATEWAY_ID}.zip"
echo "Deliver this package to the onsite configurer"
```

**Step 4: Configure UG65 MQTT Settings (Onsite)**

```
Navigate: Network Server > Application > smdh_<tenant_id>_production > MQTT Integration

MQTT Configuration:
┌────────────────────────────────────────────────────────┐
│ Enable MQTT: [YES]                                     │
│                                                        │
│ MQTT Server: <from mqtt_config.txt>                   │
│   Example: a1b2c3d4e5f6g7-ats.iot.eu-west-2.amazonaws.com │
│                                                        │
│ Port: 8883                                             │
│ Protocol: MQTT v3.1.1                                  │
│ Client ID: smdh-gateway-<tenant_id>-<site_id>-<gw_id> │
│                                                        │
│ TLS/SSL Settings:                                      │
│ ├─ Enable TLS: [YES]                                  │
│ ├─ TLS Version: TLS 1.2                               │
│ ├─ CA Certificate: [Upload] root-ca.pem               │
│ ├─ Client Certificate: [Upload] client-cert.pem       │
│ └─ Client Private Key: [Upload] client-key.key        │
│                                                        │
│ MQTT Topics:                                           │
│ ├─ Publish Topic: smdh/<tenant_id>/sensor-data        │
│ ├─ QoS Level: 1 (At least once delivery)              │
│ └─ Retain: false                                       │
│                                                        │
│ Payload Settings:                                      │
│ ├─ Format: JSON                                        │
│ ├─ Include Device EUI: [YES]                          │
│ ├─ Include Timestamp: [YES]                           │
│ ├─ Include RSSI/SNR: [YES]                            │
│ └─ Decoded Payload: [YES]                             │
│                                                        │
│ Connection Settings:                                   │
│ ├─ Keep Alive: 60 seconds                             │
│ ├─ Clean Session: false (persistent session)          │
│ ├─ Auto Reconnect: [YES]                              │
│ └─ Reconnect Interval: 5 seconds (exponential backoff)│
│                                                        │
│ Buffer Settings:                                       │
│ ├─ Offline Buffer: 10,000 messages                    │
│ └─ Buffer Strategy: Store-and-forward                 │
└────────────────────────────────────────────────────────┘

[Save Configuration]
```

**Step 5: Test MQTT Connection**

```
Navigate: Network Server > Application > MQTT Integration > Connection Status

Expected Status:
┌────────────────────────────────────────────────────────┐
│ MQTT Status: Connected                                 │
│ Last Connected: 2025-11-20 14:32:15                    │
│ Messages Sent: 0                                       │
│ Messages Failed: 0                                     │
│ Connection Uptime: 00:05:23                            │
└────────────────────────────────────────────────────────┘

Troubleshooting:
- Status "Disconnected": Check certificate files
- Status "Authentication Failed": Verify IoT Policy attached to certificate
- Status "Connection Refused": Verify IoT endpoint URL (must end with -ats.iot.eu-west-2.amazonaws.com)
```

#### 12.4.2 MQTT Payload Format

**Example MQTT Payload (Published to AWS IoT Core):**

```json
{
  "applicationID": "1",
  "applicationName": "smdh_company_a_production",
  "deviceName": "company_a_site_001_osm_001",
  "devEUI": "a840410000000123",
  "timestamp": "2025-11-20T14:35:12.456789Z",
  "fPort": 2,
  "data": {
    "BAT": 3624,
    "TEMP": 2268,
    "HUMI": 4500,
    "PM25": 12,
    "VOC": 150,
    "CC1": 291
  },
  "rxInfo": [
    {
      "gatewayID": "smdh-gateway-company-a-site-001-ug65-001",
      "name": "ug65-smdh-company-a-site-001",
      "time": "2025-11-20T14:35:12.456789Z",
      "rssi": -85,
      "loRaSNR": 8.5,
      "channel": 3,
      "rfChain": 1,
      "location": {
        "latitude": 51.5074,
        "longitude": -0.1278,
        "altitude": 10
      }
    }
  ],
  "txInfo": {
    "frequency": 868300000,
    "dr": 5,
    "adr": true
  }
}
```

### 12.5 HTTP Cloud Integration (API Gateway)

#### 12.5.1 HTTP Configuration Overview

**Architecture:**

```
UG65 Gateway → HTTPS POST → API Gateway → Lambda → Snowpipe Streaming → Snowflake
```

**Step 1: Generate API Key (IT Operations)**

```bash
# Generate strong API key
export API_KEY="smdh-prod-$(openssl rand -hex 32)"
echo "Generated API Key: ${API_KEY}"

# Create API key in API Gateway
aws apigateway create-api-key \
  --name "smdh-tenant-${TENANT_ID}-ug65-prod" \
  --description "API key for UG65 gateway - ${TENANT_ID}" \
  --enabled \
  --value "${API_KEY}" \
  --region eu-west-2

# Store API key ID
export API_KEY_ID=$(aws apigateway get-api-keys \
  --name-query "smdh-tenant-${TENANT_ID}-ug65-prod" \
  --query 'items[0].id' \
  --output text \
  --region eu-west-2)

# Associate with usage plan
aws apigateway create-usage-plan-key \
  --usage-plan-id ${USAGE_PLAN_ID} \
  --key-id ${API_KEY_ID} \
  --key-type API_KEY \
  --region eu-west-2

# Store mapping in DynamoDB
aws dynamodb put-item \
  --table-name smdh_api_key_mapping \
  --item '{
    "api_key": {"S": "'${API_KEY}'"},
    "tenant_id": {"S": "'${TENANT_ID}'"},
    "tenant_name": {"S": "<Tenant Company Name>"},
    "gateway_id": {"S": "'${GATEWAY_ID}'"},
    "status": {"S": "active"},
    "created_at": {"S": "'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'"}
  }' \
  --region eu-west-2

echo "API Key registered and mapped to tenant: ${TENANT_ID}"
```

**Step 2: Prepare Configuration Package**

```bash
# Create configuration file
cat > "ug65_http_config_${TENANT_ID}_${GATEWAY_ID}.txt" <<EOF
HTTP Configuration for UG65 Gateway
===================================

Gateway: ${GATEWAY_ID}
Tenant: ${TENANT_ID}
Site: ${SITE_ID}

HTTP Settings:
--------------
Protocol: HTTPS
Method: POST
URL: https://${API_GATEWAY_ID}.execute-api.eu-west-2.amazonaws.com/prod/ingest

Headers:
  Header 1:
    Name: x-api-key
    Value: ${API_KEY}

  Header 2:
    Name: Content-Type
    Value: application/json

Payload Format: JSON (decoded sensor data)
Retry Settings:
  - Max Retries: 3
  - Retry Interval: 5 seconds (exponential backoff)
  - Offline Buffer: 10,000 messages

Security: API Key authentication
EOF

echo "Configuration file created: ug65_http_config_${TENANT_ID}_${GATEWAY_ID}.txt"
echo "Deliver this file to the onsite configurer"
```

**Step 3: Configure UG65 HTTP Settings (Onsite)**

```
Navigate: Network Server > Application > smdh_<tenant_id>_production > HTTP Integration

HTTP Configuration:
┌────────────────────────────────────────────────────────┐
│ Enable HTTP: [YES]                                     │
│                                                        │
│ Protocol: HTTPS                                        │
│ Method: POST                                           │
│ URL: <from configuration file>                         │
│   Example: https://abc123def.execute-api.eu-west-2.amazonaws.com/prod/ingest │
│                                                        │
│ Headers:                                               │
│ ┌────────────────────────────────────────────────┐    │
│ │ Header 1:                                      │    │
│ │   Name: x-api-key                              │    │
│ │   Value: <API_KEY from config file>            │    │
│ │                                                │    │
│ │ Header 2:                                      │    │
│ │   Name: Content-Type                           │    │
│ │   Value: application/json                      │    │
│ └────────────────────────────────────────────────┘    │
│                                                        │
│ Payload Settings:                                      │
│ ├─ Format: JSON                                        │
│ ├─ Include Device EUI: [YES]                          │
│ ├─ Include Timestamp: [YES]                           │
│ ├─ Include RSSI/SNR: [YES]                            │
│ └─ Decoded Payload: [YES]                             │
│                                                        │
│ Retry Settings:                                        │
│ ├─ Enable Retry: [YES]                                │
│ ├─ Max Retries: 3                                     │
│ ├─ Retry Interval: 5 seconds                          │
│ └─ Backoff Strategy: Exponential                      │
│                                                        │
│ Buffer Settings:                                       │
│ ├─ Offline Buffer: 10,000 messages                    │
│ └─ Buffer Strategy: Store-and-forward                 │
│                                                        │
│ Timeout: 30 seconds                                    │
└────────────────────────────────────────────────────────┘

[Save Configuration]
```

**Step 4: Test HTTP Integration**

```
Navigate: Network Server > Application > HTTP Integration > Test

Test Configuration:
┌────────────────────────────────────────────────────────┐
│ [Send Test Message]                                    │
│                                                        │
│ Expected Response:                                     │
│   HTTP/1.1 200 OK                                      │
│   Content-Type: application/json                       │
│   {                                                    │
│     "message": "Data ingested successfully"            │
│   }                                                    │
│                                                        │
│ Troubleshooting:                                       │
│ - 403 Forbidden: Check API key value                  │
│ - 429 Too Many Requests: Rate limit exceeded          │
│ - 500 Internal Server Error: Check Lambda logs        │
│ - Timeout: Check URL and network connectivity         │
└────────────────────────────────────────────────────────┘
```

### 12.6 Physical Deployment Procedures

#### 12.6.1 Site Survey and Planning

**Pre-Deployment Checklist:**

```
Site Information:
- [ ] Site Name: _______________________
- [ ] Site Address: _____________________
- [ ] Contact Name: _____________________
- [ ] Contact Phone: ____________________
- [ ] Preferred Date: ___________________

Physical Requirements:
- [ ] Power available (PoE or 12V DC)
- [ ] Ethernet available (DHCP or static IP)
- [ ] Mounting location identified (elevated, central)
- [ ] Access to mounting location (ladder required?)
- [ ] Gateway placement away from metal/concrete obstructions

Network Requirements:
- [ ] Outbound HTTPS (port 443) allowed
- [ ] Outbound MQTTS (port 8883) allowed (if using MQTT)
- [ ] DNS resolution working (8.8.8.8, 1.1.1.1)
- [ ] Firewall exceptions documented

Coverage Requirements:
- [ ] Number of sensors: _______
- [ ] Maximum distance from gateway: _______ meters
- [ ] Indoor or outdoor sensors: _______
- [ ] Number of floors/walls between gateway and sensors: _______
```

**Coverage Planning:**

```
LoRaWAN Range Estimates:

Indoor (Office Environment):
- Open floor plan: 50-150 meters
- Light walls (drywall): 30-100 meters
- Heavy walls (concrete): 20-50 meters
- Multiple floors: 20-30 meters per floor

Industrial Environment:
- Open warehouse: 100-300 meters
- Light obstructions: 50-150 meters
- Heavy machinery: 30-100 meters
- Metal racks/shelving: 20-50 meters

Outdoor (Line of Sight):
- Clear line of sight: 2-5 km
- Light vegetation: 1-3 km
- Urban environment: 500-2000 meters

Coverage Improvement:
- Elevate gateway (wall-mount at 2-3 meters height)
- Avoid metal enclosures or RF-blocking materials
- Use external antenna for outdoor applications
- Deploy multiple gateways for large sites (gateway-to-gateway handoff)
```

#### 12.6.2 Installation Procedure

**Tools Required:**

- Drill with masonry/wood bits (if wall-mounting)
- Screwdriver (Phillips)
- Cable tester (Ethernet)
- Laptop with Ethernet port
- Ladder (if mounting high)
- Label maker (for cable labelling)

**Installation Steps:**

```
Step 1: Pre-Installation Testing
  1. Unbox gateway and verify contents:
     - UG65 gateway unit
     - 3dBi fiberglass antenna (RP-SMA)
     - PoE injector (if using PoE)
     - 12V DC power adapter (if not using PoE)
     - Wall-mount bracket
     - Screws and anchors

  2. Bench test gateway:
     - Connect Ethernet to laptop
     - Apply power (PoE or 12V adapter)
     - Verify LEDs illuminate (Power, Network, LoRa)
     - Access web interface (192.168.1.1 or DHCP IP)
     - Verify firmware version (v2.10 or later)

Step 2: Physical Installation
  1. Mark mounting locations:
     - Height: 2-3 meters above floor
     - Central to coverage area
     - Away from metal objects
     - Access to Ethernet and power

  2. Mount bracket:
     - Drill pilot holes (if needed)
     - Insert wall anchors
     - Secure bracket with screws
     - Verify bracket is level

  3. Attach antenna:
     - Hand-tighten RP-SMA antenna
     - Orient antenna vertically (perpendicular to floor)
     - Do NOT overtighten (finger-tight only)

  4. Mount gateway:
     - Hang gateway on bracket
     - Secure with retaining clip
     - Verify gateway is stable

Step 3: Cabling
  1. Route Ethernet cable:
     - Use cable clips to secure to wall
     - Avoid sharp bends
     - Label cable at both ends (e.g., "SMDH Gateway UG65-001")

  2. Connect Ethernet:
     - If using PoE: Connect to PoE injector
     - If using DC: Connect Ethernet directly, attach 12V adapter
     - Verify cable click into RJ45 port

  3. Apply power:
     - Wait 60 seconds for boot sequence
     - Verify LED status:
       ✓ Power (Green): Solid
       ✓ Network (Yellow): Solid or Blinking (acquiring IP)
       ✓ LoRa (Blue): Blinking (radio active)

Step 4: Configuration (see Section 12.3 or 12.4/12.5)
  - Access web interface
  - Change default password
  - Configure network settings
  - Set time zone
  - Configure LoRaWAN region
  - Add application and devices
  - Configure MQTT or HTTP integration

Step 5: Validation
  - Power on a sensor device near gateway
  - Verify device joins network (check Devices page)
  - Verify uplink messages received (check Traffic page)
  - Verify data appears in Snowflake (SQL query)
  - Document installation (photos, IP address, credentials)
```

#### 12.6.3 Post-Installation Documentation

```
Gateway Installation Report
===========================

Site Information:
- Site Name: _______________________
- Installation Date: _______________
- Installed By: ____________________

Gateway Information:
- Gateway Model: Milesight UG65
- Serial Number: ___________________
- Firmware Version: ________________
- MAC Address: _____________________

Network Configuration:
- IP Address: ______________________
- Subnet Mask: _____________________
- Gateway: _________________________
- DNS: _____________________________

LoRaWAN Configuration:
- Region: EU868
- Network Server: Built-in
- Number of Applications: __________
- Number of Devices: _______________

Cloud Integration:
- Protocol: MQTT / HTTP (circle one)
- Endpoint: ________________________
- Tenant ID: _______________________

Coverage Testing:
- Number of sensors deployed: ______
- Furthest sensor distance: _______ meters
- Sensor RSSI range: -___ to -___ dBm
- Sensor SNR range: ___ to ___ dB

Issues/Notes:
_______________________________________
_______________________________________
_______________________________________

Photos:
- [ ] Gateway installation (front view)
- [ ] Gateway installation (cabling)
- [ ] Web interface screenshots
- [ ] Coverage map (if applicable)
```

### 12.7 Maintenance and Operations

#### 12.7.1 Firmware Updates

**Current Firmware Versions:**

- Gateway Firmware: v2.10 (January 2025)
- Network Server: v2.10 (integrated)

**Firmware Update Procedure:**

```
Pre-Update Checklist:
- [ ] Backup gateway configuration (Settings > System > Backup)
- [ ] Download latest firmware from Milesight website
- [ ] Verify firmware file integrity (checksum)
- [ ] Schedule maintenance window (sensors will be offline during update)
- [ ] Notify users of maintenance window

Update Steps:

1. Navigate: Settings > System > Firmware Upgrade

2. Upload Firmware File:
   - Click "Choose File"
   - Select .bin firmware file
   - Click "Upload"

3. Wait for Upload:
   - Progress bar will show upload status
   - Do NOT power off gateway during upload
   - Upload time: ~60 seconds

4. Gateway Will Reboot:
   - Gateway will automatically reboot
   - LEDs will flash during reboot
   - Reboot time: ~120 seconds
   - Web interface will be unavailable during reboot

5. Verify Update:
   - Login to web interface
   - Navigate: Settings > System > General
   - Verify Firmware Version: v2.10 (or later)
   - Check Network Server > Devices
   - Verify all devices reconnect (may take 5-10 minutes)

6. Post-Update Testing:
   - Verify sensor uplinks are received
   - Check MQTT/HTTP integration status
   - Verify data appears in Snowflake

Rollback Procedure (if needed):
   - If update fails, gateway will automatically rollback to previous firmware
   - If gateway becomes unresponsive, power cycle gateway
   - If still unresponsive, contact Milesight support for recovery procedure
```

#### 12.7.2 Monitoring and Health Checks

**Daily Health Checks (Automated):**

```sql
-- Snowflake query: Gateway health monitoring
SELECT
    gateway_id,
    MAX(iot_timestamp) as last_seen,
    DATEDIFF('minute', MAX(iot_timestamp), CURRENT_TIMESTAMP()) as minutes_offline,
    COUNT(*) as messages_last_hour,
    AVG(rssi) as avg_rssi,
    CASE
        WHEN DATEDIFF('minute', MAX(iot_timestamp), CURRENT_TIMESTAMP()) > 30 THEN 'OFFLINE'
        WHEN COUNT(*) < 10 THEN 'LOW_TRAFFIC'
        WHEN AVG(rssi) < -120 THEN 'WEAK_SIGNAL'
        ELSE 'HEALTHY'
    END as gateway_status
FROM smdh_tenant_${TENANT_ID}.raw.sensor_readings
WHERE iot_timestamp > DATEADD(hour, -1, CURRENT_TIMESTAMP())
GROUP BY gateway_id
ORDER BY minutes_offline DESC;
```

**Weekly Health Checks (Manual):**

```
Navigate: Network Server > Statistics

Check Metrics:
┌────────────────────────────────────────────────────────┐
│ Gateway Statistics (Last 7 Days):                      │
│                                                        │
│ Uptime: 99.8%                                          │
│ Total Uplinks: 42,531                                  │
│ Total Downlinks: 145                                   │
│ Average RSSI: -85 dBm                                  │
│ Average SNR: 8.5 dB                                    │
│ Join Requests: 3 (device reboots)                     │
│ Join Accepts: 3 (100% success)                        │
│ Packet Error Rate: 0.2%                               │
│                                                        │
│ Red Flags:                                             │
│ - Uptime < 95%: Check network connectivity            │
│ - Packet Error Rate > 5%: Check interference sources  │
│ - Join Accept Rate < 90%: Check AppKey configuration  │
└────────────────────────────────────────────────────────┘
```

**Monthly Maintenance:**

```
Maintenance Tasks:
- [ ] Review gateway logs for errors (Settings > System > Logs)
- [ ] Verify firmware is up-to-date
- [ ] Check free disk space (Settings > System > Status)
- [ ] Review device list for offline devices
- [ ] Test backup/restore procedure
- [ ] Verify MQTT/HTTP integration status
- [ ] Review CloudWatch metrics (if using MQTT)
- [ ] Review API Gateway metrics (if using HTTP)
- [ ] Clean antenna connection (dust/moisture)
- [ ] Verify LED indicators operational
```

#### 12.7.3 Certificate Rotation (MQTT Only)

**Certificate Expiration Monitoring:**

```bash
# Check certificate expiration date
openssl x509 -in gateway-cert.pem -noout -enddate

# Example output:
# notAfter=Nov 20 12:00:00 2026 GMT

# Set reminder for 30 days before expiration
# Typical certificate lifetime: 1-2 years
```

**Certificate Rotation Procedure (Zero Downtime):**

```bash
# 1. Generate new certificate
aws iot create-keys-and-certificate \
  --set-as-active \
  --certificate-pem-outfile "${TENANT_ID}-${GATEWAY_ID}-cert-new.pem" \
  --private-key-outfile "${TENANT_ID}-${GATEWAY_ID}-private-new.key" \
  --region ${AWS_REGION}

export NEW_CERT_ARN="<output-from-command>"

# 2. Attach new certificate to thing (allows dual certificates)
aws iot attach-thing-principal \
  --thing-name "smdh-gateway-${TENANT_ID}-${SITE_ID}-${GATEWAY_ID}" \
  --principal "${NEW_CERT_ARN}" \
  --region ${AWS_REGION}

# 3. Attach policy to new certificate
aws iot attach-policy \
  --policy-name "smdh-gateway-${TENANT_ID}-policy" \
  --target "${NEW_CERT_ARN}" \
  --region ${AWS_REGION}

# 4. Upload new certificates to gateway (see Step 4 in Section 12.4.1)
#    Gateway will now have two valid certificates

# 5. Wait for confirmation gateway is using new certificate
#    Check MQTT connection status in web interface

# 6. Detach old certificate from thing
aws iot detach-thing-principal \
  --thing-name "smdh-gateway-${TENANT_ID}-${SITE_ID}-${GATEWAY_ID}" \
  --principal "${OLD_CERT_ARN}" \
  --region ${AWS_REGION}

# 7. Deactivate old certificate
aws iot update-certificate \
  --certificate-id ${OLD_CERT_ID} \
  --new-status INACTIVE \
  --region ${AWS_REGION}

# 8. Delete old certificate (after 30-day grace period)
aws iot delete-certificate \
  --certificate-id ${OLD_CERT_ID} \
  --region ${AWS_REGION}
```

### 12.8 Troubleshooting

#### 12.8.1 Common Issues and Solutions

| Symptom                           | Possible Cause               | Solution                                                   |
| --------------------------------- | ---------------------------- | ---------------------------------------------------------- |
| **Gateway offline (no LEDs)**     | No power                     | Check power connection (PoE or 12V adapter)                |
| **Network LED yellow (blinking)** | No Ethernet connection       | Check Ethernet cable, verify link lights on switch         |
| **Network LED off**               | No IP address                | Check DHCP server or configure static IP                   |
| **LoRa LED off**                  | LoRaWAN radio disabled       | Enable in Network Server > General                         |
| **Cannot access web interface**   | Wrong IP address             | Use Milesight Toolbox to discover IP                       |
| **Devices not joining**           | Wrong AppKey                 | Verify AppKey matches device configuration                 |
| **Devices not joining**           | Wrong region                 | Verify EU868 selected (UK/Europe)                          |
| **Uplinks not received**          | Codec not configured         | Add JavaScript decoder (Section 12.3.5)                    |
| **MQTT disconnected**             | Certificate error            | Verify certificate files uploaded correctly                |
| **MQTT authentication failed**    | Wrong IoT endpoint           | Verify endpoint ends with -ats.iot.eu-west-2.amazonaws.com |
| **HTTP 403 error**                | Wrong API key                | Verify API key in header matches DynamoDB entry            |
| **HTTP timeout**                  | Wrong URL or firewall        | Verify URL, check outbound HTTPS allowed                   |
| **Data not in Snowflake**         | Lambda error                 | Check CloudWatch logs for Lambda errors                    |
| **Weak RSSI (< -120 dBm)**        | Long distance or obstruction | Move gateway or sensor closer, elevate gateway             |
| **High packet loss (> 5%)**       | RF interference              | Change LoRaWAN channel, identify interference source       |

#### 12.8.2 Diagnostic Procedures

**Network Connectivity Test:**

```bash
# From gateway CLI (SSH or console)
ping -c 4 8.8.8.8                    # Check internet connectivity
nslookup google.com                   # Check DNS resolution
curl -I https://api.amazon.com        # Check HTTPS outbound

# Expected outputs:
# - Ping: 4 packets transmitted, 4 received, 0% packet loss
# - DNS: Returns IP address for google.com
# - HTTPS: HTTP/1.1 200 OK
```

**LoRaWAN Radio Test:**

```
Navigate: Network Server > Gateway > Radio

Radio Status:
┌────────────────────────────────────────────────────────┐
│ LoRa Radio: ENABLED                                    │
│ Region: EU868                                          │
│ Frequency: 868.1-868.5 MHz                             │
│ TX Power: 27 dBm                                       │
│ Channels Active: 8/8                                   │
│ Uplinks (Last Hour): 42                                │
│ Downlinks (Last Hour): 0                               │
│                                                        │
│ If "LoRa Radio: DISABLED":                             │
│   → Settings > Network Server > General               │
│   → Enable Network Server: [YES]                      │
│   → Restart gateway                                   │
└────────────────────────────────────────────────────────┘
```

**MQTT Connection Test (CLI):**

```bash
# Test MQTT connection using mosquitto_pub (on laptop)
mosquitto_pub \
  --cafile root-ca.pem \
  --cert client-cert.pem \
  --key client-key.key \
  -h ${IOT_ENDPOINT} \
  -p 8883 \
  -q 1 \
  -t "smdh/${TENANT_ID}/sensor-data" \
  -m '{"test": "message"}'

# Expected output: (no error)
# If error: Check certificate files, endpoint URL, IoT policy
```

**HTTP Integration Test (CLI):**

```bash
# Test HTTP integration using curl
curl -X POST \
  -H "x-api-key: ${API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"test": "message", "applicationName": "smdh_'${TENANT_ID}'_production"}' \
  https://${API_GATEWAY_ID}.execute-api.eu-west-2.amazonaws.com/prod/ingest

# Expected output:
# {"message":"Data ingested successfully"}

# If 403 error: Check API key
# If timeout: Check URL and network connectivity
```

#### 12.8.3 Support Escalation

**Level 1: Self-Service (Onsite Team)**

- Reboot gateway (power cycle)
- Verify cables and power
- Check LED indicators
- Review gateway logs (Settings > System > Logs)

**Level 2: IT Operations (Remote)**

- Review Snowflake data flow
- Check Lambda logs (CloudWatch)
- Review IoT Core metrics
- Verify API Gateway status
- Test certificates/API keys

**Level 3: Milesight Support**

- Contact: support@milesight-iot.com
- Required information:
  - Gateway serial number
  - Firmware version
  - Detailed description of issue
  - Gateway configuration backup (Settings > System > Backup)
  - Gateway logs (Settings > System > Logs > Export)

### 12.9 Cost Implications

**UG65 Gateway Costs (per gateway):**

| Component                    | Cost Type | Estimate (GBP)             |
| ---------------------------- | --------- | -------------------------- |
| **Gateway Hardware**         | One-time  | £350-450                   |
| **PoE Injector** (if needed) | One-time  | £30-50                     |
| **Antenna** (included)       | One-time  | Included                   |
| **Network Connection**       | Monthly   | £0-50 (site-dependent)     |
| **AWS IoT Core** (MQTT)      | Monthly   | £5-15/gateway              |
| **API Gateway** (HTTP)       | Monthly   | £1-5/gateway               |
| **Maintenance**              | Annual    | £50-100 (firmware updates) |

**Notes:**

- Gateway supports up to 2000 devices (amortize cost across sensors)
- MQTT costs scale with connection time (persistent connection)
- HTTP costs scale with request volume (per-message pricing)
- Typical ROI: 12-18 months (compared to cellular IoT devices)

**Cost Optimization:**

```
Single Gateway Multi-Tenant Deployment:
- Deploy one UG65 per site (not per tenant)
- Use Applications to segregate tenant data
- Share gateway cost across multiple tenants
- Example: 3 tenants × 10 sensors each = 30 sensors on one gateway
- Cost per tenant: £150 hardware + £5/month AWS = £150 + £60/year
```

### 12.10 Integration with SMDH Architecture

The Milesight UG65 gateway integrates seamlessly with the existing SMDH platform architecture:

```
┌─────────────────────────────────────────────────────┐
│                  UG65 Gateway                       │
│                                                     │
│  LoRaWAN     Network      Application              │
│  Radio    →  Server    →  Server    →  MQTT/HTTP   │
│  (868MHz)    (Built-in)   (Built-in)    Client     │
└────────────────────────────────┬────────────────────┘
                                 │
                    ┌────────────┴─────────────┐
                    │                          │
                    ▼                          ▼
        ┌──────────────────┐      ┌──────────────────┐
        │  AWS IoT Core    │      │  API Gateway     │
        │  (MQTT)          │      │  (HTTP)          │
        └────────┬─────────┘      └────────┬─────────┘
                 │                         │
                 ▼                         ▼
        ┌──────────────────┐      ┌──────────────────┐
        │  IoT Rules       │      │  Lambda          │
        │  Engine          │      │  Validation      │
        └────────┬─────────┘      └────────┬─────────┘
                 │                         │
                 ▼                         │
        ┌──────────────────┐              │
        │  Kinesis         │              │
        │  Data Streams    │              │
        └────────┬─────────┘              │
                 │                        │
                 │    ┌───────────────────┘
                 │    │
                 ▼    ▼
        ┌──────────────────────────────────┐
        │  Snowflake Openflow / Snowpipe   │
        └────────────┬─────────────────────┘
                     │
                     ▼
        ┌──────────────────────────────────┐
        │  Snowflake Tenant Database       │
        │  - Raw Tables                    │
        │  - Normalized Dynamic Tables     │
        │  - Aggregated Dynamic Tables     │
        └────────────┬─────────────────────┘
                     │
                     ▼
        ┌──────────────────────────────────┐
        │  Streamlit Portal / Power BI     │
        └──────────────────────────────────┘
```

**Key Integration Points:**

1. **No Architectural Changes Required**: UG65 leverages existing AWS and Snowflake infrastructure
2. **Protocol Flexibility**: Supports both MQTT (IoT Core) and HTTP (API Gateway) paths
3. **Multi-Tenant Support**: Built-in Applications provide tenant segregation at gateway level
4. **Scalability**: Single gateway supports up to 2000 devices across multiple tenants
5. **Security**: X.509 certificates (MQTT) or API keys (HTTP) enforce tenant isolation
6. **Data Quality**: Built-in payload decoder ensures clean data enters Snowflake
7. **Operational Simplicity**: Integrated Network Server eliminates external dependencies

---

## 13. Appendices

### 13.1 Glossary

| Term                   | Definition                                                                    |
| ---------------------- | ----------------------------------------------------------------------------- |
| **API Gateway**        | AWS managed service providing REST API endpoints with authentication          |
| **API Key**            | Static authentication credential (256-bit random string)                      |
| **CloudWatch**         | AWS monitoring service (logs, metrics, alarms)                                |
| **Cortex ML**          | Snowflake's built-in machine learning functions                               |
| **DevEUI**             | Device Extended Unique Identifier - 64-bit LoRaWAN device address             |
| **DevTank OSM**        | OpenSmartMonitor - Multi-sensor IoT device (air quality, energy, environment) |
| **Dynamic Table**      | Snowflake continuously updated materialized view                              |
| **DynamoDB**           | AWS NoSQL database (API key → tenant_id mapping)                              |
| **JWT**                | JSON Web Token - cryptographically signed authentication token                |
| **Lambda**             | AWS serverless compute service                                                |
| **LoRaWAN**            | Low-power wireless protocol for IoT (2-5km range, 868 MHz)                    |
| **OSM Config GUI**     | Web-based configuration interface for DevTank sensors (USB-connected)         |
| **PM2.5**              | Particulate Matter 2.5µm - Air quality measurement in µg/m³                   |
| **Row Access Policy**  | Snowflake query filtering for multi-tenancy                                   |
| **Secrets Manager**    | AWS service for storing secrets with encryption                               |
| **Snowpipe Streaming** | Snowflake low-latency ingestion API (<10 seconds)                             |
| **Streamlit**          | Snowflake-native Python web application framework                             |
| **TLS**                | Transport Layer Security - HTTPS encryption (v1.3)                            |
| **UG65**               | Milesight LoRaWAN gateway with built-in Network Server                        |
| **VOC**                | Volatile Organic Compounds - Air quality measurement in ppb                   |

### 13.2 Reference Documentation

**Snowflake:**

- Snowpipe Streaming API: https://docs.snowflake.com/en/user-guide/data-load-snowpipe-streaming
- Key Pair Authentication: https://docs.snowflake.com/en/user-guide/key-pair-auth
- Dynamic Tables: https://docs.snowflake.com/en/user-guide/dynamic-tables-intro
- Streamlit: https://docs.snowflake.com/en/developer-guide/streamlit/about-streamlit
- Cortex ML: https://docs.snowflake.com/en/user-guide/ml-functions
- IAM & RBAC: https://docs.snowflake.com/en/user-guide/security-access-control

**AWS:**

- API Gateway: https://docs.aws.amazon.com/apigateway/
- Lambda: https://docs.aws.amazon.com/lambda/
- DynamoDB: https://docs.aws.amazon.com/dynamodb/
- Secrets Manager: https://docs.aws.amazon.com/secretsmanager/
- IoT Core: https://docs.aws.amazon.com/iot/
- Kinesis Data Streams: https://docs.aws.amazon.com/kinesis/

**Milesight:**

- UG65 User Guide v2.10 (January 2025)
- HTTP Application Configuration: Section 3.2.2.2

**DevTank:**

- OSM Config GUI: https://osm-config.devtank.co.uk
- DevTank Support: https://devtank.co.uk/contact
- SMDH DevTank Deployment Guide: [See dedicated guide document]

**Power BI:**

- Snowflake Connector: https://learn.microsoft.com/en-us/power-bi/connect-data/desktop-connect-snowflake

### 13.3 Tenant Onboarding Checklist

**AWS Configuration:**

- [ ] Generate API key (256-bit)
- [ ] Create API Gateway API key resource
- [ ] Associate API key with usage plan
- [ ] Store API key mapping in DynamoDB (api_key → tenant_id)
- [ ] Test API Gateway endpoint with curl

**AWS IoT Core Configuration (for DevTank/MQTT sensors):**

- [ ] Create IoT Thing Type "DevTankOSM" (first time only)
- [ ] Create IoT Thing per device
- [ ] Generate X.509 certificates per device
- [ ] Attach certificates to Things
- [ ] Create/attach IoT Policy for tenant
- [ ] Prepare device credentials packages
- [ ] Get IoT endpoint URL

**Snowflake Configuration:**

- [ ] Create tenant database (`smdh_tenant_{tenant_id}`)
- [ ] Create schemas (raw, normalized, aggregated, analytics)
- [ ] Create standard tables (sensor_readings, etc.)
- [ ] **Create DevTank-specific tables** (`raw.devtank_raw_readings`)
- [ ] **Create DevTank Dynamic Tables** (normalized, aggregated)
- [ ] Create Dynamic Tables for aggregations
- [ ] Create Streams for CDC
- [ ] Create Tasks for ETL orchestration
- [ ] Create roles (admin, user, powerbi)
- [ ] Grant permissions to roles (including DevTank tables)
- [ ] Create tenant users (SSO via SAML)
- [ ] Create resource monitor (credit quota)
- [ ] Deploy Streamlit app

**Gateway Configuration (see Section 12 for detailed procedures):**

- [ ] Physical installation and mounting (Section 12.6.2)
- [ ] Access UG65 web interface (Section 12.3.1)
- [ ] Change default admin password
- [ ] Configure network settings (static IP or DHCP)
- [ ] Set time zone and NTP server
- [ ] Configure LoRaWAN region (EU868 for UK/Europe)
- [ ] Create new application (`{tenant_id}_production`)
- [ ] Add JavaScript payload decoder (Section 12.3.5)
- [ ] Configure HTTP transmission URL or MQTT endpoint (Section 12.4 or 12.5)
- [ ] Add x-api-key header (HTTP) or upload certificates (MQTT)
- [ ] Test transmission (expect HTTP 200 or MQTT connection)
- [ ] Verify data appears in Snowflake raw table

**DevTank Sensor Configuration (per device):**

- [ ] Physical device installation on-site
- [ ] Connect device via USB-C to laptop
- [ ] Access OSM Config GUI (https://osm-config.devtank.co.uk)
- [ ] Configure communication method (Wi-Fi MQTT or LoRaWAN)
- [ ] Upload certificates (Wi-Fi) or generate DevEUI/AppKey (LoRaWAN)
- [ ] Register device in LoRaWAN network server (if applicable)
- [ ] Add JavaScript payload decoder to network server
- [ ] Configure measurement intervals (5-15 minutes)
- [ ] Save and backup device configuration
- [ ] Verify device shows "Connected" status
- [ ] Verify data in Snowflake `devtank_readings` table

**Analytics Configuration:**

- [ ] Configure Power BI Snowflake connector
- [ ] Create Power BI reports (including DevTank air quality/energy)
- [ ] Publish to Power BI Service
- [ ] Configure RLS (inherited from Snowflake)
- [ ] Grant Streamlit app access to tenant users
- [ ] Test end-to-end data flow

**Documentation:**

- [ ] Provide tenant admin guide
- [ ] **Provide UG65 gateway configuration guide** (See Section 12)
- [ ] **Provide DevTank deployment guide** (See Section 11)
- [ ] Provide user training materials
- [ ] Document API key (secure delivery)
- [ ] Document DevTank device credentials packages
- [ ] Document UG65 gateway credentials packages (MQTT certificates or HTTP API keys)

### 13.4 Document History

| Version | Date       | Author            | Changes                                                                                                                                                                                          |
| ------- | ---------- | ----------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 1.0     | 2025-11-13 | Architecture Team | Initial detailed design document                                                                                                                                                                 |
| 1.1     | 2025-11-13 | Architecture Team | Clarified protocol-driven ingestion model                                                                                                                                                        |
| 1.2     | 2025-11-19 | Architecture Team | Added DevTank OpenSmartMonitor sensor integration (Section 11), updated Component Inventory, Data Source Coverage, and Tenant Onboarding Checklist                                               |
| 1.3     | 2025-11-20 | David McNabb      | Added comprehensive Milesight UG65 Gateway Configuration guide (Section 12) with dual-protocol support, physical deployment procedures, network server configuration, and troubleshooting guides |

---

**Classification:** Internal Use Only
**Distribution:** SMDH Project Team, Executive Stakeholders
**Review Cycle:** Quarterly
**Next Review Date:** 13 February 2026

---

**END OF DOCUMENT**
