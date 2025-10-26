# Smart Manufacturing Data Hub (SMDH) - System Requirements Document

## Document Information
- **Version**: 1.0
- **Date**: October 2025
- **Status**: Approved
- **Owner**: AI Applied
- **Classification**: Internal Use

---

## 1. Executive Summary

The Smart Manufacturing Data Hub (SMDH) is a cloud-native, multi-tenant IoT platform designed to empower small and medium-sized manufacturing enterprises with real-time visibility into their operations. The system enables companies to self-register, onboard their manufacturing sites and IoT devices, and immediately start collecting and analysing data through intuitive dashboards.

### Core Mission

Provide a comprehensive, self-service platform where manufacturing companies can independently manage their entire data journey - from device registration to dashboard insights - without requiring technical expertise or external support.

---

## 2. Guiding Principles

The SMDH platform is built on two fundamental principles that drive all system design and functionality:

### Principle 1: Self-Service Company Onboarding

**Companies must be able to independently register and configure their entire manufacturing infrastructure through an intuitive portal.**

This principle ensures that:
- Manufacturing companies can sign up and create accounts without sales intervention
- Site administrators can register multiple manufacturing sites/facilities
- Users can configure IoT devices, metres, and sensors without technical knowledge
- Administrative roles can be assigned and managed by the company itself
- The onboarding experience is guided, streamlined, and requires minimal technical expertise

**Key Requirements:**
- Self-service registration workflow with company verification
- Multi-site management capability within a single company account
- Role-based user management (administrators, operators, viewers)
- Device provisioning wizard with automatic credential generation
- Configuration templates for common device types and use cases
- Step-by-step guided setup with validation at each stage

### Principle 2: Automated Data Collection and Visualisation

**Once registered, the system must automatically receive, store, and visualise data from configured devices without manual intervention.**

This principle ensures that:
- Data flows automatically from registered devices to the platform
- Historical data is stored securely with appropriate retention policies
- Pre-built dashboards are automatically provisioned based on device types
- Companies can view their data immediately upon device connection
- The system handles all data processing, transformation, and quality checks
- Dashboards update in real-time or near-real-time without user action

**Key Requirements:**
- Automated data ingestion pipelines supporting multiple protocols (MQTT, HTTP, LoRaWAN)
- Automatic data storage with multi-tenant isolation
- Pre-configured dashboard templates by use case (machine utilisation, air quality, job tracking)
- Real-time and historical data visualisation
- Automated alerts and notifications based on configurable thresholds
- Self-service dashboard customisation and report generation

---

## 3. Business Requirements

### 3.1 Platform Objectives

| Objective | Target | Priority |
|-----------|--------|----------|
| Support SME manufacturing companies | 30-40 companies (Year 1) | High |
| Concurrent active users | 20-40 users | High |
| Daily data processing capacity | 2.6M-3.9M rows/day | High |
| Platform availability | 99.9% uptime SLA | Critical |
| Data analytics latency | <5 minutes for KPIs | High |
| Real-time monitoring latency | <1 second for alerts | High |
| Dashboard provisioning time | <5 minutes after device registration | High |
| Onboarding completion time | <30 minutes for basic setup | Medium |

### 3.2 Target Users

**Primary Users:**
1. **Company Administrators** - Register company, manage sites, configure billing
2. **Site Administrators** - Register devices, manage site users, configure dashboards
3. **Operators** - View dashboards, receive alerts, generate reports
4. **Viewers** - Read-only access to dashboards and reports

**User Characteristics:**
- Limited technical expertise in IoT or cloud platforms
- Familiar with manufacturing operations and KPIs
- Need mobile and desktop access to dashboards
- Require intuitive, self-explanatory interfaces
- Value speed and simplicity over advanced configuration

### 3.3 Business Constraints

- **Budget**: Target cost of £200-300 per tenant per month
- **Geographic Coverage**: Initial deployment in UK/EU (data residency in eu-west-2)
- **Compliance**: GDPR, ISO 27001, SOC 2 Type II alignment
- **Scalability**: Must scale to 100+ companies within 3 years
- **Time to Market**: Phase 1 deployment within 6 months

---

## 4. Functional Requirements

### 4.1 Company and Site Management

#### FR-1: Company Registration
**Priority: Critical**

The system SHALL provide a self-service company registration process that:
- REQ-1.1: Allows new companies to create accounts with company details (name, address, industry, contact)
- REQ-1.2: Verifies company email addresses through automated confirmation
- REQ-1.3: Requires password meeting security standards (12+ chars, complexity)
- REQ-1.4: Supports multi-factor authentication (MFA) for administrator accounts
- REQ-1.5: Provides terms of service and privacy policy acceptance
- REQ-1.6: Creates a unique tenant identifier for complete data isolation
- REQ-1.7: Provisions default company administrator account
- REQ-1.8: Generates welcome email with onboarding instructions

