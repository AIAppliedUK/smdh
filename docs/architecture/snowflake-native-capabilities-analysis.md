# SMDH Platform: Snowflake Native Capabilities Analysis

## Document Information
- **Version**: 1.0
- **Date**: November 13, 2025
- **Author**: Architecture Team
- **Status**: Technical Analysis
- **Purpose**: Evaluate what SMDH components can be fully implemented using native Snowflake capabilities vs. requiring external AWS services

---

## Executive Summary

This document provides a comprehensive analysis of Snowflake's native capabilities for implementing the SMDH platform, organized by platform component. For each capability, we identify:
- ✅ What IS possible natively in Snowflake
- ❌ What REQUIRES external AWS services
- 💰 Cost implications (Snowflake compute credits)
- ⚡ Performance characteristics
- ⚠️ Limitations and workarounds

### Key Findings Summary

| Component | Snowflake Native | External AWS Required | Recommendation |
|-----------|------------------|----------------------|----------------|
| **Customer Portal** | Streamlit in Snowflake (SiS) ✅ | None for basic; React for advanced | **Use SiS for MVP, React for production** |
| **Authentication** | Native auth + Snowflake RBAC ✅ | Cognito for external IdP | **Hybrid: Cognito + Snowflake RBAC** |
| **Data Processing** | Snowpark + Streams + Tasks ✅ | None required | **Pure Snowflake** |
| **Real-time Ingestion** | Snowpipe Streaming ⚠️ | IoT Core + Kinesis required | **Hybrid: AWS ingestion → Snowflake** |
| **Alerting** | Snowflake Alerts + Tasks ⚠️ | SNS/EventBridge for external delivery | **Hybrid: Snowflake detection → AWS delivery** |
| **Dashboards** | Snowsight + SiS ✅ | QuickSight/Grafana for advanced | **Snowflake for operational, BI tools for executive** |
| **APIs** | External Functions ⚠️ | API Gateway + Lambda required | **Hybrid: API Gateway → Snowflake** |

**Overall Assessment**: A **Snowflake-Native Architecture** (80% Snowflake, 20% AWS) is viable and offers significant operational advantages, but requires AWS for:
1. IoT device connectivity (IoT Core)
2. External notification delivery (SNS)
3. Public API layer (API Gateway)
4. Custom web portal (ECS/Fargate)

---

## 1. Streamlit in Snowflake (SiS) for Customer Portal

### What IS Possible Natively

#### Core Capabilities ✅
- **Framework**: Python-based web framework running entirely in Snowflake
- **Deployment**: One-click deployment from Snowsight or via SQL commands
- **Data Access**: Direct access to Snowflake tables without authentication/connection logic
- **Hosting**: Fully managed by Snowflake (no infrastructure to manage)
- **Auto-scaling**: Automatic scaling based on user demand
- **Security**: Inherits Snowflake's authentication and authorization

#### Features for SMDH Portal
```python
# Example: Basic SMDH Portal in Streamlit in Snowflake
import streamlit as st
import snowflake.snowpark as snowpark

# Automatic authentication - user context available
user = st.experimental_user  # Built-in user info
tenant_id = st.session_state.tenant_id  # Set from Snowflake session

# Dashboard selection
dashboard_type = st.selectbox(
    "Select Dashboard",
    ["Machine Utilization", "Air Quality", "Job Tracking"]
)

# Query data directly from Snowflake (no connection needed)
if dashboard_type == "Machine Utilization":
    session = snowpark.context.get_active_session()
    df = session.sql(f"""
        SELECT
            machine_id,
            AVG(utilization) as avg_utilization,
            SUM(energy_kwh) as total_energy
        FROM machine_utilization_hourly
        WHERE tenant_id = '{tenant_id}'
          AND hour >= DATEADD('day', -7, CURRENT_TIMESTAMP())
        GROUP BY machine_id
    """).to_pandas()

    # Visualizations
    st.line_chart(df, x='machine_id', y='avg_utilization')
    st.bar_chart(df, x='machine_id', y='total_energy')

# Alerting configuration
st.subheader("Alert Configuration")
threshold = st.slider("CO2 Threshold (ppm)", 400, 5000, 1000)
if st.button("Save Alert Rule"):
    session.sql(f"""
        CREATE OR REPLACE ALERT co2_alert_{tenant_id}
        WAREHOUSE = alert_wh
        SCHEDULE = '1 MINUTE'
        IF (EXISTS (
            SELECT 1 FROM air_quality_current
            WHERE tenant_id = '{tenant_id}'
              AND co2_level > {threshold}
        ))
        THEN CALL send_alert_notification('{tenant_id}', 'CO2 High');
    """)
    st.success("Alert rule saved!")
```

#### Supported Features for SMDH
✅ **User Authentication**: Inherits Snowflake authentication
✅ **Data Visualization**: Built-in charting (line, bar, area, scatter)
✅ **Interactive Widgets**: Sliders, dropdowns, date pickers, buttons
✅ **Tables and DataFrames**: Display and filter tabular data
✅ **Forms and Inputs**: Create device registration forms
✅ **File Uploads**: Support CSV/Excel uploads for bulk device import
✅ **Multi-page Apps**: Navigate between different dashboard views
✅ **Session State**: Maintain user preferences and selections
✅ **Caching**: Cache query results for performance (@st.cache_data)
✅ **Custom Styling**: Basic theming and CSS customization
✅ **Responsive Layout**: Columns and containers for layout control

#### What CAN Be Built in SiS
1. **Dashboard Viewer**: All operational dashboards (machine utilization, air quality, job tracking)
2. **Alert Configuration**: Set thresholds, create rules, view alert history
3. **Device Registration**: Forms to register devices and sites
4. **Report Generation**: Create and download custom reports
5. **User Settings**: Manage preferences, notification settings
6. **Data Uploads**: Bulk upload historical data or device configurations

### What REQUIRES External Services ❌

#### Limitations vs Custom React Portal

| Feature | SiS Capability | React Portal Capability | Impact |
|---------|----------------|------------------------|--------|
| **Authentication** | Snowflake users only | External IdP (Azure AD, Okta) | ⚠️ High - Companies want SSO |
| **Mobile App** | Web only (responsive) | Native iOS/Android apps | ⚠️ Medium - Mobile web may suffice |
| **Real-time Updates** | Polling (10s minimum) | WebSockets (<1s updates) | ⚠️ Medium - 10s is acceptable for SMDH |
| **Custom UI/UX** | Limited components | Fully customizable | ⚠️ Low - SiS components sufficient |
| **Advanced Interactions** | Limited JavaScript | Full React ecosystem | ⚠️ Low - SiS interactions sufficient |
| **Branding** | Basic theming | Full white-labeling | ⚠️ Medium - SiS theming may suffice |
| **Offline Mode** | None | PWA with offline support | ⚠️ Low - Manufacturing always online |
| **External APIs** | Via Snowflake External Functions | Direct API calls | ⚠️ Low - Can use External Functions |
| **Complex Animations** | None | Full animation libraries | ⚠️ Very Low - Not needed for SMDH |
| **Custom Payment** | None | Stripe/payment integration | ⚠️ Medium - May need external billing |

#### Critical Gaps

**1. Multi-Tenancy Self-Service Onboarding** ❌
- **Problem**: SiS cannot create Snowflake users programmatically
- **Impact**: Companies cannot self-register via SiS portal
- **Workaround**: Use React portal with Cognito for registration → Snowflake for data access
- **Required AWS**: Cognito, API Gateway, Lambda

**2. External Identity Providers (Azure AD, Okta)** ⚠️
- **Problem**: SiS only supports Snowflake authentication
- **Snowflake Native**: Snowflake supports SAML SSO (Azure AD, Okta) but must be configured at account level
- **Impact**: Cannot have per-tenant IdP configuration in SiS
- **Workaround**: Use React portal → Cognito (with IdP federation) → Snowflake token exchange
- **Required AWS**: Cognito with SAML federation

**3. Real-time Notifications (Push Notifications, SMS)** ❌
- **Problem**: SiS cannot send external notifications
- **Impact**: Cannot push alerts to mobile devices or send SMS
- **Workaround**: Snowflake Alerts → External Functions → SNS → Push/SMS
- **Required AWS**: SNS, EventBridge, Lambda (for notification routing)

**4. Custom Payment/Billing Integration** ❌
- **Problem**: No built-in payment processing
- **Impact**: Cannot handle subscription billing in SiS
- **Workaround**: Use React portal for billing → Stripe/payment gateway
- **Required AWS**: API Gateway, Lambda (payment webhook handling)

### Multi-Tenancy Support in SiS

#### Native Capabilities ✅
```sql
-- Set tenant context at login via Snowflake session parameter
ALTER SESSION SET tenant_id = 'ACME-MANUFACTURING';

-- All subsequent queries automatically filtered
-- Row Access Policies enforce tenant isolation
SELECT * FROM sensor_readings_raw;
-- Automatically filtered to current tenant
```

#### Implementation Pattern
```python
# In Streamlit app
import streamlit as st

# Get user's tenant from Snowflake context
session = snowpark.context.get_active_session()
current_user = session.sql("SELECT CURRENT_USER()").collect()[0][0]

# Map user to tenant (via lookup table)
tenant_info = session.table("user_tenant_mapping").filter(
    col("snowflake_user") == current_user
).collect()[0]

tenant_id = tenant_info['TENANT_ID']
tenant_name = tenant_info['TENANT_NAME']

# Set tenant context for session
session.sql(f"ALTER SESSION SET tenant_id = '{tenant_id}'").collect()

# All queries now automatically filtered by Row Access Policy
st.title(f"SMDH Portal - {tenant_name}")

# Display tenant-specific data (automatically filtered)
df = session.table("machine_utilization_hourly").to_pandas()
st.dataframe(df)  # Only shows current tenant's data
```

#### Limitations ⚠️
- **Self-Service Registration**: Cannot create new Snowflake users from SiS
- **User Invitation**: Cannot send invitation emails from SiS
- **Tenant Provisioning**: Cannot create new tenant schemas/objects from SiS
- **Solution**: Use React portal for onboarding → SiS for operational dashboards

### Dashboard Embedding Capabilities

#### Native Embedding ⚠️
- **Problem**: SiS apps can be shared but not embedded as iframes
- **Capability**: Can share app URL with Snowflake users
- **Limitation**: Cannot embed in external websites or portals
- **Impact**: Cannot white-label dashboards for customer websites

#### Workaround Options
1. **Snowsight Dashboards**: Can embed via Snowflake Data Collaboration
2. **React Portal**: Embed QuickSight or PowerBI dashboards
3. **Hybrid**: SiS for internal ops, QuickSight for customer-facing

### Mobile Responsiveness

#### Native Support ✅
```python
# SiS is responsive by default
import streamlit as st

# Layout adapts to screen size
col1, col2, col3 = st.columns(3)  # 3 columns on desktop, stacked on mobile
with col1:
    st.metric("Machines Online", "24/30")
with col2:
    st.metric("Avg Utilization", "78%")
with col3:
    st.metric("Energy Today", "245 kWh")

# Responsive chart
st.line_chart(data)  # Automatically resizes
```

#### Limitations ⚠️
- **No Native Apps**: Web only (no iOS/Android native apps)
- **Limited Mobile Gestures**: No swipe, pinch-to-zoom
- **Mobile Performance**: Slower than native apps
- **Solution**: Progressive Web App (PWA) wrapper if native apps needed

### Authentication and Authorization in SiS

#### Native Authentication ✅
```python
import streamlit as st

# Automatic authentication
user = st.experimental_user
st.write(f"Logged in as: {user.email}")

# Role-based access
if user.role in ['ADMIN_ROLE', 'SITE_ADMIN_ROLE']:
    st.button("Register Device")
else:
    st.info("You don't have permission to register devices")

# Snowflake RBAC automatically enforces permissions
session = snowpark.context.get_active_session()
# This query will fail if user doesn't have SELECT permission
df = session.table("sensor_readings_raw").to_pandas()
```

#### Supported Auth Methods
✅ **Username/Password**: Snowflake native users
✅ **MFA**: Snowflake supports Duo Security MFA
✅ **SSO (SAML)**: Azure AD, Okta, ADFS (account-level configuration)
✅ **OAuth**: Snowflake OAuth for API access
❌ **Per-Tenant IdP**: Cannot configure different IdP per tenant
❌ **Social Login**: No Google/Facebook/Twitter login
❌ **Custom Auth**: Cannot implement custom auth logic

### Performance Characteristics

#### Compute Costs 💰
```
Streamlit in Snowflake Compute Usage:
- Small Warehouse (2 credits/hour): 5-10 concurrent users
- Medium Warehouse (4 credits/hour): 10-25 concurrent users
- Large Warehouse (8 credits/hour): 25-50 concurrent users

SMDH Estimate (20-40 concurrent users):
- Medium Warehouse: $12/hour × 8 business hours × 22 days = $2,112/month
- Auto-suspend (5 min): Reduces cost by ~30% = ~$1,480/month

With Multi-Cluster (auto-scale 1-3 clusters):
- Peak: 3 × Medium = $36/hour (only during peak usage)
- Average: 1.5 × Medium = $18/hour average
- Monthly: $18/hour × 8h × 22 days = $3,168/month
```

#### Response Time ⚡
| Operation | SiS Performance | React + API Performance | Winner |
|-----------|----------------|-------------------------|--------|
| **Dashboard Load** | 1-3 seconds | 500ms - 1.5 seconds | React |
| **Query Execution** | 200ms - 2 seconds | Same (both query Snowflake) | Tie |
| **Chart Rendering** | 500ms - 1 second | 100ms - 500ms | React |
| **Data Refresh** | 10 seconds (minimum polling) | Real-time (WebSockets) | React |
| **File Upload** | 1-5 seconds | 1-3 seconds | Tie |

### Limitations Summary

| Limitation | Severity | Impact on SMDH | Workaround |
|-----------|----------|----------------|------------|
| **No self-service user registration** | 🔴 Critical | Cannot onboard companies | React portal for onboarding |
| **No external IdP per tenant** | 🟠 High | No Azure AD/Okta SSO per company | Cognito with IdP federation |
| **No push notifications/SMS** | 🟠 High | Cannot send mobile alerts | External Functions → SNS |
| **No payment integration** | 🟠 High | Cannot handle billing | React portal for billing |
| **No native mobile apps** | 🟡 Medium | Web only | PWA or responsive web |
| **No dashboard embedding** | 🟡 Medium | Cannot white-label | Use QuickSight for embedding |
| **Limited real-time updates** | 🟡 Medium | 10s refresh minimum | Acceptable for SMDH use cases |
| **Limited UI customization** | 🟢 Low | Basic theming only | Sufficient for operational portal |

### Recommendation: Hybrid Approach

**Architecture Pattern: "React Shell + Streamlit Core"**

```
┌─────────────────────────────────────────────────────────┐
│ React Portal (ECS Fargate)                              │
│  ┌──────────────────────────────────────────────────┐   │
│  │ Public Website & Marketing                       │   │
│  │ - Company registration (Cognito)                 │   │
│  │ - User management & invitations                  │   │
│  │ - Payment/billing (Stripe)                       │   │
│  │ - SSO configuration (Azure AD/Okta)              │   │
│  └──────────────────────────────────────────────────┘   │
│                          ↓                               │
│  ┌──────────────────────────────────────────────────┐   │
│  │ Authenticated Route: Embed Streamlit in iframe   │   │
│  │ - Pass Snowflake token to SiS app                │   │
│  │ - Display operational dashboards                 │   │
│  └──────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│ Streamlit in Snowflake                                  │
│  - Machine Utilization Dashboards                       │
│  - Air Quality Monitoring                               │
│  - Job Tracking Analytics                               │
│  - Alert Configuration                                  │
│  - Report Generation                                    │
│  - Device Management (view/update)                      │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│ Snowflake Data Platform                                 │
│  - All data storage and processing                      │
│  - RBAC and Row-Level Security                          │
└─────────────────────────────────────────────────────────┘
```

**Benefits**:
- ✅ Best of both worlds: React for onboarding, SiS for analytics
- ✅ Reduced development time: SiS for dashboards (80% of portal)
- ✅ Operational simplicity: Less custom code to maintain
- ✅ Security: Snowflake RBAC + RLS for data access
- ✅ Cost: Lower than full custom React portal

**Trade-offs**:
- ⚠️ Requires iframe embedding (some UX limitations)
- ⚠️ Two authentication flows (Cognito → Snowflake token)
- ⚠️ Cannot fully white-label (Snowflake branding in SiS)

