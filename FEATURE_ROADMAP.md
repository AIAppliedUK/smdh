# SMDH Feature Roadmap

Planned features, enhancements, and timeline for Smart Manufacturing Data Hub.

**Last Updated:** November 22, 2025
**Status:** Live deployment November 21, 2025

---

## 📊 Roadmap Overview

```
Phase 1: Infrastructure (✅ COMPLETE)
Nov 2024 - Nov 2025: AWS IoT Core, Kinesis, Snowflake
Results: 48 AWS resources, production-ready data pipeline

Phase 2: Applications (🚧 IN PROGRESS)
Dec 2025 - Feb 2026: Web Portal, API Gateway, Streamlit Dashboard
Deliverables: Analytics dashboards, REST API, user interface

Phase 3: Advanced Analytics (📋 PLANNED)
Mar 2026 - Jun 2026: ML Models, Real-time Alerts, BI Tools
Deliverables: SageMaker models, Grafana dashboards, advanced analytics

Phase 4+: Scale & Optimize (📅 FUTURE)
Jul 2026+: Multi-region, Advanced Features, Market Expansion
```

---

## 🚀 PHASE 2: APPLICATIONS (Dec 2025 - Feb 2026)

### 🎯 Phase 2 Focus
Build user-facing applications and APIs to make data accessible.

### 2.1: Streamlit Web Portal (Dec 2025 - Jan 2026)

**Status:** 🚧 Design Complete, Code Frameworks Ready

**What We're Building:**
- 8 Manufacturing Analytics Dashboards
- Snowflake Integration
- Multi-tenant Support
- User Authentication
- Real-time Data Updates

**Dashboards:**
1. **Fleet Utilization & Idle Losses** - Machine utilization breakdown with cost analysis
2. **Machine Timeline & Shift View** - Gantt-style timeline showing machine states
3. **Production Events & Product Mix** - Event clustering and cycle time analysis
4. **Energy & Cost by State** - Power consumption by operational state
5. **Anomalies & Outliers** - Multi-type anomaly detection dashboard
6. **Machine Health (SENTINEL)** - Vibration, temperature, power quality
7. **Environmental (HAVEN)** - Air quality, temperature, humidity, noise
8. **OEE & Benchmarking** - Complete OEE analysis with comparisons

**Timeline:**
- Week 1-2: Scaffold application structure, Snowflake connector
- Week 3-4: Implement 8 dashboard pages
- Week 5: Caching and performance optimization
- Week 6: Authentication, styling, polish
- Week 7-8: Testing, bug fixes, production deployment

**Tech Stack:**
- Framework: Streamlit 1.29+
- Database: Snowflake Python Connector
- Visualization: Plotly, Altair
- Deployment: Docker → ECS or Lambda

**Success Metrics:**
- ✅ All 8 dashboards load in < 3 seconds
- ✅ Support 40-50 concurrent users
- ✅ 99.9% uptime during business hours
- ✅ <1 minute data latency

**Blockers:** None identified

**References:**
- [Streamlit Guide](applications/web-portal/STREAMLIT_DASHBOARD_GUIDE.md)
- [Dashboard Specs](applications/web-portal/STREAMLIT_DASHBOARD_PAGES.md)

---

### 2.2: MART Schema Implementation (Dec 2025)

**Status:** 🚧 SQL Designed, Needs Snowflake Deployment

**What We're Building:**
- Analytics-optimized tables
- Pre-computed metrics
- Dashboard views
- Materialized aggregations

**Tables:**
- Power metrics (calculated from raw sensor data)
- Machine states (OFF, IDLE, WORKING with durations)
- Production events (cycle detection, quality flags)
- OEE metrics (availability, performance, quality)
- Cost analysis (by state, by tariff period)
- Anomaly flags (statistical and pattern-based)

**Timeline:**
- Deploy all MART SQL (1-2 days)
- Create views and procedures (2-3 days)
- Validate data transformations (3-5 days)
- Performance tuning (3-5 days)

