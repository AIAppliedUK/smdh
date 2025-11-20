# Smart Manufacturing Data Hub (SMDH) - System Requirements Document

## Document Information
- **Version**: 0.2 (Architectural Review Update)
- **Date**: November 2, 2025
- **Status**: Updated Based on Architectural Review Feedback
- **Owner**: AI Applied
- **Classification**: Internal Use
- **Change Summary**:
  - v1.1 (Nov 1): Removed arbitrary budget targets and timing constraints
  - v0.2 (Nov 2): Updated based on comprehensive architectural review feedback including:
    - Split latency SLAs (operator dashboards ≤60s vs safety alerts ≤5-10s)
    - Enhanced security and operational requirements
    - Added portal assumptions and authentication requirements
    - Clarified multi-tenancy isolation requirements
    - Added observability and monitoring requirements

---

## 1. Executive Summary

The Smart Manufacturing Data Hub (SMDH) is a cloud-based platform that gives small and medium-sized manufacturing companies real-time visibility of their operations. Companies can register themselves, add their sites and devices, and immediately start collecting and viewing their data through dashboards.

### Core Mission

Let manufacturing companies manage their own data from start to finish—device setup to insights—without needing technical knowledge or external help.

---

## 2. Guiding Principles

The SMDH platform is built on two core principles:

### Principle 1: Self-Service Company Onboarding

**Companies must be able to register and set up their manufacturing infrastructure themselves through a simple portal.**

What this means:
- Companies can sign up without talking to sales
- Site administrators can register multiple sites
- Users can set up devices and sensors without technical knowledge
- Companies can assign and manage their own user roles
- The setup process is guided and simple

**Key Requirements:**
- Self-service registration workflow with company verification
- Multi-site management capability within a single company account
- Role-based user management (administrators, operators, viewers)
- Device provisioning wizard with automatic credential generation
- Configuration templates for common device types and use cases
- Step-by-step guided setup with validation at each stage

### Principle 2: Automated Data Collection and Visualisation

**Once registered, the system must automatically receive, store, and display data from configured devices without manual work.**

What this means:
- Data flows automatically from registered devices to the platform
- Historical data is stored securely
- Dashboards are created automatically based on device types
- Companies can view their data as soon as devices connect
- The system handles all data processing and quality checks
- Dashboards update automatically

**Key Requirements:**
- Automated data ingestion pipelines supporting multiple protocols (MQTT, HTTP, LoRaWAN)
- Automatic data storage with multi-tenant isolation
- Pre-configured dashboard templates by use case (machine utilisation, air quality, job tracking)
- Real-time and historical data visualisation
- Automated alerts and notifications based on configurable thresholds
- Self-service dashboard customisation and report generation

---

## 3. Business Requirements

### 3.1 Platform Targets

| What | Target | Priority |
|-----------|--------|----------|
| Support SME manufacturing companies | 30-40 companies (Year 1), growing to 100 | High |
| Users logged in at once | 20-40 users | High |
| Daily data processing | 2.6M-3.9M rows/day per company | High |
| Uptime | 99.9% (≤43 minutes downtime/month) | Critical |
| Dashboard data refresh for analytics | Within 5 minutes | High |
| Safety/critical alerts | Within 5-10 seconds | Medium |
| Operational alerts | Within 60 seconds | High |
| Operator dashboard refresh | Within 60 seconds for most uses | High |
| Dashboard creation | Within 5 minutes after device registration | High |
| Basic setup completion | Within 30 minutes | Medium |

### 3.2 Target Users

**Who will use this:**
1. **Company Administrators** - Register company, manage sites, handle billing
2. **Site Administrators** - Register devices, manage site users, set up dashboards
3. **Operators** - View dashboards, get alerts, create reports
4. **Viewers** - Read-only access to dashboards and reports

**What users are like:**
- Not technical experts in IoT or cloud
- Know their manufacturing operations
- Need access from mobile and desktop
- Need simple, clear interfaces
- Want speed and simplicity over advanced options

### 3.3 Business Constraints

