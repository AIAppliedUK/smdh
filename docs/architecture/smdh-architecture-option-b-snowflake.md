# Smart Manufacturing Data Hub Architecture Design Document
# Option B: Snowflake-Leveraged Architecture v2.0

## Executive Summary

This document outlines an alternative **Snowflake-centric** architecture design for a cloud-native, multi-tenant smart manufacturing data hub. This approach maximizes Snowflake's native capabilities for data ingestion, processing, transformation, and ML while minimizing AWS service dependencies to only essential infrastructure components.

### Key Objectives
- Support diverse sensor types: machine utilization, air quality, energy, and RFID tracking
- Process 2.6M-3.9M rows daily with additional event-driven data
- Deliver <5 minute latency for sensor KPIs, <10 seconds for real-time monitoring
- Enable secure multi-tenant data isolation across all use cases
- Support 20-40 concurrent users across 60-120 specialized dashboards
- Simplify operations by consolidating data operations within Snowflake

### Key Differences from Option A (AWS-Heavy)
- **Data Processing**: Uses Snowflake Streams, Tasks, and Dynamic Tables instead of Lambda, Flink, and AWS Batch
- **Storage**: Eliminates S3 data lake; uses Snowflake internal storage with stages
- **Caching**: Leverages Snowflake result cache instead of ElastiCache/Redis
- **ML Processing**: Uses Snowflake Cortex ML functions instead of SageMaker (where applicable)
- **Schema Management**: Uses Snowflake schema detection instead of AWS Glue Schema Registry
- **Streaming**: Uses Snowpipe Streaming instead of Kinesis Firehose
- **Benefits**: Simplified architecture, reduced operational complexity, unified governance
- **Trade-offs**: Slightly higher latency for real-time processing (seconds vs milliseconds)

### Version History
- v1.0: Initial AWS-heavy architecture
- v2.0 Option A: Enhanced AWS-heavy with multiple use cases
- v2.0 Option B: **Snowflake-leveraged alternative (this document)**

---

## Architecture Overview

### High-Level Architecture Pattern
The solution implements a **Snowflake-Centric Multi-Tenant Platform** with the following characteristics:
- Minimal AWS footprint (only essential services: IoT Core, API Gateway, EventBridge, Cognito, networking)
- Snowflake handles all data processing, transformation, ML, and storage
- Shared infrastructure with logical data separation
- Row-level security for tenant isolation
- Unified data platform reducing operational complexity
- Single source of truth for all analytics and ML

### Technology Stack
- **Cloud Provider**: AWS (Region: eu-west-2 London) - Infrastructure only
- **Data Platform**: Snowflake (SaaS, AWS-hosted) - **Primary processing engine**
- **IoT Protocol**: MQTT v3/v5 via AWS IoT Core
- **Event Routing**: AWS EventBridge (minimal usage)
- **API Layer**: AWS API Gateway → Snowflake External Functions
- **Analytics**: QuickSight, PowerBI Embedded, Grafana, Custom D3.js
- **Application Framework**: React 18+ with TypeScript on AWS ECS Fargate
- **Authentication**: AWS Cognito with SSO and MFA support
- **Data Quality**: Snowflake Data Quality functions + Great Expectations

---

## Component Architecture

### 1. Data Sources Layer (Same as Option A)

#### Machine Utilization Monitoring
- **Machine Sensors**
  - Frequency: 1 Hz data collection
  - Volume: 30-45 sensors per deployment
  - Protocol: LoRaWAN/MQTT
  - Metrics: Operating state, cycle counts, downtime events

- **Energy Monitoring Systems**
  - Frequency: 15-second intervals
  - Protocol: Modbus TCP/MQTT
  - Metrics: Voltage, Current, Power Factor, kWh consumption

#### Air Quality Management
- **Environmental Sensors**
  - Frequency: 1-minute intervals
  - Volume: 10-15 sensors per facility
  - Metrics: CO2, VOCs, PM1/2.5/4/10, Temperature, Humidity, Pressure

#### Job Location Tracking
- **RFID/Barcode Systems**
  - Type: Event-driven scanning
  - Volume: 500-2000 scans per day per facility
  - Protocol: HTTP/REST API or MQTT

#### Legacy Systems Integration
- **File Uploads**
  - Formats: CSV, XLSX, JSON, PDF, PNG
  - Volume: 5-50 GB per company
  - Frequency: Weekly to monthly batch uploads

### 2. Ingestion & Routing Layer (Simplified)

#### AWS IoT Core (Retained)
- **Function**: MQTT message broker and device management
- **Protocol Support**: MQTT v3.1.1 and v5
- **Capabilities**:
  - Persistent connections with automatic reconnection
  - Device authentication via X.509 certificates
  - Device shadows for state management
  - Message retention and QoS levels

#### IoT Rules Engine (Simplified)
- **Function**: Route messages directly to Snowflake endpoints
- **Configuration**:
  - Single consolidated rule set
  - Route to Kinesis Data Streams (minimal buffering)
  - Route to Snowflake external functions for immediate processing