**Acceptance Criteria:**
- Company can complete registration in <10 minutes
- All required fields are validated in real-time
- Email verification occurs within 5 minutes
- Company is immediately active after email confirmation

#### FR-2: Manufacturing Site Registration
**Priority: Critical**

The system SHALL enable companies to register multiple manufacturing sites:
- REQ-2.1: Support registration of unlimited manufacturing sites per company
- REQ-2.2: Capture site details (name, address, timezone, operating hours)
- REQ-2.3: Allow site-specific configuration and preferences
- REQ-2.4: Support site hierarchy (e.g., regions, facilities, departments)
- REQ-2.5: Enable archiving/deactivating sites without data loss
- REQ-2.6: Provide site-level reporting and analytics
- REQ-2.7: Support geographic visualisation of site locations

**Acceptance Criteria:**
- Sites can be registered in <5 minutes
- Site data is immediately available for device registration
- Changes to site configuration take effect within 1 minute

#### FR-3: User and Role Management
**Priority: Critical**

The system SHALL provide comprehensive user management capabilities:
- REQ-3.1: Support user roles: Company Admin, Site Admin, Operator, Viewer
- REQ-3.2: Allow Company Admins to invite users via email
- REQ-3.3: Enable role-based access control (RBAC) for all resources
- REQ-3.4: Support user assignment to specific sites
- REQ-3.5: Provide user activity audit logs
- REQ-3.6: Allow users to update their own profiles and preferences
- REQ-3.7: Support Single Sign-On (SSO) via SAML 2.0
- REQ-3.8: Enable session timeout and concurrent session limits
- REQ-3.9: Provide password reset and account recovery workflows

**Role Permissions:**

| Permission | Company Admin | Site Admin | Operator | Viewer |
|-----------|---------------|------------|----------|---------|
| Register sites | ✅ | ❌ | ❌ | ❌ |
| Manage company users | ✅ | ❌ | ❌ | ❌ |
| Register devices | ✅ | ✅ | ❌ | ❌ |
| Configure dashboards | ✅ | ✅ | ✅ | ❌ |
| View dashboards | ✅ | ✅ | ✅ | ✅ |
| Generate reports | ✅ | ✅ | ✅ | ✅ |
| Manage billing | ✅ | ❌ | ❌ | ❌ |

**Acceptance Criteria:**
- User invitation emails delivered within 1 minute
- Role changes take effect immediately
- Unauthorised access attempts are logged and blocked

### 4.2 Device and Metre Registration

#### FR-4: IoT Device Registration
**Priority: Critical**

The system SHALL provide a self-service device registration wizard:
- REQ-4.1: Support registration of various device types:
  - Machine utilisation sensors (power monitors, state sensors)
  - Air quality sensors (CO2, VOC, particulate matter, temperature/humidity)
  - Energy metres (smart metres, power monitors)
  - RFID readers and barcode scanners
  - Custom/generic IoT devices
- REQ-4.2: Auto-generate device credentials (X.509 certificates, API keys)
- REQ-4.3: Provide downloadable configuration files for devices
- REQ-4.4: Display connection instructions specific to device type
- REQ-4.5: Support bulk device import via CSV/Excel
- REQ-4.6: Provide device connectivity testing and validation
- REQ-4.7: Allow custom metadata and tags per device
- REQ-4.8: Support device grouping and hierarchical organisation
- REQ-4.9: Enable device firmware version tracking
- REQ-4.10: Provide device health monitoring and connectivity status

**Acceptance Criteria:**
- Device registration completes in <3 minutes per device
- Generated credentials are immediately valid
- Devices can connect within 1 minute of registration
- Connection status updates in real-time

#### FR-5: Device Configuration and Provisioning
**Priority: High**

The system SHALL simplify device configuration through templates:
- REQ-5.1: Provide pre-configured templates for common device types
- REQ-5.2: Support custom data schemas via JSON/YAML
- REQ-5.3: Auto-detect device schema from initial data transmission
- REQ-5.4: Allow configuration of data transmission frequency
- REQ-5.5: Support over-the-air (OTA) configuration updates
- REQ-5.6: Provide device twin/shadow for state management
- REQ-5.7: Enable batch configuration updates across device groups
- REQ-5.8: Support A/B testing of configuration changes

**Acceptance Criteria:**
- Configuration templates available for 10+ common device types
- Schema detection accuracy >95%
- Configuration changes propagate within 1 minute

### 4.3 Data Ingestion and Storage

#### FR-6: Automated Data Collection
**Priority: Critical**