- **Cost**: Infrastructure costs must match actual usage and grow linearly with number of companies
- **Location**: Initial deployment in UK/EU (data stored in London region)
- **Compliance**: Must meet GDPR, ISO 27001, SOC 2 Type II standards
- **Growth**: Must support 100+ companies within 3 years
- **Launch**: Phase 1 delivery date to be set after architecture selection

---

## 4. Functional Requirements

### 4.1 Company and Site Management

#### FR-1: Company Registration
**Priority: Critical**

The system must let companies register themselves:
- REQ-1.1: New companies can create accounts with their details (name, address, industry, contact)
- REQ-1.2: Email addresses are verified automatically
- REQ-1.3: Passwords must be secure (12+ characters, mixed case, numbers, symbols)
- REQ-1.4: Multi-factor authentication available for administrators
- REQ-1.5: Terms of service and privacy policy must be accepted
- REQ-1.6: Each company gets a unique identifier to keep their data separate
- REQ-1.7: Creates a default administrator account
- REQ-1.8: Sends a welcome email with setup instructions

**Must achieve:**
- Registration completed in under 10 minutes
- All fields checked immediately as typed
- Email verification within 5 minutes
- Company active immediately after email confirmation

#### FR-2: Manufacturing Site Registration
**Priority: Critical**

The system must let companies register multiple sites:
- REQ-2.1: Unlimited sites per company
- REQ-2.2: Capture site details (name, address, timezone, operating hours)
- REQ-2.3: Site-specific settings
- REQ-2.4: Site hierarchy (regions, facilities, departments)
- REQ-2.5: Archive/deactivate sites without losing data
- REQ-2.6: Site-level reporting
- REQ-2.7: Geographic visualisation of sites

**Must achieve:**
- Sites registered in under 5 minutes
- Site available for device registration immediately
- Configuration changes take effect within 1 minute

#### FR-3: User and Role Management
**Priority: Critical**

The system must provide user management:
- REQ-3.1: User roles: Company Admin, Site Admin, Operator, Viewer
- REQ-3.2: Company Admins can invite users by email
- REQ-3.3: Role-based access control for all resources
- REQ-3.4: Users can be assigned to specific sites
- REQ-3.5: User activity logs
- REQ-3.6: Users can update their own profiles
- REQ-3.7: Single Sign-On (SSO) via SAML 2.0
- REQ-3.8: Session timeout and limits on simultaneous logins
- REQ-3.9: Password reset and account recovery

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

**Must achieve:**
- Invitation emails sent within 1 minute
- Role changes take effect immediately
- Blocked access attempts are logged

### 4.2 Device and Metre Registration

#### FR-4: IoT Device Registration
**Priority: Critical**

The system must provide a device registration wizard:
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

**Must achieve:**
- Device registration in under 3 minutes per device
- Credentials work immediately
- Devices connect within 1 minute of registration
- Connection status updates in real-time

#### FR-5: Device Configuration and Provisioning
**Priority: High**

The system must simplify device setup through templates:
- REQ-5.1: Provide pre-configured templates for common device types
- REQ-5.2: Support custom data schemas via JSON/YAML
- REQ-5.3: Auto-detect device schema from initial data transmission
- REQ-5.4: Allow configuration of data transmission frequency
- REQ-5.5: Support over-the-air (OTA) configuration updates
- REQ-5.6: Provide device twin/shadow for state management
- REQ-5.7: Enable batch configuration updates across device groups
- REQ-5.8: Support A/B testing of configuration changes

**Must achieve:**
- Templates for 10+ common device types
- Schema detection accuracy above 95%
- Configuration changes take effect within 1 minute

### 4.3 Data Ingestion and Storage

#### FR-6: Automated Data Collection
**Priority: Critical**

The system must automatically collect data from registered devices:
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

**Must achieve:**
- Data appears in system within 5 seconds of sending
- No data loss for successfully sent messages
- Failed messages retry automatically up to 3 times

#### FR-7: Data Storage and Retention
**Priority: Critical**

The system must store all collected data securely:
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

**Must achieve:**
- Data can be queried within 30 seconds of arrival
- Company data is completely isolated (verified by audit)
- Export requests complete within 15 minutes for 1 year of data