- **Actions**:
  - Route to Kinesis → **Snowpipe Streaming**
  - Trigger Snowflake External Functions (Lambda proxy)
  - Store critical events to EventBridge

#### API Gateway (Retained - Simplified)
- **Function**: REST API proxy to Snowflake
- **Features**:
  - Request throttling and rate limiting
  - Direct integration with Snowflake External Functions
  - Presigned URL generation for direct Snowflake stage uploads
  - WebSocket support for real-time updates

#### EventBridge (Minimal Usage)
- **Function**: Event-driven orchestration for non-data events
- **Use Cases**:
  - System health alerts
  - Cross-service integration (non-data)
  - Alert notification routing

#### Schema Management
- **Technology**: **Snowflake Schema Detection & Evolution**
- **Functions**:
  - Automatic schema inference from VARIANT columns
  - Schema evolution tracking via Streams
  - Data contracts via Snowflake tags and policies
  - Metadata management in INFORMATION_SCHEMA

### 3. Processing & Transformation Layer (Snowflake-Native)

#### Snowpipe Streaming (Replaces Kinesis Firehose)
- **Function**: Direct streaming ingestion into Snowflake
- **Capabilities**:
  - Sub-second to few-second latency
  - Exactly-once semantics
  - Automatic schema detection
  - No external buffering required
- **Sources**:
  - Kafka/Kinesis integration via Snowflake Connector
  - REST API for direct ingestion
  - SDK for custom applications

#### Snowflake Streams (Replaces Lambda + Flink)
- **Function**: Change Data Capture (CDC) for transformations
- **Use Cases**:
  - Track changes in raw tables
  - Trigger downstream transformations
  - Deduplication logic
  - Data quality checks
- **Features**:
  - Low-latency change tracking
  - Exactly-once processing
  - Automatic offset management

#### Snowflake Tasks (Replaces AWS Batch + Lambda)
- **Function**: Scheduled and event-driven data processing
- **Capabilities**:
  - SQL-based transformations
  - Python/Java/Scala stored procedures
  - DAG-based task orchestration
  - Cron scheduling
  - Stream-triggered execution
- **Use Cases**:
  - ETL pipeline orchestration
  - Report generation
  - Data archival
  - Aggregation jobs
  - ML model retraining

#### Dynamic Tables (Replaces Materialized Views + Lambda)
- **Function**: Continuously updated aggregations
- **Features**:
  - Declarative SQL definitions
  - Automatic refresh on data changes
  - Incremental processing
  - Optimized for streaming data
- **Use Cases**:
  - Real-time dashboards
  - KPI calculations
  - Rolling aggregations
  - Time-series analytics

#### Snowflake Stored Procedures (Replaces Lambda)
- **Languages**: SQL, Python, Java, Scala
- **Use Cases**:
  - Complex transformations
  - Data validation
  - Custom business logic
  - Integration orchestration
- **Benefits**:
  - Direct data access (no serialization)
  - Warehouse compute power
  - Version control via Git integration

#### Data Quality Framework
- **Snowflake Native**:
  - Data Quality Metrics (SYSTEM$DATA_QUALITY_*)
  - Column statistics and profiling
  - Constraint validation
  - Tag-based data classification
- **Great Expectations** (Optional):
  - Advanced validation rules
  - Profiling and documentation
  - Integration via Python stored procedures

#### Machine Learning Pipeline (Snowflake Cortex)
- **Snowflake Cortex ML Functions**:
  - Anomaly detection (DETECT_ANOMALIES)
  - Time-series forecasting (FORECAST)
  - Classification and regression
  - Sentiment analysis
  - LLM functions for analysis
- **Python UDF/Stored Procedures**:
  - Custom ML models using Snowpark
  - Integration with scikit-learn, XGBoost
  - Model training on Snowflake compute
- **Model Management**:
  - Models stored as UDFs
  - Version control via Git
  - A/B testing via conditional logic
- **When to Use SageMaker**: Only for deep learning or highly custom models

#### Snowflake Stages (Replaces S3 Data Lake)
- **Internal Stages**:
  - User/table/named stages for file storage
  - Temporary storage for ingestion
  - Encrypted by default
- **External Stages** (Minimal S3 usage):
  - Long-term archive storage (cold tier)
  - Integration with legacy systems
  - Backup/DR purposes
- **Structure**:
  - `@raw_stage/tenant-id/source-type/`
  - `@archive_stage/tenant-id/year/`
- **Features**:
  - Automatic encryption
  - Time Travel (1-90 days)
  - Fail-safe (7 days)
  - Zero-copy cloning

### 4. Data Platform (Snowflake) - Core Architecture

#### Enhanced Data Model