**Tech:**
- Language: Snowflake SQL + Python UDFs
- Storage: Snowflake MART schema
- Refresh: Dynamic tables (1-10 min lag)

**Success Metrics:**
- ✅ All MART tables populated
- ✅ Views return < 2 second response
- ✅ Data accuracy 99.9%+
- ✅ No data gaps or missing records

**References:**
- [Data Layer Design](applications/data-layer/README.md)
- [Implementation Guide](applications/data-layer/SMDH_Data_Layer_Implementation_Guide.md)

---

### 2.3: REST API Gateway (Jan - Feb 2026)

**Status:** 📋 Design Complete, Code Needed

**What We're Building:**
- RESTful API for dashboard and mobile apps
- Authentication & Authorization
- Rate limiting per tenant
- Comprehensive API documentation
- SDK libraries for clients

**API Endpoints:**
```
/api/v1/dashboards/{tenant_id}/...  - Dashboard data
/api/v1/machines/{machine_id}/...  - Machine metrics
/api/v1/sites/{site_id}/...         - Site data
/api/v1/alerts/{tenant_id}/...      - Notifications
/api/v1/export/...                   - Data export
/api/v1/admin/tenants/...            - Tenant management
```

**Timeline:**
- Week 1: API framework setup (FastAPI)
- Week 2: Authentication layer (JWT + Cognito)
- Week 3: Core endpoints implementation
- Week 4: Rate limiting, pagination, filtering
- Week 5: Documentation, SDKs, testing
- Week 6: Deployment, monitoring, hardening

**Tech Stack:**
- Framework: FastAPI (Python)
- Authentication: JWT + AWS Cognito
- Rate Limiting: Redis + lua scripts
- Deployment: Docker → ECS or Lambda
- Documentation: OpenAPI/Swagger
- Clients: Python, JavaScript, Go SDKs

**Success Metrics:**
- ✅ All endpoints < 500ms response
- ✅ Support 1,000 requests/second
- ✅ 99.95% uptime
- ✅ Full API documentation + SDKs

**Integration Points:**
- Snowflake (read)
- CloudWatch (metrics)
- Cognito (auth)
- DynamoDB (caching, optional)

**References:**
- [API Design Document](docs/api/README.md) (to be created)

---

### 2.4: Deployment Infrastructure (Jan - Feb 2026)

**Status:** 🚧 Partial (Terraform ready), Needs Container Setup

**What We're Building:**
- Docker images for Streamlit app
- ECS task definitions and services
- ALB load balancer
- Auto-scaling configuration
- CI/CD pipeline
- Log aggregation
- Monitoring & alerting

**Deployment Architecture:**
```
GitHub → CodePipeline → CodeBuild
  ↓
Docker image → ECR (registry)
  ↓
ALB ← ECS Cluster (3-5 Streamlit tasks)
  ↓
CloudWatch Logs, Alarms, Metrics
```

**Timeline:**
- Week 1: Docker images (Streamlit, API)
- Week 2: ECS cluster, task definitions, ALB
- Week 3: Auto-scaling, deployment manifests
- Week 4: CI/CD pipeline (GitHub Actions or CodePipeline)
- Week 5: Monitoring, logging, dashboards

**Tech:**
- Containerization: Docker
- Orchestration: ECS (Fargate)
- Load Balancing: ALB
- Registry: ECR
- CI/CD: GitHub Actions or CodePipeline
- Logging: CloudWatch Logs, Splunk (optional)
- Monitoring: CloudWatch, DataDog (optional)

**Terraform Changes:**
- Add ECS module (cluster, services, tasks)
- Add ALB module (target groups, rules)
- Add CloudWatch dashboard
- Add SNS alerts for deployment failures

**Success Metrics:**
- ✅ Zero-downtime deployments
- ✅ Auto-scale to handle 2x traffic
- ✅ Deployment < 5 minutes
- ✅ Rollback < 2 minutes