The system SHALL automatically collect data from registered devices:
- REQ-6.1: Support multiple ingestion protocols:
  - MQTT v3.1.1 and v5 (primary for IoT sensors)
  - HTTP REST API (for RFID/barcode scanners)
  - LoRaWAN (via gateway integration)
  - File upload (CSV, Excel, JSON)
- REQ-6.2: Handle data rates up to 1Hz for high-frequency sensors
- REQ-6.3: Process batch data uploads up to 1GB per file
- REQ-6.4: Provide automatic retry for failed transmissions
- REQ-6.5: Support data buffering during network outages
- REQ-6.6: Implement dead letter queue for unprocessable messages
- REQ-6.7: Validate data against device schema automatically
- REQ-6.8: Enrich data with metadata (device ID, timestamp, tenant ID)
- REQ-6.9: Support data compression to reduce transmission costs
- REQ-6.10: Provide ingestion metrics and monitoring

**Data Volume Targets:**
- Daily ingestion: 2.6M - 3.9M data points
- Peak throughput: 60 messages/second per device
- Batch file processing: <5 minutes for 1GB file

**Acceptance Criteria:**
- Data appears in system within 5 seconds of transmission
- Zero data loss for successfully transmitted messages
- Failed messages retry automatically up to 3 times

#### FR-7: Data Storage and Retention
**Priority: Critical**

The system SHALL store all collected data securely:
- REQ-7.1: Maintain complete data isolation between tenants
- REQ-7.2: Store raw, unprocessed data for audit purposes
- REQ-7.3: Create normalised, query-optimised data views
- REQ-7.4: Implement automatic data aggregation (hourly, daily, weekly)
- REQ-7.5: Support configurable retention policies:
  - Raw data: 90 days
  - Aggregated data: 2 years
  - Reports and exports: 5 years
- REQ-7.6: Provide Time Travel capability (point-in-time recovery)
- REQ-7.7: Enable tenant-specific data export (CSV, JSON, Parquet)
- REQ-7.8: Support data anonymisation for tenant offboarding
- REQ-7.9: Implement automated backup and disaster recovery
- REQ-7.10: Provide storage metrics and usage reporting per tenant

**Storage Capacity Targets:**
- Year 1: 110-150 GB per company
- Growth rate: 10-15 GB per month per company
- Maximum single object size: 5 GB

**Acceptance Criteria:**
- Data is queryable within 30 seconds of ingestion
- Tenant data is completely isolated (verified via audit)
- Export requests complete within 15 minutes for 1 year of data

#### FR-8: Data Quality and Validation
**Priority: High**

The system SHALL ensure data quality automatically:
- REQ-8.1: Validate data types and formats against schema
- REQ-8.2: Detect and flag outliers using statistical methods
- REQ-8.3: Identify duplicate or missing data points
- REQ-8.4: Calculate data quality scores per device
- REQ-8.5: Alert administrators when quality drops below threshold
- REQ-8.6: Provide data profiling and quality reports
- REQ-8.7: Support custom validation rules per device type
- REQ-8.8: Automatically handle timezone conversions
- REQ-8.9: Detect and correct clock drift in device timestamps

**Acceptance Criteria:**
- Data quality checks complete within 1 second per record
- Quality issues are flagged in real-time
- Quality reports available daily

### 4.4 Dashboard and Visualisation

#### FR-9: Automated Dashboard Provisioning
**Priority: Critical**

The system SHALL automatically create dashboards upon device registration:
- REQ-9.1: Auto-provision default dashboards based on device type:
  - Machine Utilisation: OEE, energy consumption, uptime/downtime
  - Air Quality: Real-time readings, compliance status, trend analysis
  - Job Tracking: Production flow, cycle times, bottleneck analysis
  - Energy Management: Consumption patterns, cost analysis, efficiency
- REQ-9.2: Make dashboards available within 5 minutes of first data point
- REQ-9.3: Support real-time updates (1-second refresh for critical metrics)
- REQ-9.4: Provide historical trending and comparison views
- REQ-9.5: Enable drill-down from summary to detailed views
- REQ-9.6: Support custom date range selection
- REQ-9.7: Provide export functionality (PDF, PNG, CSV)
- REQ-9.8: Enable dashboard sharing via secure links
- REQ-9.9: Support mobile-responsive design
- REQ-9.10: Allow dashboard customisation (layout, colours, widgets)

**Dashboard Features by Use Case:**

**Machine Utilisation Analytics:**
- Real-time machine status (idle/operating/offline)
- Overall Equipment Effectiveness (OEE) trending
- Energy consumption by machine and time period
- Cost analysis with time-of-use tariff calculations
- Predictive maintenance alerts
- Production pattern clustering
- Shift-based performance comparison