```sql
-- Enhanced multi-tenant sensor readings table with streaming support
CREATE OR REPLACE TABLE sensor_readings_raw (
    -- Tenant isolation
    tenant_id VARCHAR(50) NOT NULL,

    -- Sensor identification
    sensor_id VARCHAR(100) NOT NULL,
    sensor_type VARCHAR(50) NOT NULL, -- 'MACHINE', 'AIR_QUALITY', 'ENERGY', 'RFID'
    location_id VARCHAR(100),

    -- Temporal
    timestamp TIMESTAMP_NTZ NOT NULL,

    -- Raw payload - flexible schema
    payload VARIANT NOT NULL,

    -- Metadata
    device_metadata VARIANT,
    ingestion_timestamp TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),

    -- Data lineage
    source_system VARCHAR(100),
    message_id VARCHAR(255),

    PRIMARY KEY (tenant_id, sensor_id, timestamp, message_id)
)
CLUSTER BY (tenant_id, sensor_type, DATE_TRUNC('day', timestamp))
ENABLE_SCHEMA_EVOLUTION = TRUE;

-- Stream for change data capture
CREATE OR REPLACE STREAM sensor_readings_stream
ON TABLE sensor_readings_raw
APPEND_ONLY = TRUE;

-- Normalized sensor readings via Dynamic Table
CREATE OR REPLACE DYNAMIC TABLE sensor_readings_normalized
TARGET_LAG = '1 minute'
WAREHOUSE = streaming_wh
AS
SELECT
    tenant_id,
    sensor_id,
    sensor_type,
    location_id,
    timestamp,

    -- Extract metrics from VARIANT payload
    metric_key,
    metric_value,

    -- Quality and context
    payload:quality_score::FLOAT as quality_score,
    device_metadata,
    ingestion_timestamp,
    source_system
FROM sensor_readings_raw,
LATERAL FLATTEN(input => payload:metrics) f(metric_key, metric_value)
WHERE quality_score > 0.7;

-- Job tracking table for RFID data
CREATE OR REPLACE TABLE job_tracking (
    tenant_id VARCHAR(50) NOT NULL,
    job_id VARCHAR(100) NOT NULL,
    product_id VARCHAR(100),
    product_variant VARCHAR(100),
    location VARCHAR(100) NOT NULL,
    scan_timestamp TIMESTAMP_NTZ NOT NULL,
    duration_seconds INTEGER,
    operator_id VARCHAR(50),
    metadata VARIANT,

    PRIMARY KEY (tenant_id, job_id, location, scan_timestamp)
)
CLUSTER BY (tenant_id, DATE_TRUNC('day', scan_timestamp));

-- Stream for job tracking
CREATE OR REPLACE STREAM job_tracking_stream
ON TABLE job_tracking
APPEND_ONLY = TRUE;

-- Machine utilization via Dynamic Table (continuously updated)
CREATE OR REPLACE DYNAMIC TABLE machine_utilization_hourly
TARGET_LAG = '5 minutes'
WAREHOUSE = analytics_wh
AS
SELECT
    tenant_id,
    sensor_id as machine_id,
    DATE_TRUNC('hour', timestamp) as hour,

    -- Aggregated metrics
    AVG(CASE WHEN metric_key = 'utilization' THEN metric_value::FLOAT END) as avg_utilization,
    SUM(CASE WHEN metric_key = 'energy_kwh' THEN metric_value::FLOAT END) as total_energy,
    COUNT(DISTINCT CASE WHEN metric_key = 'state_change' THEN metric_value END) as state_changes,
    MAX(CASE WHEN metric_key = 'cycle_count' THEN metric_value::INTEGER END) as cycle_count,

    -- Quality metrics
    AVG(quality_score) as avg_quality,
    COUNT(*) as reading_count
FROM sensor_readings_normalized
WHERE sensor_type = 'MACHINE'
GROUP BY 1, 2, 3;

-- Air quality with anomaly detection via Snowflake Cortex
CREATE OR REPLACE DYNAMIC TABLE air_quality_current
TARGET_LAG = '1 minute'
WAREHOUSE = streaming_wh
AS
SELECT
    tenant_id,
    location_id,
    timestamp,

    -- Current readings
    MAX(CASE WHEN metric_key = 'co2_ppm' THEN metric_value::FLOAT END) as co2_level,
    MAX(CASE WHEN metric_key = 'voc_ppb' THEN metric_value::FLOAT END) as voc_level,
    MAX(CASE WHEN metric_key = 'pm25_ugm3' THEN metric_value::FLOAT END) as pm25_level,
    MAX(CASE WHEN metric_key = 'temperature_c' THEN metric_value::FLOAT END) as temperature,
    MAX(CASE WHEN metric_key = 'humidity_pct' THEN metric_value::FLOAT END) as humidity,

    -- Anomaly detection using Snowflake Cortex
    SNOWFLAKE.ML.DETECT_ANOMALIES(
        MAX(CASE WHEN metric_key = 'pm25_ugm3' THEN metric_value::FLOAT END)
        OVER (PARTITION BY tenant_id, location_id
              ORDER BY timestamp
              ROWS BETWEEN 60 PRECEDING AND CURRENT ROW)
    ) as pm25_anomaly,

    -- Calculate AQI
    CASE
        WHEN MAX(CASE WHEN metric_key = 'pm25_ugm3' THEN metric_value::FLOAT END) > 55 THEN 'Poor'
        WHEN MAX(CASE WHEN metric_key = 'co2_ppm' THEN metric_value::FLOAT END) > 1000 THEN 'Moderate'
        ELSE 'Good'
    END as air_quality_index
FROM sensor_readings_normalized
WHERE sensor_type = 'AIR_QUALITY'
  AND timestamp > DATEADD(minute, -5, CURRENT_TIMESTAMP())
GROUP BY 1, 2, 3;

-- Production flow analysis via Dynamic Table
CREATE OR REPLACE DYNAMIC TABLE production_flow_analysis
TARGET_LAG = '5 minutes'
WAREHOUSE = analytics_wh
AS
SELECT
    tenant_id,
    job_id,
    product_id,

    -- Flow sequence
    LISTAGG(location, ' → ') WITHIN GROUP (ORDER BY scan_timestamp) as flow_path,

    -- Timing analysis
    MIN(scan_timestamp) as start_time,
    MAX(scan_timestamp) as end_time,
    DATEDIFF('second', MIN(scan_timestamp), MAX(scan_timestamp)) as total_cycle_time,

    -- Location-specific durations
    OBJECT_AGG(location, duration_seconds) as location_durations,

    -- Identify bottlenecks
    MAX(duration_seconds) as longest_duration,
    MAX_BY(location, duration_seconds) as bottleneck_location
FROM job_tracking
GROUP BY 1, 2, 3;

-- Row Access Policy for Multi-tenancy (same as Option A)
CREATE OR REPLACE ROW ACCESS POLICY tenant_isolation AS
    (tenant_id VARCHAR) RETURNS BOOLEAN ->
    CURRENT_ROLE() IN ('ADMIN_ROLE')
    OR tenant_id = CURRENT_SESSION_PARAMETER('tenant_id');

-- Apply policy to all tables
ALTER TABLE sensor_readings_raw
    ADD ROW ACCESS POLICY tenant_isolation ON (tenant_id);
ALTER TABLE sensor_readings_normalized
    ADD ROW ACCESS POLICY tenant_isolation ON (tenant_id);
ALTER TABLE job_tracking
    ADD ROW ACCESS POLICY tenant_isolation ON (tenant_id);
```