#### FR-8: Data Quality and Validation
**Priority: High**

The system must check data quality automatically:
- REQ-8.1: Validate data types and formats against schema
- REQ-8.2: Detect and flag outliers using statistical methods
- REQ-8.3: Identify duplicate or missing data points
- REQ-8.4: Calculate data quality scores per device
- REQ-8.5: Alert administrators when quality drops below threshold
- REQ-8.6: Provide data profiling and quality reports
- REQ-8.7: Support custom validation rules per device type
- REQ-8.8: Automatically handle timezone conversions
- REQ-8.9: Detect and correct clock drift in device timestamps

**Must achieve:**
- Data quality checks complete within 1 second per record
- Quality issues flagged in real-time
- Quality reports available daily

### 4.4 Dashboard and Visualisation

#### FR-9: Automated Dashboard Creation
**Priority: Critical**

The system must automatically create dashboards when devices are registered:
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

**Must achieve:**
- Dashboards load in under 2 seconds
- Real-time data updates within 5 seconds
- Dashboards work on iOS and Android
- Exports complete in under 30 seconds

#### FR-10: Self-Service Reporting
**Priority: High**

The system must let users create their own reports:
- REQ-10.1: Provide report builder with drag-and-drop interface
- REQ-10.2: Support scheduled report generation (daily, weekly, monthly)
- REQ-10.3: Enable email delivery of reports
- REQ-10.4: Provide report templates for common analyses
- REQ-10.5: Support multi-site and multi-device aggregation
- REQ-10.6: Allow custom KPI definition and tracking
- REQ-10.7: Enable report sharing within company users
- REQ-10.8: Support multiple output formats (PDF, Excel, CSV, HTML)
- REQ-10.9: Provide report execution history and audit trail

**Must achieve:**
- Non-technical users can create reports in under 10 minutes
- Scheduled reports arrive within 15 minutes of scheduled time
- Reports can combine data from up to 100 devices

### 4.5 Alerting and Notifications

#### FR-11: Automated Alert System
**Priority: High**

The system must provide alerting:
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

**Must achieve:**
- Alerts trigger within appropriate time based on criticality (see note below)
- Email notifications sent within 1 minute
- SMS notifications sent within 30 seconds for critical alerts
- Alert acknowledgement shown in system within 1 second

> **⚠️ VALIDATION REQUIRED**: Alert latency requirements (previously specified as <10 seconds) need validation with manufacturing operators to determine actual operational needs. Different alert types may require different latencies:
> - **Critical safety alerts** (e.g., toxic gas levels): Immediate (<10 seconds may be required)
> - **Operational alerts** (e.g., machine offline): Standard (<60 seconds may be acceptable)
> - **Informational alerts** (e.g., trending issues): Non-urgent (<5 minutes may be acceptable)

---

## 5. Non-Functional Requirements

### 5.1 Performance

#### NFR-1: How Fast the System Must Be
- **Web Portal**: Pages load in under 2 seconds (for 95% of users)
- **Dashboards**: Initial load under 2 seconds, updates under 500ms
- **API**: Responds in under 200ms for 95% of requests
- **Data Processing**: Under 5 seconds from device sending data to it appearing on dashboards
- **Dashboard Updates**: Update speed depends on use (critical alerts: under 10s, operational dashboards: under 60s, historical reports: under 5 min)
- **Search**: Results in under 1 second for typical searches

> **Note**: Update speeds vary by use. Critical safety monitoring needs updates in under 10 seconds, while operational dashboards can update every 30-60 seconds. Architecture should match actual needs, not theoretical ideals.

#### NFR-2: Growth Capacity
- **Users Logged In**: 20-40 users logged in at once per company
- **Total Users**: 1000+ users across all companies
- **Data Processing**: 60 messages/second per device
- **Storage**: 15 GB/month growth per company
- **Dashboards**: 60-120 dashboards per company
- **Devices**: 1000+ devices per company
- **Companies**: Grow from 30 to 100 companies without changing architecture