**Air Quality Management:**
- Real-time environmental metrics (CO2, VOC, PM2.5, temperature, humidity)
- Compliance status indicators (HSE standards)
- Alert history and resolution tracking
- Trend analysis with forecasting
- Anomaly detection highlights
- Multi-location comparison views
- Regulatory reporting templates

**Job Location Tracking:**
- Real-time work-in-progress (WIP) by location
- Production flow visualisation (Sankey diagrams)
- Cycle time analysis by product and location
- Bottleneck identification heatmaps
- Throughput trending
- Job progression timelines (Gantt charts)
- Inventory level tracking

**Acceptance Criteria:**
- Dashboards load in <2 seconds
- Real-time data updates within 5 seconds
- Mobile dashboards functional on iOS and Android
- Export generation completes in <30 seconds

#### FR-10: Self-Service Reporting
**Priority: High**

The system SHALL enable users to create custom reports:
- REQ-10.1: Provide report builder with drag-and-drop interface
- REQ-10.2: Support scheduled report generation (daily, weekly, monthly)
- REQ-10.3: Enable email delivery of reports
- REQ-10.4: Provide report templates for common analyses
- REQ-10.5: Support multi-site and multi-device aggregation
- REQ-10.6: Allow custom KPI definition and tracking
- REQ-10.7: Enable report sharing within company users
- REQ-10.8: Support multiple output formats (PDF, Excel, CSV, HTML)
- REQ-10.9: Provide report execution history and audit trail

**Acceptance Criteria:**
- Report creation takes <10 minutes for non-technical users
- Scheduled reports deliver within 15 minutes of scheduled time
- Reports can aggregate data from up to 100 devices

### 4.5 Alerting and Notifications

#### FR-11: Automated Alert System
**Priority: High**

The system SHALL provide intelligent alerting capabilities:
- REQ-11.1: Support threshold-based alerts (above/below value)
- REQ-11.2: Enable anomaly detection using machine learning
- REQ-11.3: Provide multi-channel notifications:
  - Email
  - SMS (for critical alerts)
  - In-app notifications
  - Push notifications (mobile app)
  - Webhook integrations
- REQ-11.4: Support alert priority levels (low, medium, high, critical)
- REQ-11.5: Enable alert acknowledgement and resolution workflow
- REQ-11.6: Provide alert escalation rules
- REQ-11.7: Support alert suppression during maintenance windows
- REQ-11.8: Allow custom alert templates per device type
- REQ-11.9: Provide alert analytics and reporting
- REQ-11.10: Support alert rule testing before activation

**Pre-Configured Alert Thresholds:**

**Air Quality Alerts:**
- CO2: Warning at >1000 ppm, Critical at >5000 ppm
- PM2.5: Warning at >35 μg/m³, Critical at >150 μg/m³
- VOC: Warning at >220 ppb, Critical at >660 ppb
- Temperature: Warning at <16°C or >30°C

**Machine Utilisation Alerts:**
- Machine offline for >15 minutes
- Energy consumption >20% above baseline
- OEE drops below 70% for 1 hour
- Predictive maintenance required

**Acceptance Criteria:**
- Alerts trigger within 10 seconds of threshold breach
- Email notifications deliver within 1 minute
- SMS notifications deliver within 30 seconds
- Alert acknowledgement reflects in system within 1 second

---

## 5. Non-Functional Requirements

### 5.1 Performance Requirements

#### NFR-1: System Responsiveness
- **Web Portal**: Page load time <2 seconds (95th percentile)
- **Dashboard Rendering**: Initial load <2 seconds, refresh <500ms
- **API Response Time**: <200ms for 95% of requests
- **Data Ingestion Latency**: End-to-end <5 seconds from device to visualisation
- **Real-Time Monitoring**: Update frequency <1 second for critical metrics
- **Search Functionality**: Results returned in <1 second for typical queries

#### NFR-2: Scalability
- **Concurrent Users**: Support 20-40 concurrent users per tenant
- **Total Users**: Support 1000+ total users across all tenants
- **Data Throughput**: Handle 60 messages/second per device
- **Storage Growth**: Support 15 GB/month growth per tenant
- **Dashboard Count**: Support 60-120 dashboards per tenant
- **Device Count**: Support 1000+ devices per tenant
- **Tenant Scaling**: Scale from 30 to 100 tenants without architecture changes

#### NFR-3: Availability and Reliability
- **Uptime SLA**: 99.9% availability (excluding planned maintenance)
- **Planned Maintenance**: <4 hours/month, scheduled during low-usage periods
- **Mean Time To Recovery (MTTR)**: <1 hour for critical issues
- **Data Durability**: 99.999999999% (11 nines) durability for stored data
- **Backup Frequency**: Continuous replication with 15-minute RPO
- **Multi-AZ Deployment**: All critical components across multiple availability zones