#### Task-Based ETL Orchestration

```sql
-- Root task: Process raw sensor data quality checks
CREATE OR REPLACE TASK process_data_quality
    WAREHOUSE = etl_wh
    SCHEDULE = '1 MINUTE'
    WHEN SYSTEM$STREAM_HAS_DATA('sensor_readings_stream')
AS
    CALL validate_sensor_data('sensor_readings_stream');

-- Child task: Update aggregations
CREATE OR REPLACE TASK update_hourly_aggregates
    WAREHOUSE = etl_wh
    AFTER process_data_quality
AS
    -- Refresh specific aggregations if needed
    -- (Dynamic Tables handle most of this automatically)
    CALL refresh_custom_aggregations();

-- Child task: Run ML anomaly detection
CREATE OR REPLACE TASK detect_anomalies
    WAREHOUSE = ml_wh
    AFTER process_data_quality
AS
    CALL run_anomaly_detection_models();

-- Child task: Generate alerts
CREATE OR REPLACE TASK generate_alerts
    WAREHOUSE = etl_wh
    AFTER detect_anomalies
AS
    CALL check_threshold_alerts();

-- Resume task DAG
ALTER TASK generate_alerts RESUME;
ALTER TASK detect_anomalies RESUME;
ALTER TASK update_hourly_aggregates RESUME;
ALTER TASK process_data_quality RESUME;
```

#### Stored Procedures for Complex Logic

```sql
-- Data validation stored procedure
CREATE OR REPLACE PROCEDURE validate_sensor_data(stream_name VARCHAR)
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.10'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'validate_data'
AS
$$
def validate_data(session, stream_name):
    from snowflake.snowpark.functions import col, when

    # Read from stream
    stream_df = session.table(stream_name)

    # Apply validation rules
    validated = stream_df.with_column(
        'quality_score',
        when(
            (col('payload').is_not_null()) &
            (col('timestamp') > session.sql("SELECT DATEADD('day', -1, CURRENT_TIMESTAMP())").collect()[0][0]),
            1.0
        ).otherwise(0.5)
    )

    # Write to staging table
    validated.write.mode('append').save_as_table('sensor_readings_validated')

    return f"Validated {validated.count()} records"
$$;

-- Anomaly detection using Snowflake ML
CREATE OR REPLACE PROCEDURE run_anomaly_detection_models()
RETURNS TABLE()
LANGUAGE SQL
AS
$$
BEGIN
    -- Detect machine state anomalies
    CREATE OR REPLACE TEMP TABLE machine_anomalies AS
    SELECT
        tenant_id,
        machine_id,
        hour,
        avg_utilization,
        SNOWFLAKE.ML.FORECAST(
            avg_utilization,
            4  -- forecast next 4 hours
        ) OVER (PARTITION BY tenant_id, machine_id ORDER BY hour) as forecasted_utilization
    FROM machine_utilization_hourly
    WHERE hour > DATEADD('day', -7, CURRENT_TIMESTAMP());

    -- Return anomalies
    RETURN TABLE(SELECT * FROM machine_anomalies
                 WHERE ABS(avg_utilization - forecasted_utilization) > 20);
END;
$$;
```

