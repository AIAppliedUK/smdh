# Smart Manufacturing Data Hub Architecture Design Document

## Executive Summary

This document outlines the architecture design for a cloud-native, multi-tenant smart manufacturing data hub that enables real-time sensor data collection, processing, and visualization for 30-40 SMEs. The solution leverages AWS services for infrastructure, Snowflake for data warehousing, and supports multiple BI tools for analytics and dashboards.

### Key Objectives
- Support 60 sensors across machine utilization and air quality monitoring
- Process 2.6M-3.9M rows daily (~105-157 MB compressed/day)
- Deliver <5 minute latency for sensor KPIs
- Enable secure multi-tenant data isolation
- Support 20-40 concurrent users across 60-120 dashboards

---

## Architecture Overview

### High-Level Architecture Pattern
The solution implements a **Centralized Multi-Tenant Platform** with the following characteristics:
- Shared infrastructure with logical data separation
- Row-level security for tenant isolation
- Scalable ingestion pipeline supporting both streaming and batch data
- Flexible analytics layer supporting multiple BI tools

### Technology Stack
- **Cloud Provider**: AWS (Region: eu-west-2 London)
- **Data Warehouse**: Snowflake (SaaS, AWS-hosted)
- **IoT Protocol**: MQTT v3/v5 via AWS IoT Core
- **Analytics**: QuickSight, PowerBI Embedded, Tableau, Snowsight
- **Application Framework**: React/Angular on AWS ECS Fargate
- **Authentication**: AWS Cognito with SSO support

---

## Component Architecture

### 1. Data Sources Layer

#### DevTank Sensor Systems
- **Machine Utilization Sensors**
  - Frequency: 1 Hz data collection
  - Volume: 30-45 sensors per deployment
  - Protocol: LoRaWAN/MQTT
  
- **Air Quality Monitoring**
  - Frequency: 1/30 Hz data collection
  - Volume: 10-15 sensors per deployment
  - Metrics: Temperature, humidity, particles, light, sound

- **OpenSmartMonitor Platform**
  - Industrial IoT monitoring solution
  - LoRaWAN connectivity with cloud integration
  - Grafana-based visualization capabilities

#### File Uploads
- **Formats**: CSV, XLSX, JSON, PDF, PNG
- **Volume**: 5-50 GB per company
- **Frequency**: Weekly to monthly batch uploads

### 2. Ingestion Layer

#### AWS IoT Core
- **Function**: MQTT message broker
- **Protocol Support**: MQTT v3.1.1 and v5
- **Capabilities**:
  - Persistent connections
  - Device authentication via X.509 certificates
  - Message retention and QoS levels
  - Scales to billions of messages

#### IoT Rules Engine
- **Function**: Message routing and filtering
- **Configuration**: Single consolidated rule (reduced from 20 rules for cost optimization)
- **Actions**: Route to Kinesis Data Firehose

#### API Gateway
- **Function**: REST API for file uploads and manual data submission
- **Features**: 
  - Request throttling
  - API key management
  - Lambda integration for processing

### 3. Processing Layer

#### Kinesis Data Firehose
- **Buffer Configuration**:
  - Size: 10 MB (compressed GZIP)
  - Time: 60 seconds (whichever comes first)
- **Function**: Stream buffering and compression
- **Output**: S3 staging buckets

#### Lambda Functions
- **Data Transformation**:
  - Schema validation
  - Data type conversion
  - Deduplication logic
  - Enrichment with metadata
- **Trigger**: Kinesis Data Firehose, S3 events
- **Runtime**: Python 3.9+

#### S3 Staging
- **Structure**: `/tenant-id/year/month/day/hour/` prefixes
- **Features**:
  - Lifecycle policies for data retention
  - Encryption at rest (SSE-S3)
  - Event notifications to SQS
  - VPC Endpoint for private access

### 4. Data Platform (Snowflake)

#### Storage Integration
- **IAM Role-based authentication** to S3
- **External stages** for data loading
- **Secure access** without embedded credentials

#### Snowpipe
- **Auto-ingest**: Triggered by SQS notifications
- **Near real-time**: <1 minute from file arrival
- **Cost-effective**: Serverless, pay-per-use

#### Data Architecture
```sql
-- Multi-Tenant Table Structure
CREATE TABLE sensor_readings (
    tenant_id VARCHAR(50),
    sensor_id VARCHAR(100),
    timestamp TIMESTAMP_NTZ,
    metric_name VARCHAR(100),
    metric_value VARIANT,
    metadata VARIANT,
    -- Data provenance columns
    record_source VARCHAR(255),
    load_timestamp TIMESTAMP_NTZ,
    job_id VARCHAR(100)
);

-- Row Access Policy for Multi-tenancy
CREATE ROW ACCESS POLICY tenant_isolation AS 
    (tenant_id VARCHAR) RETURNS BOOLEAN ->
    CURRENT_ROLE() IN ('ADMIN_ROLE') 
    OR tenant_id = CURRENT_USER_TENANT();
```

#### Compute Resources
- **ETL Warehouse**: Medium (4 credits/hour), auto-suspend 60s
- **Analytics Warehouse**: Small (2 credits/hour), auto-suspend 60s
- **Developer Warehouse**: X-Small (1 credit/hour), auto-suspend 60s