#### NFR-3: Uptime and Reliability
- **Uptime**: 99.9% (excluding planned maintenance)
- **Maintenance**: Under 4 hours/month, during quiet periods
- **Recovery Time**: Under 1 hour for critical issues
- **Data Safety**: 99.999999999% (11 nines) - data won't be lost
- **Backups**: Continuous backup with 15-minute recovery point
- **Redundancy**: All critical parts run across multiple data centres

### 5.2 Security

#### NFR-4: Who Can Access What
- **User Login**:
  - Email/password (12+ characters, mixed case, numbers, symbols)
  - Two-factor authentication required for administrators
  - Two-factor authentication optional for other users
  - Logged out after 30 minutes of inactivity
  - Account locked after 3 failed login attempts
- **Device Login**:
  - Certificate-based login for MQTT devices
  - API key login for HTTP devices
  - Certificates rotated every 90 days
- **Permissions**:
  - Role-based access (what you can do depends on your role)
  - Data isolation (companies can only see their own data)
  - Minimum permissions needed (users only get access they need)
  - All permission changes logged

#### NFR-5: Data Protection
- **Data in Transit** (while moving):
  - TLS 1.2+ encryption for all API calls
  - MQTT over TLS for device connections
  - HTTPS-only for web portal
  - Certificate pinning for mobile apps
- **Data at Rest** (while stored):
  - AES-256 encryption for all stored data
  - Customer-managed encryption keys (optional)
  - Encrypted backups
  - Encrypted logs
- **Privacy**:
  - Complete data isolation between companies
  - GDPR compliance for EU data
  - Right to deletion
  - Data anonymisation when companies leave
  - Privacy policy and terms must be accepted

#### NFR-6: Network Protection
- **Edge Protection**:
  - Web Application Firewall (WAF)
  - DDoS attack mitigation (up to 10 Gbps)
  - Rate limiting on all public access points
  - Geographic IP blocking (configurable)
- **Internal Protection**:
  - Private networks for application and data
  - No public IP addresses on backend services
  - Private endpoints for cloud services
  - Network separation between components

#### NFR-7: Compliance and Audit Logs
- **Audit Logs**:
  - All user actions logged (when, who, what, result)
  - All data access logged (who looked at what and when)
  - All API calls logged
  - Logs kept for 7 years (GDPR, SOC 2 requirements)
  - Tamper-proof logs (write-once storage)
  - Logs can be searched and queried
- **Compliance**:
  - GDPR compliant for data privacy
  - ISO 27001 information security aligned
  - SOC 2 Type II ready
  - Data stored in EU (London region)
  - HIPAA ready with BAA (future healthcare use)
- **Security Testing**:
  - Penetration testing yearly
  - Vulnerability scanning quarterly
  - Continuous dependency monitoring
  - Breach notification within 72 hours
- **User Data Rights (GDPR)**:
  - Right to Access: Export all data within 5-10 days
  - Right to Deletion: Delete all personal data within 30 days
  - Minimal personal data: No personal info in sensor data (device ID only)
  - Automated where possible

### 5.3 Usability

#### NFR-8: User Experience
- **Ease of Use**: Non-technical users can complete setup in under 30 minutes
- **Accessibility**: WCAG 2.1 Level AA compliant
- **Browser Support**:
  - Chrome (latest 2 versions)
  - Firefox (latest 2 versions)
  - Safari (latest 2 versions)
  - Edge (latest 2 versions)
- **Mobile**: Works on iOS 14+ and Android 10+
- **Language**: English (initial release), expandable later
- **Help**:
  - Tooltips throughout
  - Searchable help articles
  - Video tutorials for common tasks
  - API documentation

#### NFR-9: Operations
- **Monitoring**:
  - Real-time system health dashboards
  - Alerts for system issues
  - Performance tracking:
    - Ingest Lag: ≤10 seconds (P95) - time from device send to storage write
    - Write Errors: ≤0.1% (P99) - failed writes / total writes
    - Alert Time-to-Notify: ≤10 seconds (P95) - event to SNS notification
    - Dashboard Freshness: ≤60 seconds (P95) - last data refresh timestamp
    - Query Latency: ≤5 seconds (P95) - dashboard load time
    - Availability: ≥99.9% - successful API calls / total
  - Error budget tracking: 99.9% = 43 minutes downtime/month budget
  - Cost monitoring and optimisation