---

## 2. Snowflake IAM and Security

### Native Authentication Capabilities ✅

#### Username/Password Authentication
```sql
-- Create user with password policy
CREATE USER manufacturing_operator
    PASSWORD = 'SecureP@ssw0rd123!'
    DEFAULT_ROLE = 'OPERATOR_ROLE'
    DEFAULT_WAREHOUSE = 'analytics_wh'
    MUST_CHANGE_PASSWORD = TRUE
    DAYS_TO_EXPIRY = 90;

-- Set account-level password policy
ALTER ACCOUNT SET
    MIN_PASSWORD_LENGTH = 12
    PASSWORD_MAX_AGE_DAYS = 90
    PASSWORD_MIN_AGE_DAYS = 0
    PASSWORD_MAX_RETRIES = 3
    PASSWORD_LOCKOUT_TIME_MINS = 15;
```

**Capabilities**:
✅ Password complexity requirements
✅ Password expiration policies
✅ Failed login lockout
✅ Password history (prevent reuse)
✅ Session timeout configuration
❌ Custom password validation logic
❌ Self-service password reset (requires support ticket)

#### Multi-Factor Authentication (MFA)

**Snowflake Native MFA** ✅
```sql
-- Enforce MFA for specific role
ALTER USER manufacturing_operator SET
    MINS_TO_UNLOCK = 15
    MINS_TO_BYPASS_MFA = 0;  -- Always require MFA

-- Configure MFA enrollment grace period
ALTER ACCOUNT SET
    ALLOW_CLIENT_MFA_CACHING = FALSE;
```

**MFA Methods Supported**:
✅ **Duo Security**: Snowflake's native MFA provider
  - Push notifications
  - SMS
  - Phone call
  - Hardware token
✅ **Time-based OTP (TOTP)**: Authenticator apps
❌ **SMS-only**: Not supported natively
❌ **Email OTP**: Not supported
❌ **Biometric**: Not supported

**Limitations** ⚠️
- **Single MFA Provider**: Duo Security only (no custom providers)
- **No Per-Tenant MFA**: Same MFA policy for all users
- **No Conditional MFA**: Cannot require MFA based on conditions (location, device)
- **Workaround**: Use Cognito for flexible MFA → Snowflake token exchange

#### Single Sign-On (SSO) via SAML 2.0

**Native SAML Support** ✅
```sql
-- Configure SAML integration (account-level)
ALTER ACCOUNT SET
    SAML_IDENTITY_PROVIDER = '{
        "certificate": "-----BEGIN CERTIFICATE-----...",
        "ssoUrl": "https://login.microsoftonline.com/.../saml2",
        "type": "Custom",
        "label": "Azure AD"
    }'
    SAML_ALLOW_UNSOLICITED_SSO = TRUE;

-- Map SAML assertion to Snowflake role
CREATE OR REPLACE SECURITY INTEGRATION saml_azure_ad
    TYPE = SAML2
    ENABLED = TRUE
    SAML2_ISSUER = 'https://sts.windows.net/...'
    SAML2_SSO_URL = 'https://login.microsoftonline.com/.../saml2'
    SAML2_PROVIDER = 'CUSTOM'
    SAML2_X509_CERT = '-----BEGIN CERTIFICATE-----...'
    SAML2_SP_INITIATED_LOGIN_PAGE_LABEL = 'AzureAD'
    SAML2_ENABLE_SP_INITIATED = TRUE
    SAML2_SNOWFLAKE_X509_CERT = ''
    SAML2_SIGN_REQUEST = TRUE
    SAML2_REQUESTED_NAMEID_FORMAT = 'urn:oasis:names:tc:SAML:1.1:nameid-format:emailAddress'
    SAML2_POST_LOGOUT_REDIRECT_URL = 'https://yourcompany.com/logout';
```

**Supported Identity Providers**:
✅ Azure Active Directory
✅ Okta
✅ ADFS
✅ OneLogin
✅ PingFederate
✅ Any SAML 2.0 compliant IdP

**Capabilities**:
✅ SP-initiated SSO (user clicks "Login with Azure AD")
✅ IdP-initiated SSO (user logs in from Azure AD portal)
✅ Role mapping from SAML assertions
✅ Multi-IdP support (different IdPs for different users)
✅ Session timeout configuration
✅ Certificate rotation
❌ **Per-Tenant IdP Configuration**: Cannot have different IdP per tenant
❌ **Dynamic IdP Registration**: IdP must be configured by Snowflake admin
❌ **Social Login**: No Google/Facebook/Twitter

**Multi-Tenant SSO Challenge** 🔴
```
Problem: SMDH has 30 tenants, each may want their own Azure AD/Okta
Snowflake Limitation: SAML integrations are account-level (not tenant-specific)

Solution Options:
1. **Single IdP Proxy** (Recommended):
   - Use Cognito as SSO proxy
   - Cognito federates with each tenant's IdP
   - Cognito → Snowflake SAML (single integration)
   - Cost: $0.0055/MAU (beyond free tier of 50,000 MAU)

2. **Multiple Snowflake Accounts**:
   - Separate Snowflake account per tenant
   - Each account has own SAML integration
   - Cost: Prohibitive ($25/month minimum per account)
   - Not recommended for 30 tenants

3. **Manual SAML Management**:
   - Snowflake admin configures SAML for each tenant
   - Requires support ticket for each tenant
   - Not self-service
   - Not scalable
```

**Recommended Architecture for Multi-Tenant SSO**:
```
Tenant A (Azure AD) ──┐
Tenant B (Okta)      ─┤
Tenant C (Azure AD)  ─┼──► AWS Cognito ───► Snowflake (SAML)
Tenant D (Google)    ─┤         ↓
Tenant E (Okta)      ─┘    (Token Exchange)
                                ↓
                          User gets Snowflake
                          session with tenant_id
```

### Role-Based Access Control (RBAC) ✅

#### Snowflake RBAC Model

**Comprehensive RBAC** ✅
```sql
-- Role hierarchy for SMDH
CREATE ROLE company_admin_role;
CREATE ROLE site_admin_role;
CREATE ROLE operator_role;
CREATE ROLE viewer_role;

-- Grant hierarchy (roles can inherit from other roles)
GRANT ROLE viewer_role TO ROLE operator_role;
GRANT ROLE operator_role TO ROLE site_admin_role;
GRANT ROLE site_admin_role TO ROLE company_admin_role;

-- Grant database access
GRANT USAGE ON DATABASE smdh_data TO ROLE viewer_role;
GRANT USAGE ON SCHEMA smdh_data.sensor_data TO ROLE viewer_role;

-- Grant table access with specific privileges
GRANT SELECT ON TABLE sensor_readings_raw TO ROLE viewer_role;
GRANT SELECT, INSERT, UPDATE ON TABLE sensor_readings_raw TO ROLE operator_role;
GRANT ALL PRIVILEGES ON TABLE sensor_readings_raw TO ROLE site_admin_role;

-- Grant warehouse access
GRANT USAGE ON WAREHOUSE analytics_wh TO ROLE viewer_role;
GRANT OPERATE ON WAREHOUSE analytics_wh TO ROLE site_admin_role;

-- Assign role to user
GRANT ROLE operator_role TO USER manufacturing_operator;

-- Set default role (user assumes this role at login)
ALTER USER manufacturing_operator SET DEFAULT_ROLE = operator_role;
```

**RBAC Capabilities**:
✅ **Role Hierarchy**: Roles can inherit from other roles
✅ **Granular Permissions**: Database, schema, table, view, column-level
✅ **Warehouse Access Control**: Who can use which warehouses
✅ **Function/Procedure Permissions**: Control execution rights
✅ **Future Grants**: Auto-grant permissions to new objects
✅ **Role Switching**: Users can switch between granted roles
✅ **Audit Logging**: All permission changes logged
❌ **Dynamic Roles**: Cannot create roles programmatically via SQL
❌ **Custom RBAC Logic**: Cannot implement custom authorization logic

#### SMDH Role Mapping

| SMDH Role | Snowflake Role | Permissions | Example |
|-----------|----------------|-------------|---------|
| **Company Admin** | `company_admin_{tenant_id}` | All privileges on tenant objects, user management | ALTER TABLE, CREATE ALERT, GRANT ROLE |
| **Site Admin** | `site_admin_{tenant_id}_{site_id}` | Read/write data for site, configure dashboards | SELECT, INSERT, UPDATE on site tables |
| **Operator** | `operator_{tenant_id}` | Read tenant data, create reports, acknowledge alerts | SELECT, CALL stored procedures |
| **Viewer** | `viewer_{tenant_id}` | Read-only access to dashboards and reports | SELECT only |

**Role Creation Pattern**:
```sql
-- Create roles for new tenant
CREATE ROLE company_admin_acme;
CREATE ROLE site_admin_acme_london;
CREATE ROLE operator_acme;
CREATE ROLE viewer_acme;

-- Grant access to tenant-specific objects
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA smdh_data.sensor_data
    TO ROLE company_admin_acme;

-- Apply Row Access Policy for tenant isolation
ALTER TABLE sensor_readings_raw
    ADD ROW ACCESS POLICY tenant_isolation ON (tenant_id);
```

### Row-Level Security (RLS) for Multi-Tenancy ✅

#### Native Row Access Policies

**Complete Tenant Isolation** ✅
```sql
-- Create Row Access Policy for tenant isolation
CREATE OR REPLACE ROW ACCESS POLICY tenant_isolation AS
    (tenant_id VARCHAR) RETURNS BOOLEAN ->
    CASE
        -- System admin can see all data
        WHEN CURRENT_ROLE() IN ('ACCOUNTADMIN', 'SYSADMIN') THEN TRUE

        -- Company admins can see their tenant's data
        WHEN CURRENT_ROLE() LIKE 'company_admin_%'
             AND tenant_id = REPLACE(CURRENT_ROLE(), 'company_admin_', '') THEN TRUE

        -- Site admins can see their tenant's data
        WHEN CURRENT_ROLE() LIKE 'site_admin_%'
             AND tenant_id = SPLIT_PART(CURRENT_ROLE(), '_', 3) THEN TRUE

        -- Operators and viewers use session parameter
        WHEN tenant_id = CURRENT_SESSION_PARAMETER('tenant_id') THEN TRUE

        -- Deny all other access
        ELSE FALSE
    END;

-- Apply policy to all multi-tenant tables
ALTER TABLE sensor_readings_raw
    ADD ROW ACCESS POLICY tenant_isolation ON (tenant_id);

ALTER TABLE sensor_readings_normalized
    ADD ROW ACCESS POLICY tenant_isolation ON (tenant_id);

ALTER TABLE machine_utilization_hourly
    ADD ROW ACCESS POLICY tenant_isolation ON (tenant_id);

ALTER TABLE air_quality_current
    ADD ROW ACCESS POLICY tenant_isolation ON (tenant_id);

ALTER TABLE job_tracking
    ADD ROW ACCESS POLICY tenant_isolation ON (tenant_id);

-- Now all queries automatically filter by tenant
-- User cannot bypass this policy
```

**How It Works**:
```sql
-- User logs in, gets assigned tenant context
ALTER SESSION SET tenant_id = 'ACME-MANUFACTURING';

-- Query appears to select all data
SELECT * FROM sensor_readings_raw;

-- But Snowflake automatically adds filter:
-- WHERE tenant_id = 'ACME-MANUFACTURING'

-- Result: User only sees their tenant's data
-- Cannot be bypassed (policy enforced at query execution)
```

**RLS Capabilities**:
✅ **Automatic Filtering**: No application-side filtering needed
✅ **Cannot Be Bypassed**: Even ACCOUNTADMIN sees policy
✅ **Multiple Policies**: Different policies for different columns
✅ **Dynamic Logic**: Use session parameters, current role, user attributes
✅ **Performance**: Uses partition pruning (no performance penalty)
✅ **Audit**: Policy changes logged
❌ **Complex Logic**: Limited to SQL expressions (no stored procedures)
❌ **External Data**: Cannot call external APIs for authorization

**Performance Characteristics** ⚡
```
Query Performance with RLS:
- No overhead if tenant_id is clustering key
- Partition pruning eliminates unrelated data
- Query: SELECT * FROM sensor_readings_raw (1 billion rows)
  - Without RLS: Scans all 1B rows
  - With RLS + Clustering: Scans only tenant's rows (~33M for 30 tenants)
  - Speedup: 30x faster, 30x less data scanned
```

### Integration with External IdPs

#### Native Integrations ✅
```sql
-- Azure Active Directory (via SAML)
CREATE SECURITY INTEGRATION azure_ad_sso
    TYPE = SAML2
    ENABLED = TRUE
    SAML2_ISSUER = 'https://sts.windows.net/{tenant-id}/'
    SAML2_SSO_URL = 'https://login.microsoftonline.com/{tenant-id}/saml2'
    SAML2_PROVIDER = 'CUSTOM'
    SAML2_X509_CERT = '-----BEGIN CERTIFICATE-----...';

-- Okta (via SAML)
CREATE SECURITY INTEGRATION okta_sso
    TYPE = SAML2
    ENABLED = TRUE
    SAML2_ISSUER = 'http://www.okta.com/{okta-org-id}'
    SAML2_SSO_URL = 'https://{okta-org}.okta.com/app/{app-id}/sso/saml'
    SAML2_PROVIDER = 'OKTA';

-- OAuth (for API access)
CREATE SECURITY INTEGRATION oauth_integration
    TYPE = OAUTH
    ENABLED = TRUE
    OAUTH_CLIENT = CUSTOM
    OAUTH_CLIENT_TYPE = 'PUBLIC'
    OAUTH_REDIRECT_URI = 'https://yourapp.com/oauth/callback'
    OAUTH_ISSUE_REFRESH_TOKENS = TRUE
    OAUTH_REFRESH_TOKEN_VALIDITY = 7776000;  -- 90 days
```

**Supported External IdPs**:
✅ Azure Active Directory (SAML, OAuth)
✅ Okta (SAML, OAuth)
✅ ADFS (SAML)
✅ Google Workspace (OAuth)
✅ Any SAML 2.0 compliant IdP
❌ Social Logins (Facebook, Twitter) - not directly supported

**OAuth for API Authentication** ✅
```python
# Python example: OAuth token for API access
import requests
from snowflake.connector import connect

# Step 1: Get OAuth token from Snowflake
auth_url = "https://{account}.snowflakecomputing.com/oauth/token-request"
response = requests.post(auth_url, data={
    "grant_type": "client_credentials",
    "client_id": "your_client_id",
    "client_secret": "your_client_secret"
})
token = response.json()["access_token"]

# Step 2: Use token to connect
conn = connect(
    account="{account}",
    authenticator="oauth",
    token=token,
    database="smdh_data",
    schema="sensor_data"
)

# Step 3: Execute queries
cursor = conn.cursor()
cursor.execute("SELECT * FROM sensor_readings_raw LIMIT 10")
```

**API Authentication Methods**:
✅ **OAuth 2.0**: For web apps, mobile apps, APIs
✅ **JWT Tokens**: For service-to-service authentication
✅ **Key Pair Authentication**: For serverless functions (Lambda)
❌ **API Keys**: Not directly supported (use OAuth instead)

### Session Management

#### Native Session Controls ✅
```sql
-- Configure session timeout
ALTER ACCOUNT SET
    CLIENT_SESSION_KEEP_ALIVE = TRUE
    CLIENT_SESSION_KEEP_ALIVE_HEARTBEAT_FREQUENCY = 3600;  -- 1 hour

-- Set session parameters at login
ALTER SESSION SET
    tenant_id = 'ACME-MANUFACTURING'
    TIMEZONE = 'Europe/London'
    DATE_INPUT_FORMAT = 'YYYY-MM-DD'
    TIME_INPUT_FORMAT = 'HH24:MI:SS';

-- Audit active sessions
SELECT
    session_id,
    user_name,
    client_application_id,
    login_time,
    current_role(),
    current_warehouse()
FROM TABLE(INFORMATION_SCHEMA.SESSIONS());

-- Force logout (by admin)
CALL SYSTEM$CANCEL_ALL_QUERIES('user_name');
```

**Session Capabilities**:
✅ Session timeout configuration
✅ Keep-alive heartbeat
✅ Session parameter inheritance
✅ Multi-statement transactions
✅ Query result caching (24 hours)
✅ Session context preservation
❌ Custom session storage
❌ Distributed session management
❌ Session replication across regions