---

## 📈 PHASE 3: ADVANCED ANALYTICS (Mar - Jun 2026)

### 3.1: Machine Learning Models (Mar - Apr 2026)

**Status:** 📋 Research Complete, Code Needed

**Models to Build:**
1. **State Classification (GMM)** - Classify machine states automatically
2. **Anomaly Detection (Isolation Forest)** - Detect unusual patterns
3. **Predictive Maintenance (LSTM)** - Predict failures 7-14 days ahead
4. **Energy Forecasting (Prophet)** - Forecast energy consumption
5. **OEE Optimization** - Identify optimization opportunities

**Platform:** AWS SageMaker or Snowpark Python

**Data Requirements:**
- Historical machine readings (1 year minimum)
- Known failure events (for supervised learning)
- Environmental data (temperature, humidity)
- Production schedule (shift times, maintenance windows)

**Implementation:**
- Training pipeline (monthly retraining)
- Batch predictions (daily runs)
- Real-time scoring (via Snowpark UDFs or Lambda)
- Model registry (SageMaker Model Registry)
- A/B testing framework (for model improvements)

**Success Metrics:**
- ✅ Anomaly detection: 95%+ precision
- ✅ Predictive maintenance: 85%+ accuracy
- ✅ False positive rate < 5%
- ✅ Model inference < 100ms

**Business Impact:**
- Reduce unplanned downtime by 30%
- Improve energy efficiency by 15%
- Increase equipment lifespan by 2-3 years
- Generate maintenance alerts 7-14 days early

**Timeline:**
- Week 1-2: Data preparation and EDA
- Week 3-4: Model training and validation
- Week 5: Model deployment and integration
- Week 6-8: Monitoring, tuning, documentation

---

### 3.2: Real-Time Alerting Engine (Apr - May 2026)

**Status:** 📋 Requirements Gathered

**What We're Building:**
- Real-time condition monitoring
- Multi-level alerts (warning, critical, emergency)
- Notification channels (email, SMS, Slack, PagerDuty)
- Alert routing per tenant
- Alert suppression/escalation rules
- Alert history and analytics

**Alert Types:**
- Data quality (missing data, outliers)
- Machine health (high temperature, vibration)
- Performance (unexpected idle time, slow cycles)
- Cost (power consumption anomalies)
- System (pipeline failures, data gaps)

**Implementation:**
- Snowflake Stream Trigger → Alerting Lambda
- Or: Datadog/New Relic integration
- Database: DynamoDB for alert state
- Notification: SNS, SES, Slack API, PagerDuty API

**Configuration:**
- Per-tenant alert rules
- Custom thresholds
- Noise reduction (debouncing)
- Alert grouping/correlation

**Success Metrics:**
- ✅ Alert latency < 2 minutes
- ✅ 99% delivery rate
- ✅ False positive rate < 5%
- ✅ Alert acknowledgment < 10 minutes

---

### 3.3: Advanced BI Tools (May - Jun 2026)

**Status:** 📋 Design Phase

**Tools to Integrate:**
1. **Amazon QuickSight** - Executive dashboards
2. **Grafana** - Real-time monitoring
3. **Power BI** - Advanced analytics (future)
4. **Tableau** - Ad-hoc analysis (future)

**QuickSight Implementation:**
- Executive KPI dashboard
- Cost analysis dashboard
- Equipment health scorecard
- Predictive maintenance summary

**Grafana Implementation:**
- Real-time metrics (updated every 10 seconds)
- System health dashboard
- Equipment status overview
- Alert status and trends

**Integration Points:**
- Data source: Snowflake (native connectors)
- Refresh schedule: Every 5-15 minutes
- User management: Cognito SSO
- Embedding: In Streamlit app (optional)

**Success Metrics:**
- ✅ All dashboards load < 5 seconds
- ✅ Real-time data latency < 2 minutes
- ✅ Support 100+ concurrent users
- ✅ 99.95% availability