#### Compute Resources (Optimized for Snowflake-Heavy)

- **Streaming Warehouse**: Small (2 credits/hour), always on for Snowpipe Streaming
- **ETL Warehouse**: Medium (4 credits/hour), auto-suspend 60s for Tasks
- **Analytics Warehouse**: Large (8 credits/hour), auto-suspend 300s for BI queries
- **ML Warehouse**: Large (8 credits/hour), auto-suspend 60s for Cortex ML
- **Developer Warehouse**: X-Small (1 credit/hour), auto-suspend 60s

#### Data Organization (Simplified from Option A)

- **Raw Layer**: Direct ingestion tables with VARIANT columns
- **Normalized Layer**: Dynamic Tables for flattened data
- **Aggregation Layer**: Dynamic Tables for pre-computed metrics
- **Analytics Layer**: Views and secure views for BI consumption
- **Archive**: Time Travel + External stages for cold storage

### 5. Analytics & Visualization Layer (Same as Option A)

The analytics layer remains largely unchanged from Option A:

- **QuickSight**: Embedded analytics with SPICE
- **PowerBI Embedded**: Workspace isolation per tenant
- **Grafana**: AWS Managed Grafana for operational monitoring
- **Custom D3.js**: For specialized manufacturing visualizations
- **Snowsight**: Native Snowflake interface for ad-hoc analysis

Key difference: All BI tools connect directly to Snowflake Dynamic Tables and Views, eliminating the need for external caching layers.

### 6. Web Portal Architecture (Same as Option A)

- **Framework**: React 18+ with TypeScript
- **State Management**: Redux Toolkit
- **UI Components**: Material-UI v5
- **Backend**: Node.js/FastAPI proxying to Snowflake External Functions
- **Hosting**: AWS ECS Fargate

**Key Changes**:
- API backend primarily calls Snowflake External Functions
- Session state stored in Snowflake session parameters
- Reduced dependency on external caching (leverage Snowflake result cache)

### 7. Security Architecture (Enhanced with Snowflake-Native)

#### Network Security (Minimal AWS)
- **VPC Design**:
  - Public subnets: ALB only
  - Private subnets: Application tier
  - VPC Endpoints: Snowflake PrivateLink, Secrets Manager
  - **Simplified**: No EMR, no Kinesis endpoints needed

- **Snowflake PrivateLink**:
  - Direct private connectivity from VPC to Snowflake
  - No internet gateway traversal
  - Reduced attack surface

#### Data Security (Snowflake-Native)
- **Encryption**:
  - Snowflake automatic encryption at rest (AES-256)
  - TLS 1.3 for all connections
  - End-to-end encryption
  - Tri-Secret Secure (customer-managed keys option)

- **Access Control**:
  - Role-based access control (RBAC)
  - Row Access Policies for multi-tenancy
  - Column masking policies for PII
  - Tag-based security
  - Object tagging for data classification

#### Application Security (Same as Option A)
- AWS Cognito for authentication
- JWT tokens with Snowflake session parameters
- Rate limiting at API Gateway

#### Compliance & Audit
- **Logging**:
  - Snowflake Query History (1 year retention)
  - Access History for compliance
  - CloudTrail for AWS API calls (minimal)
- **Compliance**:
  - Snowflake SOC 2 Type II, HIPAA, PCI DSS, GDPR compliant
  - Data residency controls
  - Time Travel for audit trail

---

## Multi-Tenancy Strategy (Snowflake-Optimized)

### Data Isolation Model
**Hybrid Approach: MTT with Snowflake-Native Isolation**

#### Standard Tenants
- Shared tables with tenant_id column
- Row Access Policies for complete isolation
- Shared compute with Resource Monitors
- Session-based context (SET tenant_id)

#### Premium Tenants
- Separate Snowflake schemas (optional)
- Dedicated virtual warehouses
- Custom retention via Time Travel settings
- Isolated Data Sharing for external access

### Performance Isolation
- **Resource Monitors**:
  - Credit quotas per tenant (via tagging)
  - Alert thresholds at 75%, 90%
  - Automatic suspension at 100%
  - Weekly/monthly monitoring windows

- **Warehouse Isolation**:
  - Multi-cluster warehouses for analytics
  - Separate warehouses for premium tenants
  - Query timeout settings
  - Statement timeout policies

### Cost Attribution (Snowflake-Native)
- **Account Usage Views**:
  - Warehouse metering by tag
  - Storage costs by schema/table
  - Data transfer tracking
  - Snowpipe Streaming costs
- **Tag-Based Tracking**:
  - Tag all objects with tenant_id
  - Query ACCOUNT_USAGE for cost reports
  - Automated chargeback reports

---

## Data Flow Architecture (Snowflake-Centric)

### Real-time Sensor Data Flow (Simplified)

```
Sensors → LoRaWAN/MQTT → AWS IoT Core → Kinesis Data Streams
→ Snowpipe Streaming → Snowflake Raw Table → Snowflake Stream
→ Snowflake Task → Dynamic Tables → BI Tools → Web Portal
```

**Key Simplifications**:
- No Lambda transformations
- No S3 staging
- No Kinesis Firehose
- No EMR/Flink processing
- Direct streaming to Snowflake