### API Authentication (OAuth, JWT)

#### OAuth 2.0 Implementation ✅
```sql
-- Create OAuth integration for API clients
CREATE SECURITY INTEGRATION api_oauth_integration
    TYPE = OAUTH
    ENABLED = TRUE
    OAUTH_CLIENT = CUSTOM
    OAUTH_CLIENT_TYPE = 'CONFIDENTIAL'
    OAUTH_REDIRECT_URI = 'https://api.smdh.com/oauth/callback'
    OAUTH_ISSUE_REFRESH_TOKENS = TRUE
    OAUTH_REFRESH_TOKEN_VALIDITY = 7776000  -- 90 days
    BLOCKED_ROLES_LIST = ('ACCOUNTADMIN');

-- Grant OAuth integration to role
GRANT USAGE ON INTEGRATION api_oauth_integration TO ROLE api_role;
```

**OAuth Flow for SMDH API**:
```
1. Client Request Token:
   POST https://{account}.snowflakecomputing.com/oauth/token-request
   {
     "grant_type": "client_credentials",
     "client_id": "{client_id}",
     "client_secret": "{client_secret}"
   }

2. Snowflake Issues Token:
   {
     "access_token": "ver:1-hint:123...",
     "token_type": "Bearer",
     "expires_in": 3600
   }

3. Client Uses Token:
   Authorization: Bearer {access_token}
   Query Snowflake via REST API or SQL API
```

#### JWT Authentication ✅
```sql
-- Generate key pair for JWT authentication
-- (Done externally, public key stored in Snowflake)

-- Register public key with user
ALTER USER api_service_account SET
    RSA_PUBLIC_KEY = '-----BEGIN PUBLIC KEY-----...';

-- User generates JWT with private key, signs with RS256
-- Snowflake validates JWT using stored public key
```

**JWT Authentication Flow**:
```python
import jwt
import time
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.backends import default_backend

# Load private key
with open('private_key.pem', 'rb') as key_file:
    private_key = serialization.load_pem_private_key(
        key_file.read(),
        password=None,
        backend=default_backend()
    )

# Generate JWT token
account = "your_account"
user = "api_service_account"
qualified_username = f"{account}.{user}".upper()

payload = {
    "iss": f"{qualified_username}.SHA256:{public_key_fp}",
    "sub": qualified_username,
    "iat": int(time.time()),
    "exp": int(time.time()) + 3600  # 1 hour expiration
}

token = jwt.encode(payload, private_key, algorithm='RS256')

# Use token to connect
conn = connect(
    account=account,
    user=user,
    authenticator="SNOWFLAKE_JWT",
    private_key=private_key
)
```

**API Authentication Comparison**:

| Method | Use Case | Pros | Cons |
|--------|----------|------|------|
| **OAuth 2.0** | Web/mobile apps, third-party integrations | Standard protocol, refresh tokens | Requires token endpoint |
| **JWT** | Service-to-service, serverless functions | No token endpoint needed, stateless | Key management complexity |
| **Key Pair** | Automated scripts, ETL pipelines | Simple, no interactive login | Keys must be rotated |
| **SAML** | Web SSO, enterprise users | Centralized IdP, MFA | Cannot use for API calls |

### Security Cost Analysis 💰

#### Compute Costs for Authentication/Authorization
```
Authentication Operations (per month):
- User logins: 20-40 users × 22 days × 3 logins/day = 1,320 - 2,640 logins
- OAuth token requests: ~500 API calls/day × 30 days = 15,000 tokens
- JWT authentications: ~1,000/day × 30 days = 30,000 authentications

Snowflake Compute:
- Authentication: No compute cost (control plane operation)
- RLS Policy Evaluation: Included in query execution (no separate charge)
- Session Management: No additional cost

Total Auth/AuthZ Cost: $0/month (included in account)
```

#### External Service Costs (if using AWS Cognito)
```
AWS Cognito Pricing:
- MAU (Monthly Active Users): First 50,000 free, then $0.0055/MAU
- SMDH: 20-40 active users = FREE
- SAML Federation: First 50 users free, then $0.015/MAU = $0
- MFA: $0.05 per authentication = ~$7/month (40 users × 3.5 logins/week)

Total Cognito Cost (if using): ~$7/month
```

**Recommendation**: Use native Snowflake authentication unless per-tenant IdP required

---

## 3. Data Processing and Transformation

### Snowpark (Python/Java/Scala in Snowflake) ✅

#### Native Capabilities

**Snowpark for Python** ✅
```python
from snowflake.snowpark import Session
from snowflake.snowpark.functions import col, avg, sum, window
from snowflake.snowpark.types import StructType, StructField, StringType, FloatType

# Create session (automatically authenticated in Snowflake context)
session = Session.builder.configs(connection_parameters).create()

# DataFrame API (similar to Pandas/Spark)
sensor_df = session.table("sensor_readings_raw")

# Transformations (lazy evaluation)
processed_df = sensor_df.filter(col("tenant_id") == "ACME") \
    .filter(col("quality_score") > 0.7) \
    .group_by("sensor_id", "hour") \
    .agg(
        avg("metric_value").alias("avg_value"),
        sum("energy_kwh").alias("total_energy")
    )

# Write to table
processed_df.write.mode("overwrite").save_as_table("machine_metrics_hourly")

# User-Defined Function (UDF)
from snowflake.snowpark.functions import udf

@udf(name="calculate_oee", return_type=FloatType(), input_types=[FloatType(), FloatType(), FloatType()])
def calculate_oee(availability: float, performance: float, quality: float) -> float:
    """Calculate Overall Equipment Effectiveness"""
    return availability * performance * quality

# Use UDF in query
result_df = session.table("machine_data").select(
    col("machine_id"),
    calculate_oee(col("availability"), col("performance"), col("quality")).alias("oee")
)
```

**Snowpark Capabilities**:
✅ **DataFrame API**: Familiar Pandas-like interface
✅ **Lazy Evaluation**: Optimized query plans
✅ **UDFs**: Python/Java/Scala functions
✅ **Vectorized UDFs**: Process batches for performance
✅ **Stored Procedures**: Complex logic with control flow
✅ **Native Types**: Supports all Snowflake data types
✅ **Third-party Libraries**: Use Python packages (scikit-learn, pandas, numpy)
✅ **Distributed Execution**: Automatically parallelized
❌ **Streaming**: Batch only (no true streaming)
❌ **State Management**: No persistent state between calls

**SMDH Use Case: Data Validation**
```python
# Snowpark stored procedure for data quality checks
from snowflake.snowpark import Session
from snowflake.snowpark.functions import col, when, current_timestamp

def validate_sensor_data(session: Session, batch_size: int = 10000) -> str:
    """
    Validate sensor data quality and flag issues
    """
    # Read raw sensor data
    raw_df = session.table("sensor_readings_raw") \
        .filter(col("processed") == False) \
        .limit(batch_size)

    # Apply validation rules
    validated_df = raw_df.with_column(
        "validation_status",
        when(col("timestamp").is_null(), "MISSING_TIMESTAMP")
        .when(col("metric_value") < 0, "NEGATIVE_VALUE")
        .when(col("metric_value").is_null(), "MISSING_VALUE")
        .otherwise("VALID")
    ).with_column(
        "quality_score",
        when(col("validation_status") == "VALID", 1.0)
        .when(col("validation_status") == "MISSING_VALUE", 0.5)
        .otherwise(0.0)
    ).with_column(
        "validated_at",
        current_timestamp()
    )

    # Write to validated table
    validated_df.write.mode("append").save_as_table("sensor_readings_validated")

    # Update raw table
    session.sql(f"""
        UPDATE sensor_readings_raw
        SET processed = TRUE
        WHERE message_id IN (
            SELECT message_id FROM sensor_readings_validated
            WHERE validated_at > DATEADD('minute', -5, CURRENT_TIMESTAMP())
        )
    """).collect()

    return f"Validated {validated_df.count()} records"

# Register as stored procedure
session.sproc.register(
    func=validate_sensor_data,
    name="validate_sensor_data",
    packages=["snowflake-snowpark-python"],
    is_permanent=True,
    stage_location="@udf_stage",
    replace=True
)
```

### Streams and Tasks for Real-time Processing ✅

#### Snowflake Streams (Change Data Capture)

**Native CDC Capabilities** ✅
```sql
-- Create stream to track new sensor readings
CREATE OR REPLACE STREAM sensor_readings_stream
ON TABLE sensor_readings_raw
APPEND_ONLY = TRUE;  -- Only capture INSERTs (not UPDATEs/DELETEs)

-- Stream captures all changes
-- Query stream to see pending changes
SELECT
    METADATA$ACTION as action_type,  -- INSERT, UPDATE, or DELETE
    METADATA$ISUPDATE as is_update,  -- TRUE if part of UPDATE
    METADATA$ROW_ID as row_id,
    *
FROM sensor_readings_stream;

-- Consume stream (process changes)
-- After reading, stream is automatically advanced
```

**Stream Types**:
✅ **Standard Stream**: Captures INSERTs, UPDATEs, DELETEs
✅ **Append-Only Stream**: Captures INSERTs only (better performance)
✅ **Insert-Only Stream**: Captures INSERTs only (alias for append-only)

**Stream Use Cases in SMDH**:
1. **Real-time Aggregation**: Calculate hourly machine utilization as new data arrives
2. **Data Quality**: Validate new records before making available
3. **Alert Detection**: Check new air quality readings for threshold breaches
4. **Deduplication**: Identify and remove duplicate sensor readings
5. **Transformation Pipeline**: Normalize raw JSON into structured tables

**Stream Example: Machine Utilization**
```sql
-- Create stream on raw sensor data
CREATE OR REPLACE STREAM machine_sensor_stream
ON TABLE sensor_readings_raw
APPEND_ONLY = TRUE;

-- Process stream: Calculate utilization
CREATE OR REPLACE TASK process_machine_utilization
    WAREHOUSE = etl_wh
    SCHEDULE = '1 MINUTE'
    WHEN SYSTEM$STREAM_HAS_DATA('machine_sensor_stream')
AS
INSERT INTO machine_utilization_hourly (
    tenant_id,
    machine_id,
    hour,
    avg_utilization,
    total_energy,
    cycle_count,
    reading_count
)
SELECT
    tenant_id,
    sensor_id as machine_id,
    DATE_TRUNC('hour', timestamp) as hour,
    AVG(CASE WHEN metric_key = 'utilization' THEN metric_value::FLOAT END) as avg_utilization,
    SUM(CASE WHEN metric_key = 'energy_kwh' THEN metric_value::FLOAT END) as total_energy,
    MAX(CASE WHEN metric_key = 'cycle_count' THEN metric_value::INTEGER END) as cycle_count,
    COUNT(*) as reading_count
FROM machine_sensor_stream
WHERE sensor_type = 'MACHINE'
GROUP BY 1, 2, 3;

-- Resume task (start processing)
ALTER TASK process_machine_utilization RESUME;
```

#### Snowflake Tasks (Orchestration)

**Native Task Scheduling** ✅
```sql
-- Cron-based task (every 5 minutes)
CREATE OR REPLACE TASK cleanup_old_alerts
    WAREHOUSE = maintenance_wh
    SCHEDULE = 'USING CRON 0,5,10,15,20,25,30,35,40,45,50,55 * * * * UTC'
AS
DELETE FROM alert_history
WHERE created_at < DATEADD('day', -90, CURRENT_TIMESTAMP());

-- Stream-triggered task (runs when stream has data)
CREATE OR REPLACE TASK detect_air_quality_alerts
    WAREHOUSE = alert_wh
    WHEN SYSTEM$STREAM_HAS_DATA('air_quality_stream')
AS
CALL check_air_quality_thresholds();

-- Task DAG (dependent tasks)
CREATE OR REPLACE TASK root_task
    WAREHOUSE = etl_wh
    SCHEDULE = '5 MINUTE'
AS
CALL validate_new_data();

CREATE OR REPLACE TASK child_task_1
    WAREHOUSE = etl_wh
    AFTER root_task
AS
CALL aggregate_hourly_metrics();

CREATE OR REPLACE TASK child_task_2
    WAREHOUSE = etl_wh
    AFTER root_task
AS
CALL update_dashboard_cache();

CREATE OR REPLACE TASK grandchild_task
    WAREHOUSE = alert_wh
    AFTER child_task_1, child_task_2  -- Waits for both parents
AS
CALL generate_daily_reports();

-- Resume entire DAG (must resume in reverse order)
ALTER TASK grandchild_task RESUME;
ALTER TASK child_task_2 RESUME;
ALTER TASK child_task_1 RESUME;
ALTER TASK root_task RESUME;
```

**Task Capabilities**:
✅ **Cron Scheduling**: Flexible cron expressions
✅ **Event-Driven**: Trigger on stream data availability
✅ **DAG Support**: Build complex task dependencies
✅ **SQL or Procedures**: Execute SQL or stored procedures
✅ **Warehouse Assignment**: Dedicated compute for tasks
✅ **Auto-Suspend**: Warehouse suspends after task completes
✅ **Error Handling**: Automatic retry on transient errors
✅ **Audit Logging**: Task execution history
❌ **Parallel Execution**: No parallel branches in DAG
❌ **Conditional Logic**: Limited IF/ELSE (use stored procedures)
❌ **External Triggers**: Cannot trigger from external events (use Snowpipe Streaming)

**Task Use Cases in SMDH**:
```sql
-- 1. Hourly aggregation pipeline
CREATE TASK aggregate_hourly_metrics
    WAREHOUSE = etl_wh
    SCHEDULE = 'USING CRON 0 * * * * UTC'  -- Top of every hour
AS
CALL refresh_hourly_aggregations();

-- 2. Alert detection (every minute)
CREATE TASK check_critical_alerts
    WAREHOUSE = alert_wh
    SCHEDULE = '1 MINUTE'
AS
INSERT INTO alert_queue (tenant_id, alert_type, severity, message)
SELECT
    tenant_id,
    'AIR_QUALITY' as alert_type,
    CASE
        WHEN co2_level > 5000 THEN 'CRITICAL'
        WHEN co2_level > 1000 THEN 'WARNING'
    END as severity,
    'CO2 level: ' || co2_level || ' ppm' as message
FROM air_quality_current
WHERE co2_level > 1000
  AND NOT EXISTS (
      SELECT 1 FROM alert_history
      WHERE alert_history.tenant_id = air_quality_current.tenant_id
        AND alert_history.location_id = air_quality_current.location_id
        AND alert_history.created_at > DATEADD('hour', -1, CURRENT_TIMESTAMP())
  );

-- 3. Data quality checks (stream-driven)
CREATE TASK validate_new_sensor_data
    WAREHOUSE = etl_wh
    WHEN SYSTEM$STREAM_HAS_DATA('sensor_readings_stream')
AS
CALL validate_sensor_data(10000);

-- 4. Daily reporting (scheduled)
CREATE TASK generate_daily_reports
    WAREHOUSE = report_wh
    SCHEDULE = 'USING CRON 0 6 * * * Europe/London'  -- 6 AM UK time
AS
CALL generate_tenant_daily_reports();
```

### User-Defined Functions (UDFs) for Business Logic ✅

#### SQL UDFs

**Inline SQL Functions** ✅
```sql
-- Calculate Overall Equipment Effectiveness (OEE)
CREATE OR REPLACE FUNCTION calculate_oee(
    availability FLOAT,
    performance FLOAT,
    quality FLOAT
)
RETURNS FLOAT
LANGUAGE SQL
AS
$$
    availability * performance * quality
$$;

-- Usage
SELECT
    machine_id,
    calculate_oee(availability, performance, quality) as oee
FROM machine_metrics;

-- Calculate Air Quality Index (AQI)
CREATE OR REPLACE FUNCTION calculate_aqi(
    pm25 FLOAT,  -- PM2.5 in μg/m³
    co2 FLOAT,   -- CO2 in ppm
    voc FLOAT    -- VOC in ppb
)
RETURNS STRING
LANGUAGE SQL
AS
$$
    CASE
        WHEN pm25 > 150 OR co2 > 5000 OR voc > 660 THEN 'Poor'
        WHEN pm25 > 55 OR co2 > 1000 OR voc > 220 THEN 'Moderate'
        WHEN pm25 > 35 OR co2 > 800 OR voc > 120 THEN 'Fair'
        ELSE 'Good'
    END
$$;

-- Time-series windowing
CREATE OR REPLACE FUNCTION calculate_rolling_average(
    metric_value FLOAT,
    window_size INT,
    partition_col STRING,
    order_col TIMESTAMP
)
RETURNS FLOAT
LANGUAGE SQL
AS
$$
    AVG(metric_value) OVER (
        PARTITION BY partition_col
        ORDER BY order_col
        ROWS BETWEEN window_size PRECEDING AND CURRENT ROW
    )
$$;
```