- **Disaster Recovery**:
  - RPO (Recovery Point Objective): ≤5 minutes
  - RTO (Recovery Time Objective): ≤30 minutes for full service restoration
  - Automated database backups with continuous replication
  - Automated disaster recovery testing (quarterly)
  - Multi-AZ deployment for all critical components
  - Cross-region backup for business continuity
- **Replay & Backfill**:
  - Idempotent event processing with structured event IDs: {device_id}_{timestamp_ms}_{sequence_number}
  - Data retention: 7 days in hot storage (configurable to 365 days)
  - Deduplication window: 5 minutes for replay protection
  - Backfill capability: Up to 7 days from hot storage, unlimited from archival storage
- **Schema Evolution**:
  - Backward-compatible schema changes
  - 30-day dual-schema support for device migration
  - Staged rollout for breaking changes
- **Tenant Off-Boarding**:
  - 30-day notice period before data deletion
  - Full data export (CSV/Parquet) provided to tenant
  - IoT certificate revocation immediate upon termination
  - 90-day soft delete period before physical purge
  - Audit logs retained for 7 years post-termination
- **Maintenance**:
  - Zero-downtime deployments for application updates
  - Runbooks for common operational tasks
  - Automated failover for critical components
- **Support**:
  - In-app support ticket submission
  - Email support with 24-hour response time
  - Critical issue response within 1 hour
  - Monthly service status reports

### 5.4 Integrations

#### NFR-10: APIs and Connections to Other Systems
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

### 5.5 Portal Authentication & Authorization (v0.2 Addition)

> **Note**: This section documents authentication and authorization requirements based on architectural review feedback. The customer access portal implementation is out of scope for the initial infrastructure design.

#### NFR-11: Authentication (AuthN)
- **Identity Provider**:
  - Amazon Cognito User Pools as managed authentication service
  - OIDC integration for SSO with customer IdPs (Azure AD, Okta, Google Workspace)
  - Support for social login (optional): Google, Microsoft
- **Authentication Methods**:
  - Email/password with complexity requirements (12+ characters)
  - Multi-Factor Authentication (MFA):
    - Mandatory for Org Admin and Site Admin roles
    - Optional for Operator and Read-Only roles
    - Supported methods: SMS, TOTP authenticator (e.g., Google Authenticator, Authy)
- **Session Management**:
  - Session token expiry: 8 hours
  - Refresh tokens: 30-day validity with automatic renewal
  - Session timeout: 30 minutes of inactivity
  - Concurrent session limit: 3 active sessions per user
- **Password Policy**:
  - Minimum 12 characters
  - Complexity: Mixed case, numbers, symbols required
  - Password expiration: Optional (not enforced by default)
  - Password history: Cannot reuse last 5 passwords
  - Account lockout: 3 failed attempts, 15-minute lockout

#### NFR-12: Organization & Tenant Model
- **Hierarchical Structure**:
  - **Organization**: Top-level tenant entity (e.g., "Acme Manufacturing Ltd")
  - **Sites**: Physical manufacturing locations within organization (e.g., "Factory A", "Warehouse B")
  - **Devices**: Equipment and sensors at each site (machines, meters, sensors)
  - **Users**: Assigned to organization with site-level access control
- **Multi-Tenancy Isolation**:
  - Database-enforced Row-Level Security (RLS) or partition-based isolation
  - All queries automatically filtered by tenant_id/organization_id
  - No application-layer filtering required (security enforced at data layer)
  - Tenant isolation validated through penetration testing

#### NFR-13: Role-Based Access Control (RBAC)
Four-tier role model with hierarchical permissions:

| Role | Scope | Permissions | Use Case |
|------|-------|-------------|----------|
| **Org Admin** | All sites in organization | Full access: manage users, sites, devices, billing, view all data | Company IT manager |
| **Site Admin** | Assigned sites only | Manage devices and users for their sites, configure dashboards, set alerts | Factory manager |
| **Operator** | Assigned sites only | View dashboards, acknowledge alerts, generate reports (no configuration) | Production supervisor |
| **Read-Only** | Assigned sites only | View dashboards and reports only (no alert ACK or config) | External auditor, contractor |