### RFID Job Tracking Flow (Simplified)

```
RFID Scanner → REST API → API Gateway → Snowflake External Function
→ Snowflake Table → Stream → Task → Dynamic Tables → Job Analytics
```

**Key Simplifications**:
- No EventBridge (unless needed for notifications)
- No DynamoDB cache (use Snowflake result cache)
- No separate stream processing

### Batch File Upload Flow (Simplified)

```
User → Web Portal → Snowflake Stage (Direct PUT) → Snowpipe
→ Snowflake Table → Task (Validation) → Dynamic Tables
```

**Key Simplifications**:
- Direct upload to Snowflake stages
- No S3 intermediate storage
- No Lambda validation (use Snowflake stored procedures)

---

## Implementation Roadmap (Revised for Snowflake-Centric)

### Phase 1: Foundation & Core Platform (Weeks 1-3)
- [ ] AWS account setup (minimal services)
- [ ] VPC with Snowflake PrivateLink
- [ ] Snowflake account with multi-tenant schema
- [ ] IoT Core and API Gateway (lightweight)
- [ ] Snowflake external stages (minimal S3)
- [ ] React portal framework
- [ ] CI/CD pipeline (Snowflake + AWS)

### Phase 2: Data Ingestion via Snowflake (Weeks 4-6)
- [ ] Configure Snowpipe Streaming from Kinesis
- [ ] Setup Snowflake Streams for CDC
- [ ] Implement schema detection and evolution
- [ ] Create stored procedures for validation
- [ ] Deploy Snowflake Tasks for orchestration
- [ ] Setup External Functions for API integration

### Phase 3: Use Case Implementation (Weeks 7-10)
- [ ] Machine Utilization: Dynamic Tables for metrics
- [ ] Air Quality: Cortex ML for anomaly detection
- [ ] Job Tracking: Session windowing via SQL
- [ ] Create base Dynamic Tables for dashboards
- [ ] Implement alert Tasks
- [ ] Portal integration with Snowflake

### Phase 4: Analytics & Visualization (Weeks 11-14)
- [ ] Deploy QuickSight with Snowflake connector
- [ ] Configure PowerBI with Snowflake DirectQuery
- [ ] Implement Grafana with Snowflake plugin
- [ ] Create custom D3.js visualizations
- [ ] Build report generation via Tasks
- [ ] Self-service via Snowsight

### Phase 5: Advanced Features & ML (Weeks 15-17)
- [ ] Deploy Cortex ML models for forecasting
- [ ] Implement custom ML via Python UDFs
- [ ] Advanced visualizations
- [ ] Performance optimization (clustering, materialization)
- [ ] Cost optimization (warehouse sizing)
- [ ] Documentation and training

### Phase 6: Production Hardening (Weeks 18-20)
- [ ] Security audit
- [ ] Load testing (warehouse scaling)
- [ ] Disaster recovery via replication
- [ ] Monitoring enhancement (Snowflake + CloudWatch)
- [ ] SLA implementation
- [ ] Go-live preparation

**Time Savings vs Option A**: ~4 weeks faster (20 vs 24 weeks) due to simplified architecture

---

## Capacity Planning (Snowflake-Centric)

### Storage Requirements (Within Snowflake)
- **Daily Volume**:
  - Raw data ingestion: ~200 MB/day compressed (based on 2.6M-3.9M rows/day from requirements)
  - After transformations and aggregations: ~300 MB/day
- **Monthly Growth**: 9-12 GB (raw + transformed data)
- **With Aggregations** (1min, 5min, 1hour, 1day):
  - Aggregation tables add ~3-4x multiplier
  - Total with aggregations: ~30-40 GB/month
- **Annual Projection**:
  - Raw + transformed: 110-150 GB
  - With all aggregations: ~360-480 GB
- **With Time Travel (90 days)**: ~30 GB additional overhead
- **Total Year 1 (All Data)**: ~400-500 GB

**Note**: The 9-12 GB/month figure represents raw ingestion only. Total storage including all pre-computed aggregation tables is approximately 30-40 GB/month. This aligns with Option C and D calculations.

### Compute Requirements (Snowflake Credits)

**Monthly Credit Estimate**:
- **Snowpipe Streaming**: 100-150 credits (continuous ingestion)
- **Task Execution**: 80-120 credits (ETL orchestration)
- **Dynamic Table Refresh**: 100-150 credits (continuous aggregation)
- **Analytics Queries**: 150-250 credits (BI tool queries)
- **ML Workloads**: 50-100 credits (Cortex ML)
- **Development**: 50 credits (testing, development)

**Total Monthly**: 530-820 credits (~$1,600-$2,500/month at $3/credit)

### AWS Costs (Reduced from Option A)

**Monthly AWS Estimate**:
- **IoT Core**: $100-200 (message routing only)
- **Minimal S3**: $20-50 (archive only)
- **API Gateway**: $50-100 (proxy to Snowflake)
- **ECS Fargate**: $200-300 (web portal)
- **Cognito**: $50 (authentication)
- **Networking**: $100-150 (PrivateLink, data transfer)
- **Other**: $50-100 (CloudWatch, etc.)