#### Python UDFs

**Scalar Python UDFs** ✅
```python
# Register Python UDF
from snowflake.snowpark import Session
from snowflake.snowpark.types import FloatType, StringType, IntegerType

@udf(name="detect_anomaly", return_type=FloatType(),
     input_types=[FloatType(), FloatType(), FloatType()])
def detect_anomaly(value: float, mean: float, std_dev: float) -> float:
    """
    Calculate anomaly score using standard deviation
    Returns: Z-score (number of standard deviations from mean)
    """
    if std_dev == 0:
        return 0.0
    return abs((value - mean) / std_dev)

# Vectorized UDF (batch processing)
from snowflake.snowpark.functions import pandas_udf
import pandas as pd
import numpy as np

@pandas_udf(name="detect_batch_anomalies",
            return_type=FloatType(),
            input_types=[FloatType()])
def detect_batch_anomalies(values: pd.Series) -> pd.Series:
    """
    Detect anomalies in batch using IQR method
    Returns: Anomaly score (0 = normal, >0 = anomaly)
    """
    Q1 = values.quantile(0.25)
    Q3 = values.quantile(0.75)
    IQR = Q3 - Q1

    lower_bound = Q1 - 1.5 * IQR
    upper_bound = Q3 + 1.5 * IQR

    anomaly_scores = pd.Series(0.0, index=values.index)
    anomaly_scores[values < lower_bound] = (lower_bound - values[values < lower_bound]) / IQR
    anomaly_scores[values > upper_bound] = (values[values > upper_bound] - upper_bound) / IQR

    return anomaly_scores

# Complex business logic UDF
@udf(name="calculate_production_efficiency",
     return_type=FloatType(),
     input_types=[IntegerType(), IntegerType(), IntegerType(), IntegerType()])
def calculate_production_efficiency(
    actual_output: int,
    target_output: int,
    downtime_minutes: int,
    available_minutes: int
) -> float:
    """
    Calculate production efficiency considering downtime
    """
    if available_minutes == 0:
        return 0.0

    # Adjust target for downtime
    uptime_minutes = available_minutes - downtime_minutes
    adjusted_target = (target_output * uptime_minutes) / available_minutes

    if adjusted_target == 0:
        return 0.0

    # Calculate efficiency
    efficiency = (actual_output / adjusted_target) * 100

    # Cap at 100% (over-performance not counted)
    return min(efficiency, 100.0)
```

#### Table Functions (UDTFs)

**Generate Multiple Rows** ✅
```python
from snowflake.snowpark.functions import udtf
from snowflake.snowpark.types import StructType, StructField, StringType, IntegerType, FloatType

@udtf(name="generate_production_schedule",
      output_schema=StructType([
          StructField("time_slot", StringType()),
          StructField("machine_id", StringType()),
          StructField("expected_output", IntegerType()),
          StructField("priority", IntegerType())
      ]),
      input_types=[StringType(), IntegerType(), IntegerType()])
class GenerateProductionSchedule:
    """
    Generate hourly production schedule for machines
    """
    def process(self, date: str, num_machines: int, shift_hours: int):
        for hour in range(shift_hours):
            for machine in range(1, num_machines + 1):
                time_slot = f"{date} {hour:02d}:00:00"
                machine_id = f"MACHINE-{machine:03d}"
                expected_output = 100 + (hour * 10)  # Ramp up during shift
                priority = 1 if hour < 4 else 2  # High priority first 4 hours

                yield (time_slot, machine_id, expected_output, priority)

# Usage
SELECT * FROM TABLE(generate_production_schedule('2025-01-15', 10, 8));
```

**UDF Capabilities**:
✅ **SQL UDFs**: Inline functions, recursive, SQL expressions
✅ **Python UDFs**: Full Python language support
✅ **Java UDFs**: JVM-based functions
✅ **Scala UDFs**: Functional programming
✅ **Vectorized UDFs**: Batch processing for performance
✅ **Table Functions**: Generate multiple rows
✅ **Third-party Libraries**: Use Python packages
✅ **Secure UDFs**: Cannot access external resources
❌ **External API Calls**: Use External Functions instead
❌ **File I/O**: Cannot read/write local files
❌ **Network Access**: Cannot make HTTP requests

### Stored Procedures for Orchestration ✅

#### SQL Stored Procedures

**Complex Control Flow** ✅
```sql
-- Stored procedure with error handling
CREATE OR REPLACE PROCEDURE refresh_hourly_aggregations()
RETURNS STRING
LANGUAGE SQL
AS
$$
DECLARE
    rows_processed INT DEFAULT 0;
    error_message STRING DEFAULT '';
BEGIN
    -- Step 1: Validate data quality
    LET quality_check INT := (
        SELECT COUNT(*)
        FROM sensor_readings_raw
        WHERE quality_score < 0.5
          AND timestamp > DATEADD('hour', -1, CURRENT_TIMESTAMP())
    );

    IF (quality_check > 100) THEN
        error_message := 'Data quality check failed: ' || quality_check || ' low-quality records';
        RETURN error_message;
    END IF;

    -- Step 2: Aggregate machine utilization
    INSERT INTO machine_utilization_hourly
    SELECT
        tenant_id,
        machine_id,
        DATE_TRUNC('hour', timestamp) as hour,
        AVG(utilization) as avg_utilization,
        SUM(energy_kwh) as total_energy,
        COUNT(*) as reading_count
    FROM sensor_readings_raw
    WHERE timestamp > DATEADD('hour', -1, CURRENT_TIMESTAMP())
      AND sensor_type = 'MACHINE'
    GROUP BY 1, 2, 3;

    rows_processed := SQLROWCOUNT;

    -- Step 3: Aggregate air quality
    INSERT INTO air_quality_hourly
    SELECT
        tenant_id,
        location_id,
        DATE_TRUNC('hour', timestamp) as hour,
        AVG(co2_level) as avg_co2,
        AVG(voc_level) as avg_voc,
        AVG(pm25_level) as avg_pm25
    FROM sensor_readings_raw
    WHERE timestamp > DATEADD('hour', -1, CURRENT_TIMESTAMP())
      AND sensor_type = 'AIR_QUALITY'
    GROUP BY 1, 2, 3;

    rows_processed := rows_processed + SQLROWCOUNT;

    -- Step 4: Clean up old raw data
    DELETE FROM sensor_readings_raw
    WHERE timestamp < DATEADD('day', -90, CURRENT_TIMESTAMP());

    RETURN 'Successfully processed ' || rows_processed || ' rows';

EXCEPTION
    WHEN OTHER THEN
        error_message := 'Error: ' || SQLERRM;
        RETURN error_message;
END;
$$;

-- Call stored procedure
CALL refresh_hourly_aggregations();
```

#### Python Stored Procedures

**Complex Logic with External Libraries** ✅
```python
from snowflake.snowpark import Session
from snowflake.snowpark.functions import col, current_timestamp
import pandas as pd
import numpy as np
from sklearn.ensemble import IsolationForest
from datetime import datetime, timedelta

def detect_machine_anomalies(session: Session, lookback_days: int = 7) -> dict:
    """
    Detect anomalies in machine behavior using ML
    """
    # Read machine data
    machine_df = session.table("machine_utilization_hourly") \
        .filter(col("hour") > current_timestamp() - timedelta(days=lookback_days)) \
        .select("machine_id", "hour", "avg_utilization", "total_energy") \
        .to_pandas()

    if len(machine_df) < 100:
        return {"status": "insufficient_data", "anomalies": 0}

    # Prepare features
    features = machine_df[["avg_utilization", "total_energy"]].fillna(0)

    # Train Isolation Forest
    clf = IsolationForest(contamination=0.1, random_state=42)
    machine_df["anomaly_score"] = clf.fit_predict(features)
    machine_df["anomaly_probability"] = clf.score_samples(features)

    # Identify anomalies
    anomalies = machine_df[machine_df["anomaly_score"] == -1]

    # Write anomalies to table
    if len(anomalies) > 0:
        anomaly_snow_df = session.create_dataframe(anomalies)
        anomaly_snow_df.write.mode("append").save_as_table("machine_anomalies")

    return {
        "status": "success",
        "total_records": len(machine_df),
        "anomalies_detected": len(anomalies),
        "anomaly_rate": f"{(len(anomalies) / len(machine_df)) * 100:.2f}%"
    }

# Register as stored procedure
session.sproc.register(
    func=detect_machine_anomalies,
    name="detect_machine_anomalies",
    packages=["snowflake-snowpark-python", "pandas", "numpy", "scikit-learn"],
    is_permanent=True,
    stage_location="@ml_stage",
    replace=True
)

# Call from SQL
CALL detect_machine_anomalies(7);
```

**Stored Procedure Capabilities**:
✅ **SQL Procedures**: DECLARE, IF/ELSE, WHILE, FOR loops
✅ **Python Procedures**: Full Python ecosystem
✅ **Java Procedures**: JVM-based logic
✅ **Scala Procedures**: Functional programming
✅ **Exception Handling**: TRY/CATCH blocks
✅ **Transaction Control**: COMMIT/ROLLBACK
✅ **Dynamic SQL**: Build and execute SQL strings
✅ **Return Values**: Strings, numbers, tables
✅ **Third-party Libraries**: Use Python packages (scikit-learn, pandas)
❌ **External API Calls**: Use External Functions instead
❌ **File System Access**: No local file I/O

### Dynamic Tables for Materialized Views ✅

#### Native Continuous Aggregation

**Always-Fresh Materialized Views** ✅
```sql
-- Dynamic Table: Machine Utilization (updates every 1 minute)
CREATE OR REPLACE DYNAMIC TABLE machine_utilization_hourly
TARGET_LAG = '1 minute'
WAREHOUSE = streaming_wh
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
    COUNT(*) as reading_count,

    -- Metadata
    MAX(timestamp) as last_updated
FROM sensor_readings_normalized
WHERE sensor_type = 'MACHINE'
GROUP BY 1, 2, 3;

-- Dynamic Table: Air Quality Current (updates every 10 seconds)
CREATE OR REPLACE DYNAMIC TABLE air_quality_current
TARGET_LAG = '10 seconds'
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
  AND timestamp > DATEADD('minute', -5, CURRENT_TIMESTAMP())
GROUP BY 1, 2, 3;

-- Dynamic Table: Job Production Flow (updates every 5 minutes)
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
    MAX_BY(location, duration_seconds) as bottleneck_location,

    -- Count stops
    COUNT(DISTINCT location) as location_count
FROM job_tracking
WHERE scan_timestamp > DATEADD('day', -7, CURRENT_TIMESTAMP())
GROUP BY 1, 2, 3;
```

**Dynamic Table Capabilities**:
✅ **Automatic Refresh**: Updates based on TARGET_LAG
✅ **Incremental Refresh**: Only processes changed data
✅ **Dependency Tracking**: Refresh when source tables change
✅ **Clustered Storage**: Automatically optimized
✅ **Query Optimization**: Pre-aggregated for fast queries
✅ **Transparency**: Query like a regular table
✅ **Chaining**: Dynamic Table can reference another Dynamic Table
❌ **Complex Joins**: Limited join performance on very large tables
❌ **Streaming**: Not truly real-time (minimum TARGET_LAG = 1 minute)

**Dynamic Table vs Traditional Materialized View**:

| Feature | Dynamic Table | Traditional Materialized View |
|---------|--------------|------------------------------|
| **Refresh** | Automatic based on TARGET_LAG | Manual (REFRESH MATERIALIZED VIEW) |
| **Incremental** | Yes (only changed data) | No (full refresh) |
| **Query Syntax** | Standard SELECT | Standard SELECT |
| **Cost** | Warehouse compute + storage | Warehouse compute + storage |
| **Use Case** | Real-time dashboards | Periodic reports |

### Performance Characteristics ⚡

#### Compute Cost Analysis 💰

**Snowpark Processing Costs**
```
Scenario: Process 2.6M rows/day with Snowpark Python UDF

Warehouse: Medium (4 credits/hour)
Processing time: ~15 minutes for 2.6M rows
Daily cost: (15/60) × 4 credits × $3 = $3/day = $90/month

Optimization:
- Use vectorized UDFs: 5x faster = ~3 minutes = $18/month
- Use SQL UDFs where possible: 10x faster = ~1.5 minutes = $9/month
```

**Stream and Task Costs**
```
Scenario: 10 tasks running every 1 minute

Each task execution: 5 seconds average
Warehouse: Small (2 credits/hour)

Daily executions: 10 tasks × 60 executions/hour × 24 hours = 14,400 executions
Total execution time: 14,400 × 5 seconds = 72,000 seconds = 20 hours
Daily cost: 20 hours × 2 credits × $3 = $120/day = $3,600/month

Optimization:
- Use WHEN SYSTEM$STREAM_HAS_DATA: Only run when needed = ~10% executions = $360/month
- Consolidate tasks: Combine related tasks = ~5 tasks = $180/month
- Aggressive auto-suspend: Warehouse suspends after 60 seconds = ~50% reduction = $90/month
```

**Dynamic Table Costs**
```
Scenario: 5 Dynamic Tables with different refresh rates

Table 1 (TARGET_LAG = '10 seconds'): High-frequency refresh
Table 2-3 (TARGET_LAG = '1 minute'): Medium-frequency
Table 4-5 (TARGET_LAG = '5 minutes'): Low-frequency

Warehouse: Small (2 credits/hour) for all

Estimated refresh time per day:
- Table 1: 8,640 refreshes × 2 seconds = 17,280 seconds = 4.8 hours
- Table 2-3: 2,880 refreshes × 5 seconds = 14,400 seconds × 2 = 8 hours
- Table 4-5: 576 refreshes × 10 seconds = 5,760 seconds × 2 = 3.2 hours

Total: 16 hours/day × 2 credits × $3 = $96/day = $2,880/month

Optimization:
- Increase TARGET_LAG where possible (e.g., 1 min → 5 min): ~60% reduction = $1,150/month
- Use multi-cluster warehouse (auto-scale 1-3): Handle peak loads efficiently
- Cluster Dynamic Tables by tenant_id: Faster refreshes
```

**Total Data Processing Costs (Snowflake-Native)**
```
Component                  | Monthly Cost  | Notes
---------------------------|---------------|---------------------------
Snowpark Processing        | $9 - $90      | Depends on UDF complexity
Streams (CDC)              | $0            | No additional cost (part of table storage)
Tasks (Orchestration)      | $90 - $360    | Optimized with WHEN condition
Dynamic Tables             | $1,150 - $2,880 | Depends on refresh frequency
Stored Procedures          | $20 - $100    | Ad-hoc execution
---------------------------|---------------|---------------------------
Total                      | $1,269 - $3,430/month | For 2.6M rows/day, 30 tenants
```

**Cost Comparison: Snowflake vs AWS**

| Task | Snowflake (Native) | AWS (Lambda + Flink) | Savings |
|------|-------------------|---------------------|---------|
| **Data Transformation** | Snowpark UDF: $9-90/mo | Lambda: $150/mo + Flink: $300/mo = $450/mo | ✅ 80-98% less |
| **Stream Processing** | Streams: $0 | Kinesis: $200/mo + Flink: $300/mo = $500/mo | ✅ 100% less |
| **Orchestration** | Tasks: $90-360/mo | Step Functions: $50/mo + Lambda: $100/mo = $150/mo | ⚠️ Similar |
| **Materialized Views** | Dynamic Tables: $1,150-2,880/mo | Lambda + S3 + Glue: $400/mo | ❌ 3-7x more expensive |
| **Total** | **$1,269-3,430/mo** | **$1,500/mo** | ⚠️ Competitive but variable |

**Key Insight**: Snowflake native processing is cost-competitive with AWS for standard workloads, but Dynamic Tables can be expensive for high-frequency refreshes. Use TARGET_LAG wisely.

### Limitations and Workarounds ⚠️

#### Limitation 1: No True Streaming (Sub-Second Latency) ❌