---

## 🔮 PHASE 4+: SCALE & OPTIMIZE (Jul 2026+)

### 4.1: Multi-Region Deployment

**Goal:** Serve manufacturing hubs in multiple geographies

**Regions:**
- eu-west-2 (London) - Primary, GDPR compliance
- us-east-1 (N. Virginia) - NA operations
- ap-southeast-1 (Singapore) - APAC operations

**Architecture:**
- Replicated Kinesis streams
- Read replicas for Snowflake (future)
- CloudFront CDN for static assets
- Route53 geo-routing

**Challenge:** Data residency (GDPR)

**Timeline:** Q3 2026+

---

### 4.2: Mobile Application

**Goal:** Field operator access to real-time data

**Platform:** React Native or Flutter

**Features:**
- Machine status cards
- Production timeline
- Alert notifications
- Energy cost tracking
- Offline support (cache recent data)

**Deployment:** iOS + Android app stores

**Timeline:** Q3-Q4 2026+

---

### 4.3: Advanced Stream Processing

**Goal:** Complex event processing and real-time machine learning

**Technology:** Apache Flink on Amazon EMR

**Use Cases:**
- Multi-event correlation (e.g., detect cascading failures)
- Session windows (grouping related events)
- Pattern detection (specific failure sequences)
- Real-time feature engineering for ML models

**Timeline:** Q4 2026+

---

## 📅 Quarterly Milestones

### Q4 2025 (Dec - Feb 2026)

**Phase 2 - Applications**

**December 2025:**
- [x] Week 1: Project Kickoff & Planning
- [x] Week 2-3: Scaffold Streamlit app structure
- [ ] Week 4: First dashboard (Fleet Utilization) prototype
- [ ] Deploy MART schema to Snowflake

**January 2026:**
- [ ] Complete 8 Streamlit dashboards
- [ ] REST API implementation begins
- [ ] Docker image creation
- [ ] ECS cluster setup

**February 2026:**
- [ ] API Gateway complete and tested
- [ ] Streamlit app deployed to production
- [ ] CI/CD pipeline operational
- [ ] Load testing and optimization

**Deliverables:**
- ✅ Production Streamlit web portal
- ✅ REST API Gateway
- ✅ CI/CD pipeline
- ✅ Monitoring and alerting

---

### Q1 2026 (Mar - May 2026)

**Phase 3 - Advanced Analytics**

**March 2026:**
- [ ] ML model training pipeline
- [ ] State classification model live
- [ ] Anomaly detection model live
- [ ] Predictive maintenance model training

**April 2026:**
- [ ] Predictive maintenance model live
- [ ] Energy forecasting model live
- [ ] Real-time alerting engine live
- [ ] QuickSight dashboards live

**May 2026:**
- [ ] Grafana monitoring live
- [ ] Advanced alerting rules operational
- [ ] Model A/B testing framework
- [ ] User feedback collection and iteration

**Deliverables:**
- ✅ 5 ML models in production
- ✅ Real-time alerting engine
- ✅ Advanced BI integrations
- ✅ 30% fewer unplanned downtime incidents

---

### Q2 2026 (Jun - Aug 2026)

**Phase 4 - Scale & Optimize**

**June 2026:**
- [ ] Multi-region architecture design
- [ ] Performance optimization (all dashboards < 2s)
- [ ] Cost optimization (20% reduction target)
- [ ] Security audit and hardening

**July 2026:**
- [ ] Multi-region deployment to production
- [ ] Mobile app development begins
- [ ] Flink stream processing POC
- [ ] Global data replication live

**August 2026:**
- [ ] 99.99% uptime achievement
- [ ] Support for 100-150 tenants
- [ ] Mobile app beta launch
- [ ] Kubernetes migration planning