### 5.2 Security Requirements

#### NFR-4: Authentication and Authorisation
- **User Authentication**:
  - Email/password with complexity requirements (12+ chars, mixed case, numbers, symbols)
  - Multi-factor authentication (MFA) required for administrator accounts
  - MFA optional for standard users
  - Session timeout after 30 minutes of inactivity
  - Maximum 3 failed login attempts before account lockout
- **Device Authentication**:
  - X.509 certificate-based authentication for MQTT devices
  - API key authentication for HTTP endpoints
  - Certificate rotation every 90 days
- **Authorisation**:
  - Role-based access control (RBAC) for all resources
  - Row-level security for data access (tenant isolation)
  - Least privilege principle enforced
  - Permission changes audit logged

#### NFR-5: Data Security
- **Encryption in Transit**:
  - TLS 1.2+ for all API communications
  - MQTT over TLS for IoT device connections
  - HTTPS-only for web portal
  - Certificate pinning for mobile apps
- **Encryption at Rest**:
  - AES-256 encryption for all stored data
  - Customer-managed encryption keys (optional)
  - Encrypted database backups
  - Encrypted log files
- **Data Privacy**:
  - Complete tenant data isolation
  - GDPR compliance for EU data
  - Right to erasure implementation
  - Data anonymisation for offboarded tenants
  - Privacy policy and terms acceptance required

#### NFR-6: Network Security
- **Perimeter Security**:
  - Web Application Firewall (WAF) protection
  - DDoS mitigation (up to 10 Gbps)
  - Rate limiting on all public endpoints
  - Geographic IP blocking (configurable)
- **Internal Security**:
  - Private subnets for application and data tiers
  - No public IP addresses on backend services
  - VPC endpoints for cloud service access
  - Network segmentation between components

#### NFR-7: Compliance and Auditing
- **Audit Logging**:
  - All user actions logged with timestamp, user ID, action, result
  - All data access logged (who accessed what data when)
  - All API calls logged with request/response metadata
  - Log retention: 1 year minimum
  - Tamper-proof audit logs
- **Compliance Standards**:
  - GDPR compliance for data privacy
  - ISO 27001 information security alignment
  - SOC 2 Type II readiness
  - Data residency: EU region (London - eu-west-2)
- **Security Assessments**:
  - Annual penetration testing
  - Quarterly vulnerability scanning
  - Continuous dependency vulnerability monitoring
  - Security incident response plan

### 5.3 Usability Requirements

#### NFR-8: User Experience
- **Learning Curve**: Non-technical users can complete onboarding in <30 minutes
- **Accessibility**: WCAG 2.1 Level AA compliance for web portal
- **Browser Support**:
  - Chrome (latest 2 versions)
  - Firefox (latest 2 versions)
  - Safari (latest 2 versions)
  - Edge (latest 2 versions)
- **Mobile Support**: Native experience on iOS 14+ and Android 10+
- **Language Support**: English (initial release), expandable to other languages
- **Help Documentation**:
  - Contextual help tooltips throughout interface
  - Searchable knowledge base
  - Video tutorials for common tasks
  - API documentation for integrations

#### NFR-9: Operational Excellence
- **Monitoring**:
  - Real-time system health dashboards
  - Proactive alerting for system issues
  - Performance metrics tracking
  - Cost monitoring and optimisation
- **Maintenance**:
  - Zero-downtime deployments for application updates
  - Automated database backups
  - Automated disaster recovery testing (quarterly)
  - Runbooks for common operational tasks
- **Support**:
  - In-app support ticket submission
  - Email support with 24-hour response time
  - Critical issue response within 1 hour
  - Monthly service status reports

### 5.4 Integration Requirements

#### NFR-10: API and Integration Capabilities
- **REST API**:
  - RESTful API for all platform functionality
  - OpenAPI 3.0 specification published
  - API versioning with backward compatibility
  - Rate limiting: 1000 requests/hour per user
  - Webhook support for event notifications
- **Data Export**:
  - Bulk export API with pagination
  - Scheduled exports to external systems
  - Support for CSV, JSON, Parquet formats
  - SFTP/S3 export destinations
- **Third-Party Integrations**:
  - ERP system connectors (future)
  - Manufacturing Execution Systems (MES) integration (future)
  - BI tool integration (Tableau, Power BI)
  - SSO providers (Azure AD, Okta, Google Workspace)

---

## 6. Use Case-Specific Requirements

### 6.1 Machine Utilisation Analytics (MUA)