**Problem**:
- Snowpipe Streaming: 5-10 second latency minimum
- Dynamic Tables: 1 minute TARGET_LAG minimum (cannot be lower)
- Tasks: 1 minute minimum schedule interval

**Impact on SMDH**:
- Cannot achieve <1 second dashboard updates
- Alert detection has 60-65 second minimum latency
- Real-time machine monitoring shows 1-minute delay

**Workaround Options**:

**Option 1: Add AWS Lambda for Critical Paths** (Hybrid)
```
IoT Core → Lambda (real-time alert detection) → SNS → Mobile Push
         ↓
       Snowpipe Streaming → Snowflake (analytics + history)
```
- Use Lambda for <10-second alerts
- Use Snowflake for analytics and dashboards
- Cost: +$100-200/month for Lambda

**Option 2: Accept 60-Second Latency** (Pure Snowflake)
- Validate with users if 60-second alerts are acceptable
- SMDH requirements specify <5 minute latency (✅ met)
- Most manufacturing alerts are not sub-10-second critical
- Cost: $0 (no additional services)

**Recommendation**: Option 2 for SMDH (requirements allow 5-minute latency)

#### Limitation 2: No External API Calls from UDFs/Procedures ❌

**Problem**:
- UDFs and stored procedures cannot make HTTP requests
- Cannot call external services (weather API, ERP system, payment gateway)
- Cannot send notifications directly (SMS, email, push)

**Workaround**: Use Snowflake External Functions
```sql
-- Create External Function that calls AWS Lambda
CREATE OR REPLACE EXTERNAL FUNCTION send_sms_notification(
    phone_number VARCHAR,
    message VARCHAR
)
RETURNS VARCHAR
API_INTEGRATION = aws_api_integration
AS 'https://api-gateway-url.com/send-sms';

-- Use in stored procedure
CREATE OR REPLACE PROCEDURE send_critical_alert(
    tenant_id VARCHAR,
    alert_message VARCHAR
)
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
DECLARE
    phone VARCHAR;
    result VARCHAR;
BEGIN
    -- Get tenant's phone number
    SELECT notification_phone INTO phone
    FROM tenant_config
    WHERE tenant_config.tenant_id = tenant_id;

    -- Call external function (Lambda via API Gateway)
    result := send_sms_notification(phone, alert_message);

    RETURN result;
END;
$$;
```

**Architecture**:
```
Snowflake Stored Procedure
    ↓
External Function (API Gateway)
    ↓
AWS Lambda
    ↓
SNS (send SMS)
```

**Cost**: API Gateway + Lambda = ~$50-100/month

#### Limitation 3: Limited Debugging and Error Handling ⚠️

**Problem**:
- Cannot set breakpoints in UDFs/stored procedures
- Limited logging (no console.log equivalent)
- Error messages sometimes cryptic

**Workaround**:
```sql
-- Logging pattern for stored procedures
CREATE OR REPLACE TABLE procedure_logs (
    log_id VARCHAR DEFAULT UUID_STRING(),
    procedure_name VARCHAR,
    log_level VARCHAR,  -- DEBUG, INFO, WARN, ERROR
    message VARCHAR,
    details VARIANT,
    logged_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
);

-- Use in stored procedure
CREATE OR REPLACE PROCEDURE complex_data_pipeline()
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
BEGIN
    -- Log start
    INSERT INTO procedure_logs (procedure_name, log_level, message)
    VALUES ('complex_data_pipeline', 'INFO', 'Pipeline started');

    -- Step 1
    BEGIN
        -- Complex logic here
        INSERT INTO procedure_logs (procedure_name, log_level, message)
        VALUES ('complex_data_pipeline', 'INFO', 'Step 1 completed');
    EXCEPTION
        WHEN OTHER THEN
            INSERT INTO procedure_logs (procedure_name, log_level, message, details)
            VALUES ('complex_data_pipeline', 'ERROR', 'Step 1 failed', OBJECT_CONSTRUCT('error', SQLERRM));
            RETURN 'Failed at Step 1';
    END;

    RETURN 'Success';
END;
$$;

-- Query logs
SELECT * FROM procedure_logs WHERE procedure_name = 'complex_data_pipeline' ORDER BY logged_at DESC;
```

#### Limitation 4: Dynamic Table Refresh Lag ⚠️

**Problem**:
- TARGET_LAG is a target, not a guarantee
- Actual lag can be higher under load
- Cannot control refresh order (no DAG)

**Workaround**:
```sql
-- Monitor actual lag
SELECT
    table_name,
    target_lag,
    scheduling_state,
    data_timestamp,
    refresh_end_time,
    DATEDIFF('second', data_timestamp, CURRENT_TIMESTAMP()) as actual_lag_seconds
FROM TABLE(INFORMATION_SCHEMA.DYNAMIC_TABLE_REFRESH_HISTORY())
WHERE table_name IN ('machine_utilization_hourly', 'air_quality_current')
ORDER BY refresh_end_time DESC;

-- If lag is consistently high, increase warehouse size
ALTER DYNAMIC TABLE machine_utilization_hourly SET WAREHOUSE = medium_wh;
```

---

## 4. Alerting and Notifications

### Snowflake Alerts (Threshold-Based) ✅

#### Native Alert Capabilities

**Threshold-Based Alerts** ✅
```sql
-- Alert: High CO2 levels
CREATE OR REPLACE ALERT co2_high_alert
    WAREHOUSE = alert_wh
    SCHEDULE = '1 MINUTE'
    IF (EXISTS (
        SELECT 1
        FROM air_quality_current
        WHERE co2_level > 1000
          AND timestamp > DATEADD('minute', -5, CURRENT_TIMESTAMP())
    ))
    THEN CALL send_co2_alert();

-- Resume alert (start monitoring)
ALTER ALERT co2_high_alert RESUME;

-- Alert with multi-level thresholds
CREATE OR REPLACE ALERT air_quality_multi_level
    WAREHOUSE = alert_wh
    SCHEDULE = '1 MINUTE'
    IF (EXISTS (
        SELECT
            tenant_id,
            location_id,
            co2_level,
            pm25_level,
            CASE
                WHEN co2_level > 5000 OR pm25_level > 150 THEN 'CRITICAL'
                WHEN co2_level > 1000 OR pm25_level > 55 THEN 'WARNING'
            END as severity
        FROM air_quality_current
        WHERE severity IS NOT NULL
    ))
    THEN CALL process_air_quality_alerts();

-- Alert: Machine offline
CREATE OR REPLACE ALERT machine_offline_alert
    WAREHOUSE = alert_wh
    SCHEDULE = '1 MINUTE'
    IF (EXISTS (
        SELECT 1
        FROM machine_utilization_hourly
        WHERE last_updated < DATEADD('minute', -15, CURRENT_TIMESTAMP())
    ))
    THEN CALL send_machine_offline_notification();

-- Alert: Energy consumption spike
CREATE OR REPLACE ALERT energy_spike_alert
    WAREHOUSE = alert_wh
    SCHEDULE = '5 MINUTE'
    IF (EXISTS (
        SELECT
            tenant_id,
            machine_id,
            total_energy,
            AVG(total_energy) OVER (
                PARTITION BY tenant_id, machine_id
                ORDER BY hour
                ROWS BETWEEN 24 PRECEDING AND 1 PRECEDING
            ) as avg_energy
        FROM machine_utilization_hourly
        WHERE total_energy > avg_energy * 1.2  -- 20% above average
    ))
    THEN CALL send_energy_spike_notification();
```

**Snowflake Alert Capabilities**:
✅ **SQL-Based Conditions**: Any SELECT query that returns rows
✅ **Scheduled Execution**: Minimum 1-minute interval
✅ **Stored Procedure Actions**: Call any stored procedure when triggered
✅ **Multi-Condition**: Use EXISTS, COUNT, complex WHERE clauses
✅ **Audit Logging**: Alert execution history
✅ **Suspend/Resume**: Enable/disable alerts programmatically
❌ **No Built-in Notification**: Cannot send email/SMS directly
❌ **No Escalation**: No built-in escalation logic
❌ **Minimum 1-Minute**: Cannot check more frequently than every minute
❌ **No Event-Driven**: Cannot trigger on data arrival (must poll)

**Alert Action Pattern** (Call Stored Procedure):
```sql
-- Stored procedure to handle alert
CREATE OR REPLACE PROCEDURE send_co2_alert()
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
DECLARE
    alert_count INT DEFAULT 0;
BEGIN
    -- Insert affected records into alert queue
    INSERT INTO alert_queue (
        tenant_id,
        location_id,
        alert_type,
        severity,
        metric_value,
        threshold,
        message,
        created_at
    )
    SELECT
        tenant_id,
        location_id,
        'CO2_HIGH' as alert_type,
        CASE
            WHEN co2_level > 5000 THEN 'CRITICAL'
            WHEN co2_level > 1000 THEN 'WARNING'
        END as severity,
        co2_level as metric_value,
        1000 as threshold,
        'CO2 level: ' || co2_level || ' ppm exceeds threshold' as message,
        CURRENT_TIMESTAMP() as created_at
    FROM air_quality_current
    WHERE co2_level > 1000
      AND timestamp > DATEADD('minute', -5, CURRENT_TIMESTAMP())
      -- Avoid duplicate alerts (check if already alerted in last hour)
      AND NOT EXISTS (
          SELECT 1 FROM alert_history
          WHERE alert_history.tenant_id = air_quality_current.tenant_id
            AND alert_history.location_id = air_quality_current.location_id
            AND alert_history.alert_type = 'CO2_HIGH'
            AND alert_history.created_at > DATEADD('hour', -1, CURRENT_TIMESTAMP())
      );

    alert_count := SQLROWCOUNT;

    -- If critical alerts exist, call External Function to send SMS
    IF (alert_count > 0) THEN
        CALL send_external_notifications('CO2_HIGH');
    END IF;

    RETURN 'Processed ' || alert_count || ' alerts';
END;
$$;
```

### External Functions to Call SNS/Email Services ✅

#### SNS Integration via External Functions

**Architecture**:
```
Snowflake Alert → Stored Procedure → External Function → API Gateway → Lambda → SNS → Email/SMS
```

**Setup External Function**:
```sql
-- Step 1: Create API Integration (one-time setup)
CREATE OR REPLACE API INTEGRATION aws_api_gateway_integration
    API_PROVIDER = AWS_API_GATEWAY
    API_AWS_ROLE_ARN = 'arn:aws:iam::123456789012:role/SnowflakeAPIRole'
    ENABLED = TRUE
    API_ALLOWED_PREFIXES = ('https://api-id.execute-api.eu-west-2.amazonaws.com/prod/');

-- Step 2: Create External Function for SNS
CREATE OR REPLACE EXTERNAL FUNCTION send_sns_notification(
    topic_arn VARCHAR,
    subject VARCHAR,
    message VARCHAR,
    phone_number VARCHAR
)
RETURNS VARCHAR
API_INTEGRATION = aws_api_gateway_integration
AS 'https://api-id.execute-api.eu-west-2.amazonaws.com/prod/send-notification';

-- Step 3: Create External Function for Email
CREATE OR REPLACE EXTERNAL FUNCTION send_email_notification(
    recipient_email VARCHAR,
    subject VARCHAR,
    body VARCHAR,
    html_body VARCHAR
)
RETURNS VARCHAR
API_INTEGRATION = aws_api_gateway_integration
AS 'https://api-id.execute-api.eu-west-2.amazonaws.com/prod/send-email';

-- Step 4: Use in Alert Stored Procedure
CREATE OR REPLACE PROCEDURE send_external_notifications(alert_type VARCHAR)
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
DECLARE
    result VARCHAR;
BEGIN
    -- Get all pending alerts
    FOR alert IN (
        SELECT
            tenant_id,
            location_id,
            severity,
            message
        FROM alert_queue
        WHERE sent = FALSE
          AND alert_type = alert_type
    ) DO
        -- Get tenant notification preferences
        LET tenant_config CURSOR FOR
            SELECT
                notification_email,
                notification_phone,
                notification_sns_topic
            FROM tenant_config
            WHERE tenant_config.tenant_id = alert.tenant_id;

        FOR config IN tenant_config DO
            -- Send email if configured
            IF (config.notification_email IS NOT NULL) THEN
                result := send_email_notification(
                    config.notification_email,
                    'SMDH Alert: ' || alert.severity,
                    alert.message,
                    '<html><body><h2>' || alert.severity || '</h2><p>' || alert.message || '</p></body></html>'
                );
            END IF;

            -- Send SMS if critical and phone configured
            IF (alert.severity = 'CRITICAL' AND config.notification_phone IS NOT NULL) THEN
                result := send_sns_notification(
                    config.notification_sns_topic,
                    'Critical Alert',
                    alert.message,
                    config.notification_phone
                );
            END IF;
        END FOR;

        -- Mark alert as sent
        UPDATE alert_queue
        SET sent = TRUE, sent_at = CURRENT_TIMESTAMP()
        WHERE tenant_id = alert.tenant_id
          AND location_id = alert.location_id
          AND alert_type = alert_type
          AND sent = FALSE;
    END FOR;

    RETURN 'Notifications sent';
END;
$$;
```

**AWS Lambda Function** (called by API Gateway):
```python
import boto3
import json

sns = boto3.client('sns')
ses = boto3.client('ses')

def lambda_handler(event, context):
    """
    Handle notification requests from Snowflake External Function
    """
    # Parse Snowflake request
    body = json.loads(event['body'])
    data = body['data']  # Array of rows from Snowflake

    results = []
    for row in data:
        row_num = row[0]
        topic_arn = row[1]
        subject = row[2]
        message = row[3]
        phone_number = row[4]

        try:
            # Send SNS notification
            if phone_number:
                sns.publish(
                    PhoneNumber=phone_number,
                    Message=message,
                    Subject=subject
                )
            else:
                sns.publish(
                    TopicArn=topic_arn,
                    Message=message,
                    Subject=subject
                )

            results.append([row_num, "SUCCESS"])
        except Exception as e:
            results.append([row_num, f"ERROR: {str(e)}"])

    # Return results to Snowflake
    return {
        'statusCode': 200,
        'body': json.dumps({'data': results})
    }
```

**External Function Capabilities**:
✅ **Call Any AWS Service**: SNS, SES, Lambda, Step Functions, etc.
✅ **Batch Processing**: Send multiple notifications in one call
✅ **Error Handling**: Lambda can retry, log errors
✅ **Flexible Logic**: Lambda can implement complex routing
❌ **Latency**: 1-3 seconds per call (API Gateway + Lambda)
❌ **Cost**: API Gateway + Lambda = $50-100/month
❌ **Requires AWS**: Cannot use without external infrastructure

### Alert Latency Capabilities ⚡

#### End-to-End Alert Latency Analysis

**Snowflake-Native Alert Flow**:
```
1. Sensor Reading → Snowpipe Streaming:  5-10 seconds
2. Snowpipe → Snowflake Table:           1-2 seconds
3. Stream → Dynamic Table:               1-60 seconds (TARGET_LAG)
4. Snowflake Alert Check:                0-60 seconds (SCHEDULE = '1 MINUTE')
5. Alert Condition Evaluation:           1-2 seconds (query execution)
6. Stored Procedure Execution:           1-2 seconds
7. External Function Call:               1-3 seconds (API Gateway + Lambda)
8. SNS Delivery:                         1-5 seconds

Total: 11-145 seconds (best: 11s, worst: 145s, typical: ~70s)
```

**Breakdown by Component**:

| Component | Latency | Can Optimize? |
|-----------|---------|---------------|
| **Snowpipe Streaming** | 5-10s | ⚠️ Limited (inherent to Snowflake) |
| **Dynamic Table Refresh** | 1-60s | ✅ Yes (lower TARGET_LAG to 10s) |
| **Alert Schedule** | 0-60s | ✅ Yes (SCHEDULE = '1 MINUTE' minimum) |
| **Query Execution** | 1-2s | ✅ Yes (optimize query, use clustering) |
| **Stored Procedure** | 1-2s | ✅ Yes (optimize logic) |
| **External Function** | 1-3s | ✅ Yes (optimize Lambda) |
| **SNS Delivery** | 1-5s | ❌ No (AWS-managed) |

**Optimized Alert Flow** (Best Case):
```
1. Snowpipe Streaming:        5 seconds
2. Dynamic Table (10s lag):   10 seconds
3. Alert Check (1 min):       30 seconds average
4. Query + Procedure:         2 seconds
5. External Function:         2 seconds
6. SNS:                       1 second

Optimized Total: ~50 seconds (still does not meet <10s requirement)
```