#### Data Organization
- **Raw Layer**: Time-series data as received
- **Staging Layer**: Validated and cleansed data  
- **Aggregation Layer**: Minute/Hour/Day rollups
- **Analytics Layer**: Business-ready datasets

### 5. Analytics Layer

#### QuickSight (Primary Recommendation)
- **Deployment**: Embedded analytics
- **Multi-tenancy**: Row-level security using tags
- **Benefits**:
  - Native AWS integration
  - Serverless scaling
  - Cost-effective for large user base
  - No user provisioning required

#### PowerBI Embedded (Alternative)
- **Deployment**: Service principal profiles
- **Multi-tenancy**: Workspace per tenant
- **Benefits**:
  - Rich visualization capabilities
  - Familiar to many users
  - Advanced analytics features

#### Additional Options
- **Tableau**: For advanced self-service analytics
- **Snowsight**: Native SQL worksheets and exploration
- **Custom Dashboards**: React/D3.js for specific requirements

### 6. Application Layer

#### Web Portal
- **Technology**: React or Angular SPA
- **Hosting**: AWS ECS Fargate (containerized)
- **Features**:
  - Dashboard embedding
  - File upload interface
  - User management
  - Tenant administration

#### Authentication & Authorization
- **AWS Cognito**:
  - User pools for authentication
  - Identity pools for AWS resource access
  - SSO integration capability
  - MFA support

#### Load Balancing
- **Application Load Balancer**:
  - Multi-AZ deployment
  - SSL/TLS termination
  - Path-based routing
  - Health checks

---

## Security Architecture

### Network Security
- **VPC Design**:
  - CIDR: 10.0.0.0/16
  - Public subnets: ALB, NAT Gateways
  - Private subnets: Application and processing workloads
  - VPC Endpoints: S3, Snowflake PrivateLink

- **Security Controls**:
  - WAF for application protection
  - Security Groups for instance-level firewall
  - NACLs for subnet-level control
  - CloudTrail for audit logging

### Data Security
- **Encryption**:
  - At rest: S3 SSE, Snowflake automatic encryption
  - In transit: TLS 1.2+ for all connections
  - Key management: AWS KMS

- **Access Control**:
  - IAM roles for service-to-service authentication
  - Row-level security in Snowflake
  - Tenant isolation via access policies

### Compliance Considerations
- Data residency in EU (London region)
- GDPR compliance capability (though no PII expected)
- Audit trails via CloudTrail and Snowflake query history
- Regular security patching via managed services

---

## Multi-Tenancy Strategy

### Data Isolation Model
**Multi-Tenant Table (MTT) Pattern** with Row-Level Security:
- **Advantages**:
  - Simplified administration
  - Cost-effective resource utilization
  - Scales to thousands of tenants
  - Single schema to maintain

- **Implementation**:
  - Tenant ID in every table
  - Row Access Policies for isolation
  - Secure views for tenant-specific data
  - Context functions for tenant identification

### Dashboard Isolation
- **QuickSight**: Tag-based RLS, single dashboard serves all tenants
- **PowerBI**: Separate workspaces with service principal profiles
- **Portal**: JWT tokens with tenant claims

### Cost Attribution
- Snowflake resource monitors per tenant
- AWS cost allocation tags
- Usage tracking and reporting

---

## Data Flow Architecture

### Real-time Sensor Data Flow
```
1. Sensors → LoRaWAN Gateway → MQTT Protocol
2. MQTT → AWS IoT Core (TLS secured)
3. IoT Core → IoT Rules Engine (filtering/routing)
4. Rules → Kinesis Data Firehose (buffering)
5. Firehose → Lambda (transformation)
6. Lambda → S3 (compressed storage)
7. S3 → SQS Event Notification
8. SQS → Snowpipe (auto-ingest)
9. Snowpipe → Snowflake Raw Tables
10. Snowflake → Aggregations/Analytics
11. Analytics → BI Tools (QuickSight/PowerBI)
12. BI Tools → Web Portal (embedded)
```

### Batch File Upload Flow
```
1. User → Web Portal (authenticated)
2. Portal → S3 (presigned URL upload)
3. S3 → Lambda (file processing)
4. Lambda → S3 (processed files)
5. S3 → Snowpipe (auto-ingest)
6. Snowflake → Data processing
```

---

## Implementation Roadmap

### Phase 1: Foundation (Month 1)
- [ ] AWS account setup and networking
- [ ] Snowflake account provisioning
- [ ] Basic IoT Core configuration
- [ ] S3 bucket structure and IAM roles
- [ ] Initial Snowflake schema design

### Phase 2: Pilot (Month 2)
- [ ] Onboard 2-3 pilot SMEs
- [ ] Deploy core ingestion pipeline
- [ ] Implement basic dashboards
- [ ] Initial security configuration
- [ ] User acceptance testing

### Phase 3: Expansion (Months 3-4)
- [ ] Onboard 5-10 additional SMEs
- [ ] Enhance dashboard capabilities
- [ ] Implement full multi-tenancy
- [ ] Add monitoring and alerting
- [ ] Performance optimization