**Business Objective**: Enable manufacturers to understand machine performance, identify inefficiencies, and optimise energy consumption.

#### Requirements:
- **UC-MUA-1**: Calculate Overall Equipment Effectiveness (OEE) automatically
  - Availability rate = (Operating Time / Planned Production Time)
  - Performance rate = (Ideal Cycle Time × Total Count / Operating Time)
  - Quality rate = (Good Count / Total Count)
  - OEE = Availability × Performance × Quality
- **UC-MUA-2**: Classify machine states automatically (idle vs. operating) using ML
  - Use Gaussian Mixture Models (GMM) for threshold detection
  - Adapt thresholds based on 2+ weeks of historical data
  - Accuracy target: >95% state classification
- **UC-MUA-3**: Calculate energy costs using Time-of-Use (ToU) tariffs
  - Support multiple tariff structures (flat, ToU, seasonal)
  - Automatic tariff application based on timestamp
  - Cost allocation by machine, shift, and production run
- **UC-MUA-4**: Detect production patterns and clusters
  - Use DBSCAN clustering for pattern analysis
  - Identify typical production cycles
  - Flag deviations from normal patterns
- **UC-MUA-5**: Provide predictive maintenance alerts
  - Analyse utilisation trends for anomaly detection
  - Alert on unusual energy consumption patterns
  - Recommend maintenance based on operational hours

**Data Requirements:**
- Sensor frequency: 1 Hz for power monitoring
- Data retention: 90 days raw data, 2 years aggregated
- Metrics tracked: Current, voltage, power, power factor, kWh, machine state

### 6.2 Air Quality Management Analytics (AQMA)

**Business Objective**: Ensure worker safety and regulatory compliance by monitoring environmental conditions in manufacturing facilities.

#### Requirements:
- **UC-AQMA-1**: Monitor air quality metrics in real-time
  - CO2 levels (ppm)
  - Volatile Organic Compounds - VOC (ppb)
  - Particulate Matter - PM1, PM2.5, PM4, PM10 (μg/m³)
  - Temperature (°C)
  - Humidity (%)
  - Atmospheric pressure (hPa)
- **UC-AQMA-2**: Implement configurable alerting thresholds
  - Pre-configured defaults based on HSE standards
  - Custom thresholds per tenant
  - Multi-level alerts (warning, critical)
  - Alert suppression during known events
- **UC-AQMA-3**: Calculate Air Quality Index (AQI)
  - Real-time AQI calculation based on PM2.5 and CO2
  - Visual indicators (Good, Moderate, Poor)
  - Trend analysis and forecasting
- **UC-AQMA-4**: Generate compliance reports automatically
  - Daily, weekly, monthly summaries
  - HSE compliance reporting format
  - Workplace Exposure Limit (WEL) tracking
  - Exportable PDF reports
- **UC-AQMA-5**: Detect anomalies using machine learning
  - Identify sudden spikes or drops
  - Predict poor air quality events
  - Correlate with external factors (weather, production activity)

**Data Requirements:**
- Sensor frequency: 1-minute intervals
- Data retention: 2 years minimum for compliance
- Alert latency: <10 seconds from threshold breach
- Report generation: Automated monthly

### 6.3 Job Location Tracking

**Business Objective**: Track products through manufacturing workflows to optimise production flow and identify bottlenecks.

#### Requirements:
- **UC-JLT-1**: Capture location scan events
  - RFID reader integration
  - Barcode scanner integration
  - Manual entry via web/mobile interface
  - Batch scanning support
- **UC-JLT-2**: Track work-in-progress (WIP) by location
  - Real-time inventory at each production stage
  - Location categories:
    - Complete
    - Punched
    - Waiting
    - Local Painting
    - Drying
    - Stored
  - WIP ageing analysis
- **UC-JLT-3**: Calculate cycle times automatically
  - Time between location transitions
  - Total cycle time per job/product
  - Average cycle time by product type
  - Comparison to target cycle times
- **UC-JLT-4**: Identify production bottlenecks
  - Detect locations with high dwell times
  - Highlight stages with WIP accumulation
  - Heatmap visualisation of bottlenecks
  - Root cause analysis recommendations
- **UC-JLT-5**: Visualise production flow
  - Sankey diagrams showing product flow
  - Gantt charts for job timelines
  - Real-time production status boards
  - Historical flow pattern analysis

**Data Requirements:**
- Event-driven data collection
- Volume: 500-2,000 scans per day per facility
- Scan-to-dashboard latency: <5 seconds
- Data retention: 1 year minimum

---

## 7. Data and Integration Requirements

### 7.1 Data Protocols and Formats