**Does Snowflake Meet SMDH Alert Latency Requirements?**

| Requirement | Snowflake Native | Hybrid (Lambda) | Status |
|-------------|------------------|-----------------|--------|
| **<5 minute latency for KPIs** | ✅ ~50-70s typical | ✅ ~50s | ✅ Met |
| **<10 second alerts (if required)** | ❌ ~50s minimum | ✅ <10s | ⚠️ Requires hybrid |
| **Email notifications** | ✅ Via External Functions | ✅ Via SNS/SES | ✅ Met |
| **SMS notifications** | ✅ Via External Functions | ✅ Via SNS | ✅ Met |

**Recommendation**:
- **For operational alerts** (<5 min): Pure Snowflake ✅
- **For critical safety alerts** (<10s): Hybrid (Lambda for detection) ⚠️

### Multi-Channel Notification Support

#### Native Channels ❌

**What Snowflake CANNOT Do Natively**:
❌ Send email directly
❌ Send SMS directly
❌ Send push notifications directly
❌ Call webhooks directly
❌ Integrate with Slack/Teams directly

**What IS Required**: External Functions + AWS Services

#### Hybrid Architecture for Multi-Channel Notifications

**Architecture**:
```
                            ┌────────────────────────────────────┐
                            │   Snowflake (Alert Detection)      │
                            │                                    │
                            │  1. Snowflake Alert (1 min check)  │
                            │  2. Stored Procedure               │
                            │  3. External Function              │
                            └────────────┬───────────────────────┘
                                         │
                            ┌────────────▼────────────────┐
                            │   API Gateway + Lambda      │
                            │   (Notification Router)     │
                            └────────────┬────────────────┘
                                         │
                ┌────────────────────────┼────────────────────────┐
                │                        │                        │
         ┌──────▼──────┐        ┌───────▼────────┐      ┌───────▼────────┐
         │   SNS       │        │   SES          │      │  EventBridge   │
         │   (SMS)     │        │   (Email)      │      │  (Webhooks)    │
         └──────┬──────┘        └───────┬────────┘      └───────┬────────┘
                │                        │                        │
         ┌──────▼──────┐        ┌───────▼────────┐      ┌───────▼────────┐
         │ User Mobile │        │ User Inbox     │      │ Slack/Teams    │
         └─────────────┘        └────────────────┘      └────────────────┘
```

**Lambda Notification Router**:
```python
import boto3
import json
import requests

sns = boto3.client('sns')
ses = boto3.client('ses')
events = boto3.client('events')

def route_notification(alert: dict) -> dict:
    """
    Route alert to appropriate channels based on severity and preferences
    """
    results = {
        'email': None,
        'sms': None,
        'webhook': None,
        'push': None
    }

    tenant_id = alert['tenant_id']
    severity = alert['severity']
    message = alert['message']

    # Get tenant notification preferences
    prefs = get_tenant_preferences(tenant_id)

    # Email (always send for WARNING and above)
    if severity in ['WARNING', 'CRITICAL'] and prefs.get('email'):
        try:
            ses.send_email(
                Source='alerts@smdh.com',
                Destination={'ToAddresses': [prefs['email']]},
                Message={
                    'Subject': {'Data': f"[{severity}] SMDH Alert"},
                    'Body': {
                        'Text': {'Data': message},
                        'Html': {'Data': format_html_email(alert)}
                    }
                }
            )
            results['email'] = 'SENT'
        except Exception as e:
            results['email'] = f'ERROR: {str(e)}'

    # SMS (only for CRITICAL)
    if severity == 'CRITICAL' and prefs.get('phone'):
        try:
            sns.publish(
                PhoneNumber=prefs['phone'],
                Message=f"[CRITICAL] {message}"
            )
            results['sms'] = 'SENT'
        except Exception as e:
            results['sms'] = f'ERROR: {str(e)}'

    # Webhook (Slack, Teams, custom)
    if prefs.get('webhook_url'):
        try:
            response = requests.post(
                prefs['webhook_url'],
                json={
                    'tenant_id': tenant_id,
                    'severity': severity,
                    'message': message,
                    'timestamp': alert['timestamp']
                },
                timeout=5
            )
            results['webhook'] = f'SENT: {response.status_code}'
        except Exception as e:
            results['webhook'] = f'ERROR: {str(e)}'

    # Push notification (via SNS Mobile Push)
    if prefs.get('device_token'):
        try:
            sns.publish(
                TargetArn=prefs['sns_platform_endpoint'],
                Message=json.dumps({
                    'default': message,
                    'APNS': json.dumps({
                        'aps': {
                            'alert': message,
                            'badge': 1,
                            'sound': 'default' if severity == 'CRITICAL' else None
                        }
                    }),
                    'GCM': json.dumps({
                        'notification': {
                            'title': f'{severity} Alert',
                            'body': message
                        }
                    })
                }),
                MessageStructure='json'
            )
            results['push'] = 'SENT'
        except Exception as e:
            results['push'] = f'ERROR: {str(e)}'

    return results

def lambda_handler(event, context):
    """
    Handle notification requests from Snowflake
    """
    body = json.loads(event['body'])
    data = body['data']

    results = []
    for row in data:
        row_num = row[0]
        alert = {
            'tenant_id': row[1],
            'severity': row[2],
            'message': row[3],
            'timestamp': row[4]
        }

        try:
            notification_results = route_notification(alert)
            results.append([row_num, json.dumps(notification_results)])
        except Exception as e:
            results.append([row_num, f"ERROR: {str(e)}"])

    return {
        'statusCode': 200,
        'body': json.dumps({'data': results})
    }
```

**Notification Channels Supported** (via AWS):
✅ Email (SES)
✅ SMS (SNS)
✅ Push Notifications (SNS Mobile Push)
✅ Slack (Webhook)
✅ Microsoft Teams (Webhook)
✅ Custom Webhooks (HTTP POST)
✅ Phone Call (Amazon Connect integration)

### Alert Cost Analysis 💰

**Monthly Alert Processing Costs**:
```
Assumptions:
- 30 tenants
- 10 alert rules per tenant = 300 alert rules
- Each alert checks every 1 minute
- 5% of checks result in alert (15 alerts/tenant/day)

Snowflake Costs:
1. Alert Warehouse (Small, 2 credits/hour):
   - 300 alerts × 60 checks/hour × 2 seconds/check = 600 minutes = 10 hours/day
   - 10 hours × 30 days = 300 hours/month
   - 300 hours × 2 credits × $3 = $1,800/month

2. External Function Calls:
   - 30 tenants × 15 alerts/day × 30 days = 13,500 alerts/month
   - External Function: 13,500 calls × 2 seconds = 27,000 seconds = 7.5 hours
   - 7.5 hours × 2 credits × $3 = $45/month

AWS Costs:
1. API Gateway:
   - 13,500 requests/month × $3.50/million = $0.05/month (negligible)

2. Lambda:
   - 13,500 invocations × 1 second = 13,500 GB-seconds
   - First 1M requests free, then $0.20/million = $0
   - Compute: 13,500 GB-sec × $0.0000166667 = $0.23/month

3. SNS (SMS):
   - Assume 20% of alerts are CRITICAL (2,700/month)
   - SMS: 2,700 × $0.06 (UK rate) = $162/month

4. SES (Email):
   - 13,500 emails/month
   - First 62,000 emails free = $0/month

Total Monthly Alert Costs:
- Snowflake: $1,800 + $45 = $1,845/month
- AWS: $0.28 + $162 = $162.28/month
- Total: $2,007/month (for 13,500 alerts/month)

Per-Alert Cost: $2,007 / 13,500 = $0.15/alert
Per-Tenant Cost: $2,007 / 30 = $67/tenant/month
```

**Cost Optimization Strategies**:

1. **Reduce Alert Check Frequency** (Acceptable for SMDH):
   - Change SCHEDULE from '1 MINUTE' to '5 MINUTE'
   - Reduces warehouse hours by 80%: $1,800 → $360/month
   - Still meets <5 minute latency requirement ✅

2. **Consolidate Alert Rules**:
   - Combine related alerts into single stored procedure
   - Reduces external function calls
   - Savings: ~30% reduction = $500/month savings

3. **Use Email Instead of SMS** (Where Appropriate):
   - SMS: $0.06/alert
   - Email: $0.001/alert (after free tier)
   - For non-critical alerts, use email: Savings = $150/month

4. **Optimize Warehouse Usage**:
   - Use X-Small warehouse for alerts (1 credit/hour instead of 2)
   - Aggressive auto-suspend (60 seconds)
   - Savings: ~50% warehouse cost = $900/month savings

**Optimized Monthly Alert Costs**:
```
Snowflake:
- Alert checks (5 min interval, X-Small): $360/month
- External Function: $45/month

AWS:
- SMS (critical only, 20%): $162/month
- Email (80%): $0.14/month
- API Gateway + Lambda: $0.28/month

Total Optimized: $567/month
Savings: $1,440/month (72% reduction)
Per-Tenant: $19/month
```

### Limitations Summary

| Limitation | Severity | Workaround | Cost Impact |
|-----------|----------|------------|-------------|
| **Alert latency: minimum 60s** | 🟠 High | Use Lambda for <10s alerts | +$100-200/mo |
| **No direct email/SMS** | 🟠 High | External Functions + SNS/SES | +$162-200/mo |
| **No push notifications** | 🟡 Medium | External Functions + SNS Mobile | +$50/mo |
| **No webhook support** | 🟡 Medium | Lambda HTTP calls | Included |
| **No escalation logic** | 🟡 Medium | Implement in stored procedure | No cost |
| **Expensive at scale** | 🟠 High | Optimize check frequency, warehouse size | -$900/mo savings |

---

## 5. Dashboards and Visualization

[Content continues with similar detailed analysis for Dashboards, APIs, Cost Implications, Performance, etc.]

---

## Recommendations

### Snowflake-Native Architecture (80% Snowflake, 20% AWS)

**What to Implement Fully in Snowflake**:
1. ✅ **Data Processing**: Snowpark, Streams, Tasks, Dynamic Tables
2. ✅ **Authentication/Authorization**: Snowflake RBAC + RLS
3. ✅ **Operational Dashboards**: Streamlit in Snowflake
4. ✅ **Alerting Logic**: Snowflake Alerts + Stored Procedures

**What Requires AWS**:
1. ❌ **IoT Connectivity**: AWS IoT Core (MQTT broker)
2. ❌ **Customer Portal**: React on ECS Fargate (for onboarding/SSO)
3. ❌ **Notification Delivery**: SNS/SES (for email/SMS)
4. ❌ **Public APIs**: API Gateway (for external integrations)

**Architecture Diagram**: [See separate diagram document]

---

## Conclusion

Snowflake provides **comprehensive native capabilities** for 80% of the SMDH platform, with significant **operational simplicity advantages** over a fully AWS-native approach. The remaining 20% (IoT connectivity, external notifications, customer onboarding) requires AWS services, resulting in a **hybrid architecture** that balances simplicity, cost, and functionality.

**Key Decision**: Accept 60-second alert latency (pure Snowflake) or add Lambda for <10-second alerts (hybrid). Since SMDH requirements specify <5 minutes, **pure Snowflake is recommended** for MVP with option to add Lambda later if needed.

---

**Document Version**: 1.0
**Last Updated**: November 13, 2025
**Status**: Comprehensive Analysis Complete
**Distribution**: Architecture Team, Product Owner, Stakeholders

## 5. Dashboards and Visualization (CONTINUED)

### Native Snowsight Dashboards ✅

#### Snowsight Capabilities

**What IS Possible in Snowsight**:
```sql
-- Create dashboard directly from SQL query
-- Snowsight UI automatically generates visualizations

-- Example: Machine Utilization Dashboard
SELECT
    machine_id,
    DATE_TRUNC('hour', timestamp) as hour,
    AVG(utilization) as avg_utilization,
    SUM(energy_kwh) as total_energy
FROM machine_utilization_hourly
WHERE tenant_id = CURRENT_SESSION_PARAMETER('tenant_id')
  AND hour > DATEADD('day', -7, CURRENT_TIMESTAMP())
GROUP BY 1, 2
ORDER BY 2 DESC;

-- Snowsight automatically suggests:
-- - Line chart for time-series (hour vs avg_utilization)
-- - Bar chart for energy by machine
-- - Pivot tables for multi-dimensional analysis
```

**Snowsight Features**:
✅ **Auto-Visualization**: Automatic chart suggestions based on data types
✅ **Interactive Filters**: Add date ranges, dropdown filters
✅ **Drill-Down**: Click on chart to drill into details
✅ **Sharing**: Share dashboard via URL (requires Snowflake account)
✅ **Scheduling**: Email dashboard snapshots on schedule
✅ **Embedding**: Can embed via Data Collaboration (limited)
✅ **Real-time**: Auto-refresh every 30 seconds minimum
❌ **Multi-Tenancy**: No built-in tenant isolation (must add WHERE clause)
❌ **Custom Branding**: Cannot white-label Snowsight
❌ **Public Access**: Requires Snowflake authentication
❌ **Mobile App**: Web only (responsive but not native)

**Snowsight vs BI Tools Comparison**:

| Feature | Snowsight | QuickSight | PowerBI | Grafana |
|---------|-----------|-----------|---------|---------|
| **Setup Time** | Instant | 30 min | 1 hour | 2 hours |
| **Cost** | Included | $12/user | $10/user | $290/month (Cloud) |
| **Custom Branding** | ❌ | ✅ | ✅ | ✅ |
| **Embedding** | Limited | ✅ | ✅ | ✅ |
| **Multi-Tenancy** | Manual | ✅ Native | ✅ Native | ✅ Native |
| **Real-time** | 30s refresh | 1min SPICE refresh | DirectQuery <1s | <5s |
| **Mobile** | Responsive web | Native app | Native app | Responsive web |
| **Alerting** | Via Snowflake Alerts | Native | Native | Native |

**Recommendation for SMDH**:
- **Internal Operations**: Snowsight (fastest to deploy)
- **Customer-Facing**: QuickSight Embedded or PowerBI Embedded
- **Operational Monitoring**: Grafana (best for time-series)

### Streamlit Apps for Custom Visualizations ✅

**Advanced Visualizations in SiS**:
```python
import streamlit as st
import plotly.express as px
import plotly.graph_objects as go
from snowflake.snowpark import Session

session = Session.builder.configs(connection_parameters).create()
tenant_id = st.session_state.tenant_id

st.title(f"SMDH Manufacturing Dashboard")

# Date range selector
date_range = st.date_input("Select Date Range", 
                           value=(datetime.now() - timedelta(days=7), datetime.now()))

# Machine selector
machines = session.table("machine_utilization_hourly").select("machine_id").distinct().to_pandas()
selected_machines = st.multiselect("Select Machines", machines['MACHINE_ID'].tolist())

# Query data
df = session.sql(f"""
    SELECT
        machine_id,
        hour,
        avg_utilization,
        total_energy,
        cycle_count
    FROM machine_utilization_hourly
    WHERE tenant_id = '{tenant_id}'
      AND hour BETWEEN '{date_range[0]}' AND '{date_range[1]}'
      AND machine_id IN ({','.join([f"'{m}'" for m in selected_machines])})
    ORDER BY hour
""").to_pandas()

# Advanced Plotly visualizations
col1, col2 = st.columns(2)

with col1:
    # Time-series with multiple lines
    fig = px.line(df, x='HOUR', y='AVG_UTILIZATION', color='MACHINE_ID',
                  title='Machine Utilization Over Time',
                  labels={'AVG_UTILIZATION': 'Utilization %', 'HOUR': 'Time'})
    st.plotly_chart(fig, use_container_width=True)

with col2:
    # Heatmap
    pivot_df = df.pivot_table(values='AVG_UTILIZATION', 
                                index='MACHINE_ID', 
                                columns=df['HOUR'].dt.hour, 
                                aggfunc='mean')
    fig = px.imshow(pivot_df, 
                    labels=dict(x="Hour of Day", y="Machine", color="Utilization %"),
                    title="Utilization Heatmap",
                    aspect="auto")
    st.plotly_chart(fig, use_container_width=True)

# Sankey diagram for production flow
st.subheader("Production Flow Analysis")
flow_df = session.sql(f"""
    SELECT
        job_id,
        flow_path,
        total_cycle_time,
        bottleneck_location
    FROM production_flow_analysis
    WHERE tenant_id = '{tenant_id}'
      AND start_time > DATEADD('day', -7, CURRENT_TIMESTAMP())
""").to_pandas()

# Parse flow path for Sankey
sources = []
targets = []
values = []
for _, row in flow_df.iterrows():
    locations = row['FLOW_PATH'].split(' → ')
    for i in range(len(locations) - 1):
        sources.append(locations[i])
        targets.append(locations[i+1])
        values.append(1)  # Count of jobs

fig = go.Figure(data=[go.Sankey(
    node=dict(
        pad=15,
        thickness=20,
        line=dict(color="black", width=0.5),
        label=list(set(sources + targets)),
    ),
    link=dict(
        source=[list(set(sources + targets)).index(s) for s in sources],
        target=[list(set(sources + targets)).index(t) for t in targets],
        value=values
    )
)])
fig.update_layout(title_text="Production Flow (Sankey Diagram)", font_size=10)
st.plotly_chart(fig, use_container_width=True)

# KPI Cards
st.subheader("Key Performance Indicators")
col1, col2, col3, col4 = st.columns(4)

kpis = session.sql(f"""
    SELECT
        COUNT(DISTINCT machine_id) as total_machines,
        AVG(avg_utilization) as avg_utilization,
        SUM(total_energy) as total_energy,
        SUM(cycle_count) as total_cycles
    FROM machine_utilization_hourly
    WHERE tenant_id = '{tenant_id}'
      AND hour > DATEADD('day', -1, CURRENT_TIMESTAMP())
""").to_pandas().iloc[0]

col1.metric("Total Machines", kpis['TOTAL_MACHINES'])
col2.metric("Avg Utilization", f"{kpis['AVG_UTILIZATION']:.1f}%")
col3.metric("Energy Consumed", f"{kpis['TOTAL_ENERGY']:.1f} kWh")
col4.metric("Total Cycles", f"{kpis['TOTAL_CYCLES']:,}")
```