**Total AWS**: $570-950/month (vs $1,000-1,800 in Option A)

### Total Cost Comparison

| Component | Option A (AWS-Heavy) | Option B (Snowflake-Heavy) |
|-----------|---------------------|---------------------------|
| AWS Services | $1,000-$1,800 | $570-$950 |
| Snowflake | $1,500-$2,400 | $1,600-$2,500 |
| **Total** | **$2,500-$4,200** | **$2,170-$3,450** |
| **Savings** | - | **~15-20%** |

---

## Monitoring & Operations (Snowflake-Centric)

### Key Performance Indicators

#### Data Pipeline KPIs
- Snowpipe Streaming latency: <10 seconds target
- Task execution success rate: >99.9%
- Dynamic Table freshness: Within TARGET_LAG
- Query performance: <3 seconds p95

#### Snowflake-Specific Metrics
- Credit consumption per tenant
- Warehouse utilization rates
- Query spillage to disk (avoid)
- Clustering depth (maintain <4)
- Time Travel storage growth

### Monitoring Stack (Simplified)

- **Snowflake Native**:
  - Query History and Profile
  - Warehouse Load Monitoring
  - Account Usage views
  - Resource Monitors
  - Task History

- **AWS CloudWatch** (Minimal):
  - IoT Core metrics
  - API Gateway metrics
  - Application logs

- **Alerting**:
  - Snowflake Tasks for data alerts
  - SNS for infrastructure alerts
  - Email notifications via Snowflake

### Operational Procedures

- **Incident Response**: Task failure → automatic retry → alert
- **Change Management**: Git-based for Snowflake objects
- **Backup & Recovery**: Time Travel (up to 90 days) + Replication
- **Maintenance**: Zero-downtime warehouse changes
- **Cost Reviews**: Weekly Snowflake credit analysis

---

## Risk Mitigation (Updated for Option B)

| Risk | Probability | Impact | Mitigation Strategy |
|------|------------|--------|-------------------|
| Snowflake outage | Low | High | Multi-region replication, Time Travel for recovery |
| Snowpipe latency | Low | Medium | Multi-cluster warehouses, monitoring, auto-scaling |
| Cost overrun | Medium | Medium | Resource Monitors with auto-suspend, credit alerts |
| Security breach | Low | Critical | PrivateLink, RBAC, row-level security, encryption |
| Vendor lock-in | Medium | Medium | Standard SQL, Python UDFs portable, data export capability |
| Query performance | Low | High | Clustering, materialized views, query optimization |
| Data quality issues | Medium | High | Stored procedure validation, Cortex data quality |
| Multi-tenant isolation breach | Low | Critical | Row Access Policies, testing, audit logging |
| Real-time latency SLA miss | Medium | Medium | Snowpipe Streaming optimization, warehouse scaling |
| Skill gap | Medium | Low | Training on Snowflake, simpler than multi-service AWS |

**New Risks in Option B**:
- **Snowflake Skill Gap**: Mitigate with training and Snowflake partner support
- **Limited Real-Time**: Accept <10s latency vs <1s in Option A
- **Cortex ML Limitations**: Use SageMaker for advanced custom models

---

## Cost Optimization Strategies (Snowflake-Focused)

### Snowflake Compute Optimization
- **Warehouse Sizing**:
  - Start small, scale based on actual usage
  - Use multi-cluster for concurrent workloads
  - Aggressive auto-suspend (60s for most warehouses)
  - Auto-resume only when needed

- **Query Optimization**:
  - Leverage result cache (24-hour cache)
  - Optimize clustering keys
  - Use Dynamic Tables vs manual refresh
  - Partition pruning with clustering
  - Minimize data scanned

### Snowflake Storage Optimization
- **Time Travel Management**:
  - 1 day for development
  - 7 days for production tables
  - 90 days only for compliance-critical tables

- **Data Lifecycle**:
  - Archive to external stages after 90 days
  - Drop transient tables when not needed
  - Use transient tables for staging

### AWS Cost Optimization (Minimal)
- **PrivateLink**: Eliminate data transfer charges
- **Reserved Instances**: For ECS Fargate (1-year)
- **Spot Instances**: Not needed (no EMR/Batch)

---

## Comparison: Option A vs Option B

### When to Choose Option B (Snowflake-Leveraged)

**Choose Option B if**:
- ✅ You can accept 5-10 second latency for real-time data (vs sub-second)
- ✅ You want simplified operations with fewer services to manage
- ✅ Your team has or can acquire Snowflake expertise
- ✅ You prioritize unified data governance and lineage
- ✅ You want built-in ML capabilities without SageMaker complexity
- ✅ Cost predictability is important (Snowflake credits vs AWS variability)
- ✅ You value faster development cycles (SQL vs Lambda code)

### When to Choose Option A (AWS-Heavy)

**Choose Option A if**:
- ✅ You require sub-second real-time processing
- ✅ Your team has deep AWS expertise (Lambda, Flink, etc.)
- ✅ You need highly custom ML models requiring SageMaker
- ✅ You prefer best-of-breed services for each function
- ✅ You need fine-grained control over every component
- ✅ Edge computing and IoT integration is critical