**Permission Matrix**:
- User management: Org Admin, Site Admin (for their sites)
- Device onboarding: Org Admin, Site Admin
- Dashboard configuration: Org Admin, Site Admin
- Alert configuration: Org Admin, Site Admin
- View data: All roles
- Acknowledge alerts: Operator, Site Admin, Org Admin
- Billing & subscription: Org Admin only

#### NFR-14: IP Allow-Listing (Optional)
Enterprise customers may require IP-based access control:
- **Configuration**: Per-organization IP CIDR ranges (e.g., "10.0.0.0/8", "203.0.113.0/24")
- **Enforcement**:
  - API Gateway resource policy for API calls
  - Cognito pre-authentication trigger for login requests
- **Bypass**: MFA can override IP restrictions for emergency access (configurable)
- **Audit**: All IP-based access denials logged to security audit trail

#### NFR-15: Dashboard Embedding Strategy
Requirements for embedding dashboards in customer portal:

| Dashboard Solution | Embedding Method | Cost Model | Authentication Flow |
|--------------------|------------------|------------|---------------------|
| **QuickSight** (Options A/B) | QuickSight embedding SDK | $0.30 per 30-minute session | Cognito JWT → QuickSight session token |
| **Custom React** (Option C) | Direct REST API calls | Included in development cost | Cognito JWT → REST API bearer token |
| **Grafana** (Option D) | Iframe embedding | Free (included in Pro tier) | Cognito JWT → Grafana API token |

**Embedding Requirements**:
- Single Sign-On (SSO): Users should not re-authenticate for embedded dashboards
- White-labeling: Customer logo, colors, domain (e.g., "customer1.smdh.io")
- Tenant isolation: Embedded dashboards automatically filtered to user's organization
- Responsive design: Support desktop, tablet, mobile viewports
- Security: Content Security Policy (CSP), iframe sandboxing, CORS configuration

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
- Alert latency: Based on alert criticality (see FR-11 for validation notes)
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

## 9. How We'll Know It's Working

### 9.1 User Metrics

| What We're Measuring | Target | How We Measure |
|--------|--------|-------------------|
| Registration completion | Over 90% | Track from sign-up to first dashboard |
| Time to first dashboard | Under 1 hour | From registration to viewing data |
| User satisfaction | Over 4.0/5.0 | Quarterly surveys |
| How often dashboards are used | Over 3 times/week per user | Usage tracking |
| Feature use | Over 60% | Track which features get used |
| Support tickets | Under 1 per company per month | Support system |

### 9.2 Technical Metrics

| What We're Measuring | Target | How We Measure |
|--------|--------|-------------------|
| System uptime | Over 99.9% | CloudWatch monitoring |
| Data ingestion success | Over 99.95% | Pipeline metrics |
| Dashboard load time | Under 2 seconds (95% of loads) | Real user monitoring |
| API errors | Under 0.1% | CloudWatch metrics |
| Data quality | Over 95% | Automated checks |
| Alert accuracy | Over 90% | False alarm tracking |

### 9.3 Business Metrics

| What We're Measuring | Target | How We Measure |
|--------|--------|-------------------|
| New companies | 30 companies (Year 1) | CRM tracking |
| Companies staying | Over 90% yearly | Churn tracking |
| Cost efficiency | Infrastructure costs grow with usage, not faster | Cost monitoring |
| Growth rate | 30% year-on-year | Business analytics |
| Net Promoter Score | Over 50 | Quarterly surveys |

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

## 12. Requirements Validation Checklist

**⚠️ IMPORTANT**: The following requirements need stakeholder validation before finalizing the architecture:

### 12.1 Alert Latency Requirements

**Current State**: Generic requirement for fast alerting without use-case differentiation