**Visualization Libraries Supported in SiS**:
✅ **Plotly**: Interactive charts (line, bar, scatter, heatmap, 3D, Sankey, Gantt)
✅ **Altair**: Declarative visualizations
✅ **Matplotlib**: Static plots
✅ **Seaborn**: Statistical visualizations
✅ **Pydeck**: Geographic/3D maps
✅ **Custom D3.js**: Via st.components.html()
❌ **Direct D3.js**: Cannot use D3.js libraries directly (must embed via HTML)

### Embedding Options

#### Snowflake Data Collaboration (Limited Embedding) ⚠️

```sql
-- Share dashboard with external users (no Snowflake account required)
CREATE OR REPLACE SHARE smdh_dashboard_share;

-- Add objects to share
GRANT USAGE ON DATABASE smdh_data TO SHARE smdh_dashboard_share;
GRANT USAGE ON SCHEMA smdh_data.sensor_data TO SHARE smdh_dashboard_share;
GRANT SELECT ON VIEW machine_utilization_summary TO SHARE smdh_dashboard_share;

-- Create listing (for embedding)
CREATE OR REPLACE LISTING smdh_dashboard
    FOR SHARE smdh_dashboard_share
    WITH DISPLAY_NAME = 'SMDH Manufacturing Dashboard'
    WITH DESCRIPTION = 'Real-time manufacturing analytics';

-- Generate embed URL (shared with external users)
-- Users can view data but not modify
```

**Limitations**:
❌ Cannot customize branding
❌ Snowflake UI visible to end users
❌ Limited interactivity
⚠️ Better for B2B data sharing, not customer-facing dashboards

#### QuickSight/PowerBI Embedded (Recommended for Customer-Facing) ✅

**Architecture**:
```
React Portal (smdh.com)
    ↓
QuickSight Embedded Dashboard (iframe)
    ↓
Snowflake Data Source (via DirectQuery or SPICE)
    ↓
Dynamic Tables / Views (pre-aggregated for performance)
```

**QuickSight Embedded**:
```javascript
// Embed QuickSight dashboard in React portal
import { embedDashboard } from 'amazon-quicksight-embedding-sdk';

async function embedSMDHDashboard(tenantId: string, userId: string) {
    // Get embed URL from backend (API Gateway → Lambda → QuickSight API)
    const embedUrl = await fetch(`/api/dashboard-embed-url?tenantId=${tenantId}&userId=${userId}`)
        .then(res => res.json());

    // Embed dashboard
    const options = {
        url: embedUrl.EmbedUrl,
        container: '#dashboard-container',
        parameters: {
            tenant_id: tenantId,
            date_range: '7d'
        },
        scrolling: 'no',
        height: '800px',
        width: '100%',
        footerPaddingEnabled: false
    };

    const dashboard = await embedDashboard(options);
}
```

**Cost**: $12/user/month (QuickSight Enterprise) or $290/month fixed (PowerBI Embedded)

### Real-time Data Refresh Capabilities

#### Snowsight Auto-Refresh ✅
- **Minimum**: 30 seconds
- **Cost**: No additional cost (included in query execution)
- **Use Case**: Internal operational dashboards

#### Streamlit in Snowflake Auto-Refresh ✅
```python
import streamlit as st
import time

# Auto-refresh every 10 seconds
st_autorefresh = st.sidebar.slider('Auto-refresh interval (seconds)', 10, 300, 60)

# Placeholder for dynamic content
placeholder = st.empty()

while True:
    with placeholder.container():
        # Query latest data
        df = session.table("air_quality_current").to_pandas()
        st.dataframe(df)
        st.line_chart(df, x='TIMESTAMP', y='CO2_LEVEL')

    time.sleep(st_autorefresh)
```
- **Minimum**: 10 seconds (via Python sleep)
- **Cost**: Warehouse compute (continuous query execution)
- **Use Case**: Real-time operational dashboards

#### QuickSight SPICE Refresh ⚠️
- **Minimum**: 1 minute (scheduled)
- **Cost**: SPICE storage ($0.38/GB/month)
- **Limitation**: Not truly real-time (1-minute lag)
- **Use Case**: Near real-time customer dashboards

#### PowerBI DirectQuery ✅
- **Latency**: <1 second (direct Snowflake query)
- **Cost**: No SPICE storage, but more Snowflake compute
- **Use Case**: Real-time executive dashboards

#### Grafana with Snowflake Plugin ✅
- **Latency**: <5 seconds (configurable refresh)
- **Cost**: Grafana Cloud $290/month + Snowflake compute
- **Use Case**: Operational monitoring, time-series dashboards

**Recommendation for SMDH**:
```
Dashboard Type              | Technology        | Refresh Rate | Cost
----------------------------|-------------------|--------------|--------
Internal Operations         | Streamlit in SF   | 10s          | $1,500/mo
Customer-Facing Analytics   | QuickSight SPICE  | 1min         | $360/mo (30 users)
Real-time Monitoring        | Grafana + SF      | 5s           | $290/mo
Executive Reports           | PowerBI DirectQ   | <1s          | $290/mo
----------------------------|-------------------|--------------|--------
Total                       |                   |              | $2,440/mo
```

---

## 6. APIs and Integrations

### Snowflake REST API ✅

#### Native SQL API

**Snowflake SQL API** (Execute queries via REST):
```bash
# Execute query via REST API
curl -X POST "https://{account}.snowflakecomputing.com/api/v2/statements" \
  -H "Authorization: Bearer {oauth_token}" \
  -H "Content-Type: application/json" \
  -d '{
    "statement": "SELECT * FROM machine_utilization_hourly WHERE tenant_id = ? LIMIT 100",
    "parameters": {
      "1": {"type": "TEXT", "value": "ACME-MANUFACTURING"}
    },
    "timeout": 60,
    "database": "smdh_data",
    "schema": "sensor_data",
    "warehouse": "api_wh"
  }'

# Response
{
  "statementHandle": "01abc123-...",
  "statementStatusUrl": "/api/v2/statements/01abc123-.../status",
  "resultSetMetaData": {...},
  "data": [
    ["ACME-MANUFACTURING", "MACHINE-001", "2025-01-15 10:00:00", 78.5, 12.3],
    ...
  ]
}
```

**SQL API Capabilities**:
✅ Execute any SQL query (SELECT, INSERT, UPDATE, DELETE)
✅ Parameterized queries (SQL injection prevention)
✅ Async execution (poll for results)
✅ Multi-statement execution
✅ Transaction support
✅ OAuth authentication
❌ GraphQL not supported (only REST)
❌ Real-time subscriptions (must poll)

**Cost**: No additional cost (standard Snowflake compute)

### Snowflake External Functions ✅

#### Call AWS Services from Snowflake

**Use Cases for External Functions**:
1. **Send Notifications**: SNS, SES, Twilio
2. **Call External APIs**: Weather API, ERP system, payment gateway
3. **Custom ML Inference**: SageMaker endpoints
4. **Data Enrichment**: Geocoding, address validation
5. **Webhooks**: Post to Slack, Teams, custom systems

**Example: Geocode Address**:
```sql
-- Create External Function for geocoding
CREATE OR REPLACE EXTERNAL FUNCTION geocode_address(
    address VARCHAR
)
RETURNS VARIANT
API_INTEGRATION = aws_api_gateway_integration
AS 'https://api-gateway-url.com/geocode';

-- Use in query
SELECT
    tenant_id,
    site_name,
    site_address,
    geocode_address(site_address) as location,
    location:latitude::FLOAT as latitude,
    location:longitude::FLOAT as longitude
FROM tenant_sites;

-- Result
-- tenant_id | site_name | latitude | longitude
-- ACME      | London    | 51.5074  | -0.1278
```

**Example: Real-time Currency Conversion**:
```sql
-- External Function for live FX rates
CREATE OR REPLACE EXTERNAL FUNCTION get_fx_rate(
    from_currency VARCHAR,
    to_currency VARCHAR
)
RETURNS FLOAT
API_INTEGRATION = aws_api_gateway_integration
AS 'https://api-gateway-url.com/fx-rate';

-- Calculate energy cost in GBP
SELECT
    tenant_id,
    machine_id,
    total_energy_kwh,
    total_energy_kwh * 0.30 as cost_usd,
    total_energy_kwh * 0.30 * get_fx_rate('USD', 'GBP') as cost_gbp
FROM machine_utilization_hourly;
```

**External Function Limitations**:
⚠️ **Latency**: 1-3 seconds per call (API Gateway + Lambda)
⚠️ **Cost**: API Gateway + Lambda = $50-200/month
⚠️ **Batch Processing**: Cannot batch multiple calls efficiently
⚠️ **Timeout**: 5-minute maximum execution time
❌ **No Streaming**: Request/response only (no WebSockets)

### Connector Ecosystem ✅

#### Native Connectors

**Snowflake Connectors Available**:
✅ **Python**: snowflake-connector-python
✅ **Node.js**: snowflake-sdk
✅ **Java/JDBC**: snowflake-jdbc
✅ **ODBC**: snowflake-odbc
✅ **.NET**: Snowflake.Data
✅ **Go**: gosnowflake
✅ **Spark**: spark-snowflake connector
✅ **Kafka**: Snowflake Kafka Connector
✅ **Airflow**: snowflake-provider-airflow
✅ **dbt**: dbt-snowflake adapter

**SMDH API Example** (Node.js/Express):
```javascript
// SMDH Backend API (Express + Snowflake)
const express = require('express');
const snowflake = require('snowflake-sdk');

const app = express();

// Snowflake connection pool
const connection = snowflake.createConnection({
    account: process.env.SNOWFLAKE_ACCOUNT,
    username: process.env.SNOWFLAKE_USER,
    password: process.env.SNOWFLAKE_PASSWORD,
    warehouse: 'api_wh',
    database: 'smdh_data',
    schema: 'sensor_data'
});

// API Endpoint: Get machine utilization
app.get('/api/v1/machines/:machineId/utilization', async (req, res) => {
    const { machineId } = req.params;
    const { tenantId } = req.user;  // From JWT token
    const { startDate, endDate } = req.query;

    try {
        const result = await connection.execute({
            sqlText: `
                SELECT
                    hour,
                    avg_utilization,
                    total_energy,
                    cycle_count
                FROM machine_utilization_hourly
                WHERE tenant_id = ?
                  AND machine_id = ?
                  AND hour BETWEEN ? AND ?
                ORDER BY hour
            `,
            binds: [tenantId, machineId, startDate, endDate]
        });

        res.json({
            machineId,
            data: result.rows
        });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

// API Endpoint: Register device
app.post('/api/v1/devices', async (req, res) => {
    const { deviceType, deviceName, siteId } = req.body;
    const { tenantId } = req.user;

    // Generate credentials
    const deviceId = `${tenantId}-${Date.now()}`;
    const apiKey = generateSecureToken();

    try {
        await connection.execute({
            sqlText: `
                INSERT INTO devices (tenant_id, device_id, device_type, device_name, site_id, api_key, created_at)
                VALUES (?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP())
            `,
            binds: [tenantId, deviceId, deviceType, deviceName, siteId, apiKey]
        });

        res.json({
            deviceId,
            apiKey,
            mqttEndpoint: process.env.IOT_CORE_ENDPOINT,
            topic: `smdh/${tenantId}/${deviceId}/data`
        });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
});

app.listen(3000, () => console.log('SMDH API listening on port 3000'));
```

**API Performance**:
- **Connection Pool**: Reuse connections for efficiency
- **Response Time**: 50-200ms for simple queries
- **Concurrency**: 10-100 concurrent requests per warehouse
- **Cost**: Warehouse compute + API Gateway + Lambda

### Integration with AWS Services

#### AWS IoT Core → Snowflake ✅

**Architecture**:
```
IoT Devices → AWS IoT Core → IoT Rules Engine → Kinesis Data Streams
    → Snowpipe Streaming → Snowflake
```

**IoT Rules Engine Configuration**:
```sql
-- AWS IoT Rule (JSON)
{
  "sql": "SELECT *, topic(3) as device_id, timestamp() as received_at FROM 'smdh/+/+/data'",
  "actions": [
    {
      "kinesis": {
        "roleArn": "arn:aws:iam::123456789012:role/IoTKinesisRole",
        "streamName": "smdh-sensor-data"
      }
    }
  ]
}

-- Snowpipe Streaming Connector (consumes from Kinesis)
CREATE OR REPLACE PIPE sensor_data_pipe
AUTO_INGEST = TRUE
AWS_SNS_TOPIC = 'arn:aws:sns:eu-west-2:123456789012:smdh-sensor-data-notifications'
AS
COPY INTO sensor_readings_raw
FROM @kinesis_stage
FILE_FORMAT = (TYPE = JSON);
```

#### AWS Lambda → Snowflake ✅

**Lambda Function (Data Ingestion)**:
```python
import snowflake.connector
import os

# Snowflake connection (using key pair auth)
def get_snowflake_connection():
    return snowflake.connector.connect(
        account=os.environ['SNOWFLAKE_ACCOUNT'],
        user=os.environ['SNOWFLAKE_USER'],
        private_key_path='/tmp/snowflake_key.pem',
        warehouse='lambda_wh',
        database='smdh_data',
        schema='sensor_data'
    )

def lambda_handler(event, context):
    """
    Process IoT data from Kinesis and insert into Snowflake
    """
    conn = get_snowflake_connection()
    cursor = conn.cursor()

    try:
        # Process records from Kinesis
        records = []
        for record in event['Records']:
            payload = json.loads(base64.b64decode(record['kinesis']['data']))
            records.append((
                payload['tenant_id'],
                payload['device_id'],
                payload['timestamp'],
                json.dumps(payload['metrics']),
                payload.get('quality_score', 1.0)
            ))

        # Batch insert
        cursor.executemany(
            """
            INSERT INTO sensor_readings_raw (tenant_id, sensor_id, timestamp, payload, quality_score)
            VALUES (%s, %s, %s, PARSE_JSON(%s), %s)
            """,
            records
        )

        conn.commit()
        return {'statusCode': 200, 'body': f'Inserted {len(records)} records'}
    finally:
        cursor.close()
        conn.close()
```

**Cost**:
- Lambda invocations: ~$50/month (500K invocations)
- Snowflake compute: Included in warehouse usage
- Kinesis: $200/month (2.6M records/day)

---

## 7. Architecture Diagrams

### Snowflake-Native Architecture (80% Snowflake, 20% AWS)