### Feature Comparison Matrix

| Feature | Option A | Option B |
|---------|----------|----------|
| Real-time Latency | <1 second (Flink) | 5-10 seconds (Snowpipe) |
| Operational Complexity | High (15+ services) | Low (5 core services) |
| Development Speed | Slower (multi-language) | Faster (SQL-first) |
| ML Capabilities | Advanced (SageMaker) | Good (Cortex ML) |
| Cost Predictability | Variable | High (credit-based) |
| Vendor Lock-in | Distributed | Snowflake-centric |
| Data Governance | Complex (multi-tool) | Unified (Snowflake) |
| Team Skill Required | AWS + Data Eng | SQL + Snowflake |
| Scaling Complexity | Manual tuning | Auto-scaling |
| Time to Production | 24 weeks | 20 weeks |

---

## Recommendations & Best Practices

### Immediate Actions
1. **Proof of Concept**:
   - Test Snowpipe Streaming latency with sample sensor data
   - Evaluate Snowflake Cortex ML for anomaly detection
   - Benchmark Dynamic Tables refresh performance

2. **Team Enablement**:
   - Snowflake training for development team
   - SQL optimization workshops
   - Snowpark Python for advanced users

3. **Architecture Validation**:
   - Confirm 5-10 second latency acceptable for use cases
   - Validate Cortex ML capabilities for requirements
   - Test multi-tenant isolation at scale

### Strategic Considerations
1. **Hybrid Approach**: Start with Option B, keep Option A components for edge cases
2. **Migration Path**: Build Option B first, add AWS services if needed
3. **Skill Development**: Invest in Snowflake certification for team
4. **Cost Management**: Implement Resource Monitors from day 1
5. **Exit Strategy**: Design data models to be portable (standard SQL)

### Success Criteria (Same as Option A)
- ✅ Support all three use cases on single platform
- ✅ Meet <5 minute latency for analytics (✅ achievable)
- ✅ Achieve 99.9% platform availability
- ✅ Enable complete multi-tenant isolation
- ✅ Deliver self-service capabilities
- ✅ Maintain costs within budget (~15% savings)
- ✅ Reduce operational complexity by 50%

---

## Appendices

### A. Snowflake Features Utilized

| Feature | Use Case | Benefit |
|---------|----------|---------|
| Snowpipe Streaming | Real-time ingestion | Low-latency, serverless |
| Streams | Change data capture | Incremental processing |
| Tasks | ETL orchestration | SQL-based automation |
| Dynamic Tables | Real-time aggregation | Declarative, auto-refresh |
| Cortex ML | Anomaly detection | Built-in ML, no training |
| External Functions | API integration | Serverless compute |
| PrivateLink | Network security | Private connectivity |
| Row Access Policies | Multi-tenancy | Complete isolation |
| Time Travel | Audit & recovery | Point-in-time restore |
| Resource Monitors | Cost control | Auto-suspend on budget |

### B. Eliminated AWS Services from Option A

- ❌ AWS Batch (replaced by Snowflake Tasks)
- ❌ Lambda for transformations (replaced by Stored Procedures)
- ❌ Kinesis Firehose (replaced by Snowpipe Streaming)
- ❌ EMR/Flink (replaced by Dynamic Tables)
- ❌ ElastiCache (replaced by Snowflake result cache)
- ❌ Glue Schema Registry (replaced by Snowflake schema detection)
- ❌ SageMaker (mostly replaced by Cortex ML)
- ❌ S3 Data Lake (replaced by Snowflake internal storage)

### C. Glossary (Additional Terms)
- **Cortex ML**: Snowflake's built-in ML functions
- **Dynamic Table**: Continuously updated materialized view
- **Snowpipe Streaming**: Low-latency streaming ingestion
- **Snowpark**: Python/Java/Scala framework for Snowflake
- **Time Travel**: Point-in-time data recovery feature
- **PrivateLink**: AWS private network connection to Snowflake

### D. Useful Resources
- [Snowflake Snowpipe Streaming](https://docs.snowflake.com/en/user-guide/data-load-snowpipe-streaming)
- [Dynamic Tables Guide](https://docs.snowflake.com/en/user-guide/dynamic-tables-intro)
- [Snowflake Cortex ML](https://docs.snowflake.com/en/user-guide/ml-functions)
- [Multi-Tenant Patterns](https://docs.snowflake.com/guides/multi-tenancy)
- [Snowflake Tasks](https://docs.snowflake.com/en/user-guide/tasks-intro)

---

## Document Control

- **Version**: 2.0 - Option B
- **Date**: October 2024
- **Author**: Architecture Team
- **Status**: Alternative Architecture Proposal
- **Review Date**: January 2025
- **Distribution**: Project Stakeholders

---

*This document presents an alternative Snowflake-centric architecture that simplifies operations, reduces costs, and accelerates development while accepting slightly higher real-time latency. It should be evaluated alongside Option A (AWS-Heavy) to determine the best fit for organizational capabilities and requirements.*