**Questions for Manufacturing Operators:**
1. What is the actual response time when you receive an alert? (Immediate? 5 minutes? 15 minutes?)
2. Have you experienced systems with <10-second alerting? What was the operational benefit?
3. Which alerts are truly time-critical vs. informational?
4. Are there regulatory requirements for specific alert latencies?

**Recommended Approach**:
- Categorize alerts by criticality (Critical Safety / Operational / Informational)
- Define appropriate latency SLAs for each category
- Validate with actual manufacturing floor workflows

### 12.2 Cost Model Validation

**Current State**: Infrastructure costs based on consumption patterns (2.6M-3.9M rows/day, 30 tenants)

**Questions for Business Stakeholders:**
1. What is the acceptable cost structure for the business model?
2. What are customer expectations around pricing?
3. What is the competitive pricing landscape?
4. Should pricing be tiered by data volume, features, or flat-rate?

**Recommended Approach**:
- Research competitor pricing models
- Conduct customer willingness-to-pay interviews
- Calculate cost-plus-margin based on actual consumption
- Define clear cost drivers that customers can understand and control

### 12.3 Timeline Validation

**Current State**: Timeline to be determined based on architecture selection

**Questions for Product/Business:**
1. Is there a specific market window or competitive pressure?
2. What are the opportunity costs of delayed launch?
3. Is there pre-sold or committed revenue requiring specific delivery dates?
4. What is the minimum viable feature set for initial launch?

**Recommended Approach**:
- Define MVP scope (absolutely essential features only)
- Calculate opportunity cost of different launch dates
- Consider phased rollout (limited beta → general availability)

### 12.4 Real-Time Monitoring Requirements

**Current State**: Requirements updated to be use-case appropriate

**Questions for End Users:**
1. How frequently do you check manufacturing dashboards? (Every minute? Every hour?)
2. What decisions do you make based on real-time data vs. historical trends?
3. Which metrics need real-time visibility vs. daily/weekly reports?

**Recommended Approach**:
- Map dashboard use cases to actual usage patterns
- Define refresh rates based on decision-making frequency
- Avoid over-engineering for theoretical requirements

### 12.5 Validation Timeline

| Activity | Owner | Deadline | Status |
|----------|-------|----------|--------|
| Alert latency requirements validation | Product Owner + Ops | TBD | ⏳ Not Started |
| Cost model and pricing research | Business Development | TBD | ⏳ Not Started |
| Timeline and MVP scope definition | Product Owner | TBD | ⏳ Not Started |
| Real-time monitoring use case mapping | UX Research | TBD | ⏳ Not Started |
| Requirements document final approval | All Stakeholders | TBD | ⏳ Not Started |

---

## 13. Appendices

### Appendix A: Glossary

> **Note**: See Section 12 for requirements validation checklist

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

## Appendix E: Version 0.2 Change Summary

### Overview
Version 0.2 incorporates feedback from comprehensive architectural review to ensure requirements align with infrastructure design options and operational realities.

### Key Changes in v0.2 (November 2, 2025)

#### 1. Split Latency Requirements (Section 3.1)
**Rationale**: Single "<1 second dashboard update" requirement was over-specified and driving architecture complexity/cost.

| Requirement Type | Previous | Updated (v0.2) | Impact |
|------------------|----------|----------------|--------|
| Safety/Critical Alerts | <10 seconds (implied) | ≤5-10 seconds (explicit) | ✅ Clarified criticality |
| Operational Alerts | <10 seconds | ≤60 seconds acceptable | ✅ Realistic operational need |
| Operator Dashboards | <1 second | ≤60 seconds acceptable | ✅ Allows simpler architecture (Option B) |

**Architecture Impact**: Allows Option B (Snowflake) with Lambda fast-path, saving $179K-$199K annually vs Option A (Flink).

#### 2. Enhanced Security Requirements (Section 5.2, NFR-7)
**Added**:
- 7-year audit log retention (GDPR/SOC 2 compliance)
- S3 Object Lock WORM mode for tamper-proof logs
- 72-hour breach notification SLA
- Data Subject Rights (GDPR) processing procedures
- Automated DSR handling via API

**Rationale**: Architectural review identified need for explicit security control documentation.