**Deliverables:**
- ✅ Multi-region support
- ✅ 99.99% uptime
- ✅ Mobile app beta
- ✅ 3-5x performance improvement

---

## 📊 Success Metrics by Phase

### Phase 1 (Completed)
- ✅ 48 AWS resources deployed
- ✅ Snowflake infrastructure ready
- ✅ Zero data loss
- ✅ Integration tests pass
- ✅ Production ready

### Phase 2 (Target)
- [ ] 100% uptime during business hours
- [ ] <3 second dashboard load time
- [ ] Support 40-50 concurrent users
- [ ] Zero data loss
- [ ] 99.9% SLA

### Phase 3 (Target)
- [ ] 30% reduction in unplanned downtime
- [ ] 15% improvement in energy efficiency
- [ ] <2 minute alert latency
- [ ] 95%+ anomaly detection accuracy
- [ ] 99.95% SLA

### Phase 4 (Target)
- [ ] Support 100-150 tenants
- [ ] <2 second global response time
- [ ] 99.99% SLA
- [ ] 50% reduction in infrastructure costs
- [ ] Mobile app adoption >30%

---

## 💰 Resource Allocation

### Phase 2 (Applications) - Dec 2025 - Feb 2026

**Team:**
- 1 Backend Developer (REST API)
- 1 Frontend Developer (Streamlit)
- 1 DevOps Engineer (Docker, ECS, CI/CD)
- 0.5 Data Engineer (MART schema, data validation)
- 0.5 QA Engineer (Testing, deployment validation)

**Budget:** $150k-200k

---

### Phase 3 (Advanced Analytics) - Mar - Jun 2026

**Team:**
- 1 Data Scientist (ML models)
- 1 ML Engineer (Model deployment)
- 1 Backend Engineer (Alerting system)
- 0.5 DevOps Engineer (Model registry, monitoring)
- 0.5 QA Engineer

**Budget:** $200k-250k

---

### Phase 4 (Scale & Optimize) - Jul 2026+

**Team:**
- Full-stack team (8-10 people)
- Multiple product lines
- Global operations

**Budget:** $300k+/quarter

---

## 🎯 Key Dependencies

### Critical Path Items
1. **Phase 2.1:** Streamlit dashboard (blocks user feedback)
2. **Phase 2.2:** MART schema (needed for Phase 3 ML)
3. **Phase 3.1:** ML models (enables predictive features)
4. **Phase 4:** Multi-region (enables geographic expansion)

### Approval Gates
- Phase 2 kickoff: PMO approval required
- Phase 3 start: Stakeholder review of Phase 2 results
- Phase 4 start: Board approval for expansion

---

## 🚨 Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|-----------|
| Snowflake costs higher than expected | Budget overrun | Optimize queries, implement tiered storage |
| Streamlit scaling issues | Performance problems | Move to FastAPI + React (Phase 3) |
| ML models underperform | Reduced value | Invest in better data collection, more features |
| Talent acquisition delays | Timeline slip | Start hiring 2 months early, contractor support |
| Security vulnerabilities found | Reputation damage | Regular security audits, bug bounty program |

---

## 📞 Feedback & Changes

This roadmap is **living document**. Changes made quarterly based on:
- Stakeholder feedback
- Market conditions
- Technical discoveries
- Customer requests
- Resource availability

**Last review date:** November 22, 2025
**Next review date:** February 28, 2026

To propose changes:
1. Create GitHub issue with `roadmap-change` label
2. Include business justification
3. Identify impact on timeline
4. Propose alternative priority

---

## Related Documents

- [Implementation Status](IMPLEMENTATION_STATUS.md) - Current state
- [Known Limitations](KNOWN_LIMITATIONS.md) - Current constraints
- [Architecture Decision Record](ARCHITECTURE_DECISION_RECORD.md) - Why decisions were made

---

**Roadmap Version:** 1.0
**Last Updated:** November 22, 2025
**Maintainer:** Platform Team
**Review Frequency:** Quarterly