**Supported Ingestion Protocols:**
- **MQTT**: v3.1.1 and v5 over TLS (primary for sensors)
- **HTTP/HTTPS**: REST API for event-driven data and file uploads
- **LoRaWAN**: Via gateway integration
- **File Upload**: Web portal for CSV, Excel, JSON, PDF

**Data Formats:**
- **Real-time Sensors**: JSON payload over MQTT
- **Batch Files**: CSV, Excel (.xlsx), JSON, Parquet
- **API Calls**: JSON request/response
- **Reports**: PDF, Excel, CSV, HTML

**Data Schema Management:**
- Automatic schema detection from VARIANT/JSON columns
- Schema evolution support with versioning
- Backward compatibility for schema changes
- Data contract enforcement via validation rules

### 7.2 External System Integration

**Identity Providers:**
- SAML 2.0 (Azure AD, Okta, Google Workspace)
- OAuth 2.0 / OpenID Connect
- LDAP/Active Directory (future)

**Notification Channels:**
- Email (SMTP)
- SMS (Twilio, AWS SNS)
- Push notifications (Firebase, APNs)
- Webhooks for custom integrations
- Slack/Teams integration (future)

**Analytics Tools:**
- Amazon QuickSight (embedded dashboards)
- Power BI (via Snowflake connector)
- Tableau (via Snowflake connector)
- Grafana (for real-time monitoring)
- Custom visualisation via REST API

---

## 8. System Constraints and Assumptions

### 8.1 Technical Constraints

- **Cloud Platform**: AWS (eu-west-2 region) - no multi-cloud support initially
- **Data Warehouse**: Snowflake - primary data storage and analytics platform
- **Programming Languages**:
  - Backend: Python 3.9+, Node.js 18+
  - Frontend: TypeScript with React 18+
  - Data Processing: SQL, Python (Snowpark)
- **Browser Requirements**: Modern browsers only (no IE11 support)
- **Mobile**: Responsive web initially, native apps in future phases

### 8.2 Business Constraints

- **Pricing Model**: Subscription-based, per-tenant pricing
- **Support Model**: Email support standard, phone support premium tier
- **Geographic Coverage**: UK/EU initially, US expansion in Year 2
- **Tenant Isolation**: Complete logical separation, no data sharing between tenants
- **Customisation**: Configuration-based, no custom code per tenant

### 8.3 Assumptions

- Manufacturing sites have stable internet connectivity (>1 Mbps)
- IoT devices support MQTT over TLS or HTTP
- Users have modern devices (manufactured within last 5 years)
- Companies have email infrastructure for notifications
- Average 50-100 devices per tenant
- Average 5-10 users per tenant
- Data predominantly numerical sensor readings
- No personally identifiable information (PII) in sensor data
- Companies responsible for device hardware procurement
- Platform provides configuration guidance, not device installation

---

## 9. Success Criteria

### 9.1 User Success Metrics

| Metric | Target | Measurement Method |
|--------|--------|-------------------|
| Onboarding completion rate | >90% | Track registration to first dashboard |
| Time to first insight | <1 hour | Registration to viewing first dashboard |
| User satisfaction score | >4.0/5.0 | Quarterly NPS surveys |
| Dashboard usage frequency | >3x/week per user | Analytics tracking |
| Feature adoption rate | >60% | Track feature usage across users |
| Support ticket reduction | <1 ticket/tenant/month | Support system metrics |

### 9.2 Technical Success Metrics

| Metric | Target | Measurement Method |
|--------|--------|-------------------|
| System uptime | >99.9% | CloudWatch monitoring |
| Data ingestion success rate | >99.95% | Pipeline metrics |
| Dashboard load time | <2 seconds (p95) | Real User Monitoring (RUM) |
| API error rate | <0.1% | CloudWatch metrics |
| Data quality score | >95% | Automated quality checks |
| Alert accuracy | >90% | False positive tracking |

### 9.3 Business Success Metrics

| Metric | Target | Measurement Method |
|--------|--------|-------------------|
| Customer acquisition | 30 companies (Year 1) | CRM tracking |
| Customer retention | >90% annual | Churn analysis |
| Revenue per tenant | £200-300/month | Billing system |
| Tenant growth rate | 30% YoY | Business analytics |
| Net Promoter Score | >50 | Quarterly surveys |

---

## 10. Out of Scope (Initial Release)

The following features are explicitly out of scope for the initial release but may be considered for future phases:

**Advanced Features:**
- ❌ Mobile native applications (iOS/Android)
- ❌ Computer vision for quality inspection
- ❌ Voice assistant integration (Alexa, Google)
- ❌ Predictive quality analytics
- ❌ Supply chain optimisation
- ❌ ERP/MES system integration
- ❌ GraphQL API
- ❌ Real-time collaboration features
- ❌ Custom ML model development by tenants
- ❌ Blockchain-based data provenance