#### 3. Enhanced Operational Requirements (Section 5.3, NFR-9)
**Added**:
- **Golden Signals**: Specific SLOs for ingest lag, write errors, alert latency, dashboard freshness, query latency, availability
- **Error Budget Tracking**: 99.9% = 43 minutes downtime/month budget
- **RPO/RTO Targets**: RPO ≤5 min, RTO ≤30 min (explicit recovery objectives)
- **Replay & Backfill**: Idempotent event processing with structured event IDs
- **Schema Evolution**: Backward compatibility and migration strategies
- **Tenant Off-Boarding**: Secure data lifecycle procedures

**Rationale**: Operations and disaster recovery procedures must be defined upfront, not retrofitted.

#### 4. New Portal Authentication & Authorization Section (Section 5.5, NFR-11-15)
**Added Entire Section**:
- **NFR-11**: Authentication (Cognito, OIDC, MFA requirements)
- **NFR-12**: Organization & tenant model (hierarchical structure)
- **NFR-13**: RBAC with 4-tier role model (Org Admin, Site Admin, Operator, Read-Only)
- **NFR-14**: IP allow-listing for enterprise customers
- **NFR-15**: Dashboard embedding strategy per architecture option

**Rationale**: Architectural review identified missing portal authentication assumptions that impact infrastructure design.

#### 5. Clarified Data Volume Specifications (Section 3.1)
**Updated**:
- "2.6M-3.9M rows/day" → "2.6M-3.9M rows/day **per tenant**"
- Added platform-wide scaling context (30-100 tenants)

**Rationale**: Ambiguity in data volume scope was causing capacity planning disputes.

#### 6. Multi-Tenancy Isolation Requirements (Section 5.5, NFR-12)
**Added Explicit Requirement**:
- Database-enforced RLS or partition-based isolation (not application-layer filtering)
- Tenant isolation validated through penetration testing

**Rationale**: Differentiates secure native isolation (Options A/B/D) from risky app-enforced filtering (Option C).

### Requirements Validation Status

| Requirement Area | Validation Status | Owner | Target Date |
|------------------|-------------------|-------|-------------|
| ✅ Latency SLAs (split alerts/dashboards) | Documented in v0.2 | Architecture Team | Complete |
| ✅ Security controls (audit, GDPR, DSR) | Documented in v0.2 | Security Team | Complete |
| ✅ Operations (RPO/RTO, off-boarding) | Documented in v0.2 | Operations Team | Complete |
| ✅ Portal AuthN/AuthZ assumptions | Documented in v0.2 | Product Team | Complete |
| ⏳ Operator validation of alert latency | Field interviews needed | Product Owner | Nov 15, 2025 |
| ⏳ Cost model validation | Customer willingness-to-pay research | Business Dev | Nov 30, 2025 |
| ⏳ Timeline validation | MVP scope definition | Product Owner | Nov 15, 2025 |

### Cross-Reference to Architecture Document
This requirements document v0.2 aligns with **SMDH Infrastructure Design Options v0.2** (November 2, 2025), which provides detailed architecture evaluation based on these updated requirements.

**Key Alignment Points**:
- Split latency requirements enable Option B (Snowflake) + Lambda fast-path
- Security controls documented match architecture Security Control Matrix (Section 9)
- Ops requirements align with Operations & DR section (Section 8)
- Portal assumptions match Portal Assumptions section (Section 10)

---

## Document Approval

| Role | Name | Signature | Date |
|------|------|-----------|------|
| Product Owner | | | |
| Technical Architect | | | |
| Security Lead | | | |
| Compliance Officer | | | |

---

**Document Version**: 0.2 (Architectural Review Update)
**Last Updated**: November 2, 2025
**Next Review**: December 2025 (post-architecture selection)
**Status**: Under Review - Pending Architecture Decision

---

*This document represents the complete system requirements for the Smart Manufacturing Data Hub platform and serves as the authoritative source for all development, testing, and deployment activities. Version 0.2 incorporates architectural review feedback to ensure requirements are evidence-based, operationally realistic, and aligned with infrastructure design options.*