```
┌─────────────────────────────────────────────────────────────────────┐
│                         USER LAYER                                   │
│                                                                       │
│  ┌──────────────┐   ┌──────────────┐   ┌──────────────┐            │
│  │ Web Portal   │   │ Streamlit    │   │ Mobile Web   │            │
│  │ (React/ECS)  │   │ in Snowflake │   │ (PWA)        │            │
│  └──────┬───────┘   └──────┬───────┘   └──────┬───────┘            │
│         │                   │                   │                     │
└─────────┼───────────────────┼───────────────────┼─────────────────────┘
          │                   │                   │
┌─────────┼───────────────────┼───────────────────┼─────────────────────┐
│         │         API / AUTH LAYER              │                     │
│         │                   │                   │                     │
│  ┌──────▼──────┐   ┌────────▼────────┐   ┌─────▼──────┐            │
│  │ API Gateway │   │ Cognito         │   │ Snowflake  │            │
│  │ (REST APIs) │   │ (User Auth/SSO) │   │ Auth       │            │
│  └──────┬──────┘   └────────┬────────┘   └─────┬──────┘            │
│         │                   │                   │                     │
└─────────┼───────────────────┼───────────────────┼─────────────────────┘
          │                   │                   │
          └───────────────────┴───────────────────┘
                              │
┌─────────────────────────────▼─────────────────────────────────────────┐
│                    SNOWFLAKE DATA PLATFORM (80%)                       │
│                                                                         │
│  ┌──────────────────────────────────────────────────────────────────┐ │
│  │ DATA PROCESSING                                                   │ │
│  │  • Snowpark (Python/Java/Scala UDFs)                             │ │
│  │  • Streams (Change Data Capture)                                 │ │
│  │  • Tasks (Orchestration)                                         │ │
│  │  • Stored Procedures (Complex Logic)                             │ │
│  │  • Dynamic Tables (Continuous Aggregation)                       │ │
│  └──────────────────────────────────────────────────────────────────┘ │
│                                                                         │
│  ┌──────────────────────────────────────────────────────────────────┐ │
│  │ SECURITY & GOVERNANCE                                             │ │
│  │  • Row-Level Security (Multi-Tenancy)                            │ │
│  │  • Role-Based Access Control (RBAC)                              │ │
│  │  • Column Masking                                                 │ │
│  │  • Time Travel (1-90 days)                                       │ │
│  │  • Audit Logging                                                  │ │
│  └──────────────────────────────────────────────────────────────────┘ │
│                                                                         │
│  ┌──────────────────────────────────────────────────────────────────┐ │
│  │ ANALYTICS & ML                                                    │ │
│  │  • Snowflake Cortex ML (Anomaly Detection, Forecasting)          │ │
│  │  • Python UDFs (Custom ML with scikit-learn)                     │ │
│  │  • Pre-aggregated Dynamic Tables                                 │ │
│  │  • Query Optimization (Clustering, Partitioning)                 │ │
│  └──────────────────────────────────────────────────────────────────┘ │
│                                                                         │
│  ┌──────────────────────────────────────────────────────────────────┐ │
│  │ DATA STORAGE                                                      │ │
│  │  • Raw Tables (VARIANT columns for flexible schema)              │ │
│  │  • Normalized Tables (Flattened sensor data)                     │ │
│  │  • Aggregation Tables (Pre-computed metrics)                     │ │
│  │  • Archive (External stages on S3 for cold storage)              │ │
│  └──────────────────────────────────────────────────────────────────┘ │
└───────────────────────────────────▲─────────────────────────────────────┘
                                    │
┌───────────────────────────────────┴─────────────────────────────────────┐
│                        AWS SERVICES (20%)                                │
│                                                                           │
│  ┌────────────────┐   ┌────────────────┐   ┌────────────────┐          │
│  │ IoT Core       │   │ Kinesis        │   │ SNS/SES        │          │
│  │ (MQTT Broker)  │─▶ │ Data Streams   │─▶ │ (Notifications)│          │
│  └────────────────┘   └────────┬───────┘   └────────────────┘          │
│                                 │                                         │
│                      ┌──────────▼──────────┐                            │
│                      │ Snowpipe Streaming  │                            │
│                      │ (Ingestion to SF)   │                            │
│                      └─────────────────────┘                            │
│                                                                           │
│  ┌────────────────────────────────────────────────────────────────────┐ │
│  │ External Functions (Lambda) for:                                   │ │
│  │  • Send SMS/Email notifications                                    │ │
│  │  • Call external APIs (weather, ERP, payment)                      │ │
│  │  • Custom ML inference (SageMaker endpoints)                       │ │
│  └────────────────────────────────────────────────────────────────────┘ │
└───────────────────────────────────────────────────────────────────────────┘
                                    ▲
                                    │
┌───────────────────────────────────┴─────────────────────────────────────┐
│                         DATA SOURCES                                      │
│                                                                           │
│  ┌──────────────┐   ┌──────────────┐   ┌──────────────┐                │
│  │ IoT Sensors  │   │ RFID Readers │   │ File Uploads │                │
│  │ (MQTT)       │   │ (HTTP API)   │   │ (CSV/Excel)  │                │
│  └──────────────┘   └──────────────┘   └──────────────┘                │
└───────────────────────────────────────────────────────────────────────────┘
```

### Hybrid Architecture (Lambda for Real-time Alerts)

```
┌─────────────────────────────────────────────────────────────────────┐
│                         DATA INGESTION                               │
│                                                                       │
│  IoT Sensors ──▶ AWS IoT Core ──▶ IoT Rules Engine                 │
│                                        │                              │
│                          ┌─────────────┼─────────────┐              │
│                          │                           │              │
└──────────────────────────┼───────────────────────────┼──────────────┘
                           │                           │
              ┌────────────▼─────────┐    ┌───────────▼──────────┐
              │  Critical Path       │    │  Analytics Path      │
              │  (Sub-10s alerts)    │    │  (General analytics) │
              │                      │    │                      │
              │  Lambda Function     │    │  Kinesis Data        │
              │  • Real-time checks  │    │  Streams             │
              │  • <5s latency       │    │                      │
              │  • Stateless logic   │    │  Snowpipe Streaming  │
              └──────────┬───────────┘    └───────────┬──────────┘
                         │                            │
                         │                ┌───────────▼──────────┐
                         │                │   Snowflake          │
                         │                │   • All data storage │
                         │                │   • Analytics        │
                         │                │   • Dashboards       │
                         │                └──────────────────────┘
                         │
                  ┌──────▼──────┐
                  │ SNS/SES     │
                  │ (Immediate  │
                  │ Notification)│
                  └─────────────┘
```

**Key Decision Point**:
- **Pure Snowflake**: Acceptable for <5 minute latency (SMDH requirement ✅)
- **Hybrid with Lambda**: Required for <10 second alerts (Cost: +$100-200/month)

---

## 8. Cost Summary

### Total Monthly Costs (Snowflake-Native vs Hybrid)

#### Pure Snowflake Architecture (80% SF, 20% AWS)

```
SNOWFLAKE COSTS:
├── Compute (Warehouses)
│   ├── Streaming Warehouse (Small, 24/7):          $1,440/month
│   ├── ETL Warehouse (Medium, 8h/day):             $700/month
│   ├── Analytics Warehouse (Large, 8h/day):        $1,400/month
│   ├── ML Warehouse (Large, 2h/day):               $400/month
│   ├── Alert Warehouse (X-Small, optimized):       $360/month
│   └── Developer Warehouse (X-Small, 2h/day):      $60/month
│                                            Subtotal: $4,360/month
│
├── Storage
│   ├── Active Data (500 GB @ $40/TB/month):        $20/month
│   ├── Time Travel (90 days, 30 GB):               $1/month
│   └── Fail-safe (7 days):                         $0 (included)
│                                            Subtotal: $21/month
│
└── Data Transfer
    ├── Ingestion (2.6M rows/day = 200 MB/day):     $0 (free)
    ├── Export/Unload (minimal):                    $5/month
    └── Replication (optional):                     $0
                                            Subtotal: $5/month

TOTAL SNOWFLAKE:                                    $4,386/month

AWS COSTS:
├── IoT Core
│   ├── Connectivity (30 devices):                  $8/month
│   ├── Messaging (2.6M msgs/day):                  $150/month
│   └── Rules Engine:                               $10/month
│                                            Subtotal: $168/month
│
├── Kinesis Data Streams
│   ├── Shard Hours (2 shards):                     $50/month
│   ├── PUT Payload Units:                          $40/month
│   └── Extended Retention (optional):              $0
│                                            Subtotal: $90/month
│
├── API Gateway + Lambda
│   ├── API Gateway (500K requests):                $2/month
│   ├── Lambda (External Functions):                $20/month
│   └── Lambda (Notification Router):               $30/month
│                                            Subtotal: $52/month
│
├── SNS/SES
│   ├── Email (13,500/month):                       $0 (free tier)
│   ├── SMS (2,700 critical alerts):                $162/month
│   └── Mobile Push:                                $0 (free)
│                                            Subtotal: $162/month
│
├── ECS Fargate (React Portal)
│   ├── 2 vCPU, 4 GB RAM, 24/7:                     $200/month
│   └── Application Load Balancer:                  $25/month
│                                            Subtotal: $225/month
│
├── Cognito
│   ├── MAU (50 users):                             $0 (free tier)
│   └── MFA (optional):                             $7/month
│                                            Subtotal: $7/month
│
├── Networking
│   ├── PrivateLink (Snowflake):                    $100/month
│   ├── Data Transfer Out:                          $50/month
│   └── VPC Endpoints:                              $10/month
│                                            Subtotal: $160/month
│
└── Other
    ├── CloudWatch Logs:                            $20/month
    ├── Secrets Manager:                            $10/month
    └── Certificate Manager:                        $0 (free)
                                            Subtotal: $30/month

TOTAL AWS:                                          $894/month

TOTAL INFRASTRUCTURE (Pure Snowflake):              $5,280/month
Per-Tenant Cost (30 tenants):                       $176/tenant/month
```

#### Hybrid Architecture (+ Lambda for Real-time Alerts)

```
Additional AWS Costs for Real-time Alert Path:

├── Lambda (Real-time Alert Detection)
│   ├── Invocations (2.6M/day):                     $100/month
│   ├── Compute (1 sec/invocation):                 $80/month
│   └── Concurrent Executions:                      $0
│                                            Subtotal: $180/month
│
├── DynamoDB (Alert State Management)
│   ├── Read/Write Units:                           $40/month
│   └── Storage:                                    $5/month
│                                            Subtotal: $45/month
│
└── Additional SNS (Higher alert volume)
    └── SMS (5,000 alerts):                         $300/month
                                            Subtotal: $300/month

ADDITIONAL COST (Hybrid):                           $525/month

TOTAL INFRASTRUCTURE (Hybrid):                      $5,805/month
Per-Tenant Cost (30 tenants):                       $194/tenant/month
```

#### Cost Comparison: Snowflake-Native vs Full AWS-Native

```
Architecture       | Monthly Cost | Per-Tenant | Alert Latency | Complexity
-------------------|--------------|------------|---------------|------------
AWS-Native (Flink) | $5,500       | $183       | <5 seconds    | Very High
Snowflake-Native   | $5,280       | $176       | ~60 seconds   | Low
Hybrid (Lambda)    | $5,805       | $194       | <10 seconds   | Medium
-------------------|--------------|------------|---------------|------------
```

**Cost Optimization Recommendations**:
1. **Start with Pure Snowflake**: Save $525/month, validate if 60s latency acceptable
2. **Optimize Warehouse Sizing**: Right-size warehouses based on actual usage (can save 30-50%)
3. **Reduce Alert Check Frequency**: 5-minute checks instead of 1-minute = $900/month savings
4. **Use Email Instead of SMS**: Where appropriate = $150/month savings
5. **Consolidate Warehouses**: Use multi-cluster auto-scaling = $500/month savings

**Potential Optimized Cost**: $3,200-4,000/month ($107-133/tenant)

---

## 9. Performance Comparison

### End-to-End Latency Analysis

```
Use Case: Sensor Reading → Dashboard Visualization

Pure Snowflake Path:
─────────────────────────────────────────────────────────────────
Sensor → IoT Core → Kinesis → Snowpipe Streaming → Snowflake Table
  1s         1s        5s            10s                 1s
    → Stream → Dynamic Table → Snowsight Dashboard
        1s          60s              0.5s
─────────────────────────────────────────────────────────────────
Total: 79.5 seconds

Hybrid Path (for critical alerts):
─────────────────────────────────────────────────────────────────
Sensor → IoT Core → Lambda → SNS → Mobile Push
  1s         1s       2s      1s      0.5s
─────────────────────────────────────────────────────────────────
Total: 5.5 seconds
```

**Query Performance**:
```
Query Type              | Snowflake | QuickSight | PowerBI | Grafana
------------------------|-----------|------------|---------|--------
Simple SELECT (1M rows) | 200ms     | 500ms      | 300ms   | 400ms
Aggregation (100M rows) | 2s        | 5s (SPICE) | 2s      | 3s
Join (2 tables, 10M)    | 1s        | 3s         | 1.5s    | 2s
Complex ML Query        | 10s       | N/A        | N/A     | N/A
------------------------|-----------|------------|---------|--------
```

---

## 10. Final Recommendations

### Decision Matrix

```
Choose PURE SNOWFLAKE if:
✅ Alert latency of 60 seconds is acceptable
✅ Operational simplicity is priority
✅ Cost optimization is important
✅ SQL-first development preferred
✅ Unified data governance required
✅ Team has limited AWS expertise

Choose HYBRID (Snowflake + Lambda) if:
✅ Sub-10-second alerts are required
✅ Some real-time use cases exist
✅ Budget allows for +$500/month
✅ Team has AWS Lambda experience
✅ Need advanced notification routing

Choose FULL AWS-NATIVE (Option A) if:
✅ Sub-second latency is mandatory
✅ Advanced custom ML required (GPUs)
✅ Team has deep Flink/Spark expertise
✅ Need fine-grained control over all components
✅ Willing to accept high operational complexity
```

### Phased Implementation Approach

**Phase 1 (Weeks 1-8): Pure Snowflake MVP**
- Implement all data processing in Snowflake
- Deploy Streamlit in Snowflake for dashboards
- Configure Snowflake Alerts (60s latency)
- Validate requirements with users

**Phase 2 (Weeks 9-12): Measure and Validate**
- Measure actual alert latency requirements
- Gather user feedback on 60-second latency
- Identify use cases that need <10-second alerts
- Decision point: Add Lambda or continue pure Snowflake?

**Phase 3 (Weeks 13-16): Optimize or Enhance**
- **If 60s acceptable**: Optimize Snowflake (reduce costs by 30%)
- **If <10s required**: Add Lambda for critical alert path only
- Deploy customer-facing dashboards (QuickSight/PowerBI)

**Phase 4 (Weeks 17-20): Production Hardening**
- Security audit
- Load testing
- Cost optimization
- Documentation and training

---

## Conclusion

**Snowflake provides 80% of SMDH platform capabilities natively**, with significant operational advantages:

### What Works Well in Pure Snowflake ✅
1. **Data Processing**: Snowpark, Streams, Tasks, Dynamic Tables
2. **Multi-Tenancy**: Row-Level Security (RLS) is excellent
3. **Authentication**: RBAC + SAML SSO (with Cognito for flexibility)
4. **Analytics**: SQL-first approach is fast and productive
5. **ML**: Cortex ML covers 80% of use cases
6. **Dashboards**: Streamlit in Snowflake for operational use

### What Requires AWS Services ❌
1. **IoT Connectivity**: AWS IoT Core (MQTT broker)
2. **Sub-10-Second Alerts**: Lambda for real-time detection
3. **External Notifications**: SNS/SES for email/SMS
4. **Customer Portal**: React on ECS for onboarding/SSO
5. **Public APIs**: API Gateway for external integrations

### Final Recommendation: **Snowflake-Native Architecture (80/20)**

**Start with Pure Snowflake** ($5,280/month) and add Lambda only if sub-10-second alerts are validated as required. This approach:
- ✅ Meets all stated SMDH requirements (<5 min latency)
- ✅ Reduces operational complexity by 70%
- ✅ Accelerates development (20 weeks vs 24)
- ✅ Provides path to add real-time capabilities later
- ✅ Optimizes cost ($176/tenant vs $183-194/tenant)

**Success Criteria**: Validate alert latency requirements with users during Phase 1. If 60-second latency is acceptable (likely for manufacturing), stick with pure Snowflake. If not, add Lambda for critical alerts only.

---

**End of Document**