**Operational Features:**
- ❌ White-label/reseller capabilities
- ❌ Multi-cloud deployment
- ❌ On-premise deployment option
- ❌ Custom SLA per tenant
- ❌ 24/7 phone support (premium tier only)

**Regional Features:**
- ❌ Languages other than English
- ❌ Currency support beyond GBP/EUR
- ❌ Regions outside EU
- ❌ Compliance certifications beyond GDPR/ISO 27001

---

## 11. Implementation Priorities

### Phase 1 - Foundation (Months 1-2)
**Priority: Critical**

- Company and site registration
- User management and RBAC
- Basic device registration (manual)
- MQTT data ingestion pipeline
- Data storage with tenant isolation
- Basic dashboard for one use case (MUA)

### Phase 2 - Core Features (Months 3-4)
**Priority: High**

- Device registration wizard with templates
- All three use cases (MUA, AQMA, Job Tracking)
- Automated dashboard provisioning
- Threshold-based alerting
- Email notifications
- Self-service report builder
- Mobile-responsive web portal

### Phase 3 - Advanced Features (Months 5-6)
**Priority: Medium**

- Machine learning anomaly detection
- Predictive maintenance alerts
- Advanced analytics (OEE, AQI)
- Bulk device import
- API documentation and external access
- SSO integration
- Advanced visualisation (Sankey, Gantt)
- Performance optimisation

### Phase 4 - Scale and Polish (Months 7-8)
**Priority: Low**

- Multi-tenant scale testing
- Security hardening
- Compliance audit preparation
- Production monitoring enhancement
- User training materials
- Beta customer onboarding
- Performance tuning

---

## 12. Appendices

### Appendix A: Glossary

| Term | Definition |
|------|------------|
| **SME** | Small and Medium-sized Enterprise (manufacturing companies with 10-250 employees) |
| **OEE** | Overall Equipment Effectiveness - metric combining availability, performance, and quality |
| **ToU Tariff** | Time-of-Use electricity tariff with different rates at different times of day |
| **MQTT** | Message Queuing Telemetry Transport - lightweight IoT messaging protocol |
| **LoRaWAN** | Long Range Wide Area Network - wireless protocol for IoT devices |
| **RBAC** | Role-Based Access Control - permission system based on user roles |
| **RLS** | Row-Level Security - database security filtering data by user/tenant |
| **AQI** | Air Quality Index - composite score of air quality based on multiple pollutants |
| **HSE** | Health and Safety Executive - UK regulatory body |
| **WEL** | Workplace Exposure Limit - maximum concentration of hazardous substance |
| **WIP** | Work-in-Progress - products currently in manufacturing process |
| **GMM** | Gaussian Mixture Model - machine learning algorithm for clustering |
| **DBSCAN** | Density-Based Spatial Clustering - ML algorithm for pattern detection |

### Appendix B: Reference Documents

- SMDH Architecture Design Document v2.0
- SMDH Complete Architecture Guide
- SMDH Option B: Snowflake-Leveraged Architecture
- Machine Utilisation Use Case Document
- Air Quality Use Case Document
- Job Location Tracking Use Case Document

### Appendix C: Compliance and Standards

**Regulatory Compliance:**
- GDPR (General Data Protection Regulation)
- UK GDPR post-Brexit
- ISO 27001 (Information Security Management)
- SOC 2 Type II (Service Organisation Control)
- HSE Workplace Exposure Limits (WELs)

**Technical Standards:**
- MQTT v3.1.1 and v5 (OASIS Standard)
- TLS 1.2 and 1.3 (RFC 5246, RFC 8446)
- OAuth 2.0 (RFC 6749)
- SAML 2.0 (OASIS Standard)
- OpenAPI 3.0 (REST API specification)
- WCAG 2.1 Level AA (Web accessibility)

### Appendix D: Contact Information

**Project Ownership:**
- **Company**: AI Applied
- **Website**: https://aiapplied.com
- **Project Repository**: https://github.com/aiapplied/smdh

**Support:**
- **Technical Support**: smdh-support@aiapplied.com
- **Business Enquiries**: info@aiapplied.com
- **Security Issues**: security@aiapplied.com

---

## Document Approval

| Role | Name | Signature | Date |
|------|------|-----------|------|
| Product Owner | | | |
| Technical Architect | | | |
| Security Lead | | | |
| Compliance Officer | | | |

---

**Document Version**: 1.0
**Last Updated**: October 2025
**Next Review**: January 2026
**Status**: Approved for Development

---

*This document represents the complete system requirements for the Smart Manufacturing Data Hub platform and serves as the authoritative source for all development, testing, and deployment activities.*