### Phase 4: Scale (Months 5-6)
- [ ] Scale to 30-40 SMEs
- [ ] Advanced analytics features
- [ ] ML model deployment
- [ ] Full production hardening
- [ ] Documentation and training

---

## Capacity Planning

### Storage Requirements
- **Daily Volume**: 105-157 MB compressed
- **Monthly Growth**: 3-5 GB
- **6-Month Projection**: 18-30 GB raw data
- **With Aggregations**: ~50 GB total

### Compute Requirements
- **Snowflake Credits**: 
  - Estimated 100-200 credits/month initially
  - Scaling to 300-500 credits at full capacity
- **AWS Costs**:
  - IoT Core: ~$50-100/month (based on messages)
  - S3: ~$20-50/month
  - Compute (Lambda, ECS): ~$200-400/month
  - Data Transfer: ~$50-100/month

### User Capacity
- **Named Users**: 20-40
- **Concurrent Users**: 10 peak
- **Dashboard Count**: 60-120
- **API Calls**: 10,000/day estimated

---

## Monitoring & Operations

### Key Metrics
- **Data Pipeline**:
  - Ingestion latency (<5 minutes target)
  - Pipeline success rate (>99.9% target)
  - Data quality scores

- **Performance**:
  - Dashboard load times (<3 seconds)
  - Query performance (p95 < 5 seconds)
  - Concurrent user capacity

- **Cost**:
  - Daily Snowflake credit usage
  - AWS service costs by component
  - Per-tenant resource consumption

### Monitoring Tools
- **CloudWatch**: Infrastructure metrics and logs
- **Snowflake Query History**: Performance analysis
- **CloudTrail**: Security and audit logs
- **Custom Dashboards**: Business KPIs

### Alerting Strategy
- Critical: Pipeline failures, security events
- Warning: Performance degradation, cost overruns
- Info: Daily summaries, usage reports

---

## Risk Mitigation

| Risk | Probability | Impact | Mitigation Strategy |
|------|------------|--------|-------------------|
| Data pipeline failure | Low | High | Multiple retry mechanisms, DLQ, monitoring |
| Cost overrun | Medium | Medium | Resource monitors, budget alerts, optimization |
| Security breach | Low | High | Defense in depth, encryption, regular audits |
| Vendor lock-in | Medium | Low | Open standards (Parquet, MQTT), portable code |
| Scalability issues | Low | Medium | Auto-scaling, managed services, capacity planning |
| Data quality issues | Medium | Medium | Validation rules, data profiling, monitoring |

---

## Cost Estimates

### Monthly Costs (at full scale)
- **Snowflake**: $1,500-2,500
  - Storage: $23/TB/month
  - Compute: Variable based on usage
  
- **AWS Services**: $800-1,500
  - IoT Core: $100-200
  - S3 Storage: $50-100
  - Compute (Lambda/ECS): $400-600
  - Networking: $100-200
  - Other services: $150-400

- **Total Infrastructure**: $2,300-4,000/month

### Cost Optimization Strategies
- Snowflake auto-suspend for warehouses
- S3 lifecycle policies for old data
- Reserved capacity for predictable workloads
- Monitoring and rightsizing resources

---

## Recommendations

### Immediate Actions
1. **Choose primary BI tool**: Recommend QuickSight for cost-effectiveness
2. **Confirm compliance requirements**: Verify GDPR/ISO 27001 needs
3. **Establish data governance**: Define retention policies and access controls
4. **Create proof of concept**: Validate architecture with subset of data

### Strategic Considerations
1. **Start with MTT pattern**: Simpler to manage, can evolve if needed
2. **Implement PrivateLink early**: Easier than retrofitting later
3. **Design for observability**: Include monitoring from day one
4. **Plan for ML/AI**: Include in schema design even if not immediate

### Success Criteria
- ✅ Meet <5 minute latency requirement
- ✅ Support 60 sensors scaling to more
- ✅ Enable multi-tenant isolation
- ✅ Deliver self-service analytics
- ✅ Maintain <$4,000/month infrastructure cost

---

## Appendices

### A. Technology Alternatives Considered
- **Streaming**: Kafka vs Kinesis (chose Kinesis for managed service)
- **Data Warehouse**: Redshift vs Snowflake (chose Snowflake for separation of compute/storage)
- **Container Orchestration**: EKS vs ECS (chose ECS for simplicity)

### B. Reference Architecture Patterns
- AWS IoT Reference Architecture
- Snowflake Multi-Tenant Design Patterns
- AWS Well-Architected Framework

### C. Useful Links
- [AWS IoT Core Documentation](https://docs.aws.amazon.com/iot/)
- [Snowflake Documentation](https://docs.snowflake.com/)
- [DevTank OpenSmartMonitor](https://opensmartmonitor.co.uk/)

---

## Document Control

- **Version**: 1.0
- **Date**: October 2024
- **Author**: Architecture Team
- **Status**: Draft for Review
- **Next Review**: Post-Pilot Phase

---

*This document represents the current architectural design and is subject to updates based on pilot feedback and evolving requirements.*