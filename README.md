# Smart Manufacturing Data Hub (SMDH)

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![AWS](https://img.shields.io/badge/AWS-Cloud-orange)](https://aws.amazon.com/)
[![Snowflake](https://img.shields.io/badge/Snowflake-Data%20Warehouse-blue)](https://www.snowflake.com/)
[![React](https://img.shields.io/badge/React-18+-61dafb)](https://reactjs.org/)

**Developed by [AI Applied](https://aiapplied.com)**

## Overview

The Smart Manufacturing Data Hub (SMDH) is a cloud-native, multi-tenant IoT platform designed to support 30-40 small and medium-sized enterprises (SMEs) in manufacturing. The platform integrates three critical use cases while maintaining a unified, scalable infrastructure.

### Supported Use Cases

1. **Machine Utilization Analytics (MUA)** - Real-time monitoring of machine performance, energy consumption, and operational efficiency
2. **Air Quality Management Analytics (AQMA)** - Environmental monitoring to ensure worker safety and regulatory compliance  
3. **Job Location Tracking** - RFID/barcode-based tracking of products through manufacturing workflows

## Architecture

### Key Platform Metrics

| Metric | Value |
|--------|-------|
| **Data Volume** | 2.6M-3.9M rows per day |
| **Tenants** | 30-40 SME companies |
| **Concurrent Users** | 20-40 users |
| **Dashboards** | 60-120 specialized views |
| **Analytics Latency** | <5 minutes |
| **Real-time Latency** | <1 second |
| **Uptime SLA** | 99.9% |

### Technology Stack

**Cloud Infrastructure:**
- **AWS** (eu-west-2 London region) ✅ Deployed
- **Snowflake** Multi-Tenant Data Warehouse ✅ Deployed
- **React 18+** with TypeScript 🚧 Planned
- **Material-UI (MUI)** framework 🚧 Planned

**Data Processing:**
- **AWS IoT Core** for MQTT message ingestion ✅ Deployed
- **Amazon Kinesis** for stream processing ✅ Deployed
- **AWS Lambda** for serverless compute 🚧 Planned
- **Apache Flink** on Amazon EMR 📋 Future

**Analytics & Visualization:**
- **Streamlit** for manufacturing dashboards 🚧 In Design
- **Amazon CloudWatch** for monitoring ✅ Deployed
- **Amazon QuickSight** for BI dashboards 📋 Future
- **Grafana** for real-time monitoring 📋 Future
- **Power BI Embedded** 📋 Future
- **Amazon SageMaker** for ML models 📋 Future

## Project Structure

```
smdh/
├── docs/                          # Comprehensive documentation
│   ├── architecture/              # Architecture decision records and diagrams ✅
│   ├── detailed-design/           # Detailed design specifications ✅
│   ├── requirements/              # System requirements ✅
│   ├── deployment/                # Sensor deployment guides ✅
│   ├── sensor-docs/               # Device specifications (external PDFs)
│   └── api/                       # API documentation (📋 In Progress)
├── infrastructure/                # Infrastructure as Code ✅ DEPLOYED
│   ├── terraform/                 # AWS Terraform configs (48 resources) ✅
│   ├── snowflake/                 # Snowflake SQL setup ✅
│   └── scripts/                   # Deployment and validation scripts ✅
├── applications/                  # Application layer
│   ├── web-portal/                # Streamlit analytics dashboards (🚧 Design Complete)
│   ├── data-layer/                # Data layer specifications ✅
│   └── [api-gateway]/             # REST API (📋 Future)
├── tests/                         # Comprehensive test suites ✅
│   ├── unit/                      # Unit tests (power, ML, state classification)
│   ├── integration/               # Data flow integration tests
│   ├── e2e/                       # End-to-end pipeline tests
│   ├── device-simulators/         # IoT device simulation tools
│   ├── api-testing/               # REST API testing (Postman)
│   └── certificates/              # Test certificates and CA files
├── use-cases/                     # Use case documentation
│   ├── Air Quality Use Case.docx  # AQMA specifications
│   ├── Machine Utilisation Use Case.docx  # MUA specifications
│   └── Use Case-Muzzle Movement.docx  # Job tracking specifications
├── templates/                     # Document templates
├── data-pipelines/                # Data processing pipeline definitions (🚧 Framework)
└── tools/                         # Development utilities
    ├── deployment/                # Deployment tools
    ├── monitoring/                # Monitoring scripts
    └── utilities/                 # Helper scripts
```

**Legend:**
- ✅ = Implemented and tested
- 🚧 = Design complete, implementation in progress
- 📋 = Planned for next phase

## Quick Start

### Prerequisites

- **AWS CLI** v2.x configured with appropriate permissions
- **Terraform** v1.0+ for infrastructure deployment
- **Node.js** v18+ for web application development
- **Python** v3.9+ for data processing scripts
- **Docker** for containerized deployments
- **Git** for version control

### Local Development Setup

1. **Clone the repository**
   ```bash
   git clone https://github.com/yourusername/smdh.git
   cd smdh
   ```

2. **Install dependencies**
   ```bash
   # Web application
   cd applications/web-portal
   npm install
   
   # Python dependencies
   cd ../../data-pipelines
   pip install -r requirements.txt
   ```

3. **Configure environment variables**
   ```bash
   cp .env.example .env
   # Edit .env with your configuration
   ```

4. **Start development servers**
   ```bash
   # Web portal (React)
   cd applications/web-portal
   npm start
   
   # API Gateway (local)
   cd ../api-gateway
   npm run dev
   ```

### Infrastructure Deployment

1. **Deploy AWS infrastructure with Terraform**
   ```bash
   cd infrastructure/terraform
   terraform init
   terraform plan -var-file=environments/dev/terraform.tfvars
   terraform apply -var-file=environments/dev/terraform.tfvars
   ```

2. **Configure Snowflake infrastructure**
   ```bash
   cd ../snowflake
   ./validate_setup.sh test_tenant
   # This runs all 4 core setup scripts + tenant onboarding
   ```

3. **Verify deployment**
   ```bash
   # Test IoT Core connectivity
   cd ../../tests
   python device-simulators/test-iot-transmission.py --endpoint <your-endpoint> ...

   # Validate data flow
   python integration/validate-data-flow.py --region eu-west-2 ...
   ```

For detailed deployment instructions, see [Deployment Checklist](DEPLOYMENT_CHECKLIST.md).

## Data Sources

### Machine Utilization Monitoring (MUA)
- **Power Monitoring Sensors**: Real-time electrical current and power consumption (1Hz)
- **Machine State Sensors**: Operational status, cycle counts, downtime events
- **Smart Energy Meters**: Voltage, current, power factor, kWh consumption (15-second intervals)

### Air Quality Management (AQMA)
- **CO2 Sensors**: Carbon dioxide levels (1-minute intervals)
- **VOC Sensors**: Volatile organic compounds for worker safety
- **Particulate Matter Sensors**: PM1, PM2.5, PM4, PM10 concentrations
- **Temperature/Humidity Sensors**: Environmental comfort monitoring

### Job Location Tracking
- **RFID Readers**: Event-driven scanning at production checkpoints
- **Barcode Scanners**: Manual and automated product tracking
- **Location Tags**: Track products through manufacturing stages

## Security & Compliance

- **Encryption**: TLS 1.2+ in transit, KMS encryption at rest
- **Authentication**: AWS Cognito with MFA support
- **Authorization**: Row-Level Security (RLS) in Snowflake
- **Compliance**: GDPR, ISO 27001, SOC 2 Type II ready
- **Network Security**: VPC with private subnets, WAF protection

## Monitoring & Observability

- **CloudWatch**: Centralized logging and metrics
- **X-Ray**: Distributed tracing
- **Grafana**: Real-time monitoring dashboards
- **PagerDuty**: Incident management and alerting

## Testing

```bash
# Run all tests
npm test

# Run specific test suites
npm run test:unit
npm run test:integration
npm run test:e2e

# Python tests
cd data-pipelines
python -m pytest tests/
```

## Documentation & Guides

### Implementation Status & Planning
- [Implementation Status](IMPLEMENTATION_STATUS.md) - What's built, in progress, and planned
- [Feature Roadmap](FEATURE_ROADMAP.md) - Next steps and timeline
- [Known Limitations](KNOWN_LIMITATIONS.md) - Current constraints and workarounds

### Architecture & Design
- [Architecture Options](docs/architecture/smdh-architecture-option-a-multiBI.md) - Complete analysis of 4 architecture options
- [Detailed AWS Design](docs/detailed-design/SMDH%20AWS%20design.md) - Current implementation design
- [System Requirements](docs/requirements/SMDH-System-Requirements.md) - Complete specs

### Infrastructure & Deployment
- [Terraform Guide](infrastructure/terraform/README.md) - AWS infrastructure as code
- [Snowflake Setup](infrastructure/snowflake/README.md) - Data warehouse configuration
- [Deployment Checklist](DEPLOYMENT_CHECKLIST.md) - Step-by-step deployment
- [Deployment Notes](infrastructure/DEPLOYMENT_NOTES.md) - Previous deployment record

### Applications & Data Layer
- [Data Layer Design](applications/data-layer/README.md) - Schema design and implementation guide
- [Streamlit Dashboard Guide](applications/web-portal/STREAMLIT_DASHBOARD_GUIDE.md) - Web portal architecture
- [Dashboard Pages Design](applications/web-portal/STREAMLIT_DASHBOARD_PAGES.md) - 8 analytics dashboard specifications
- [Data Ingestion Mapping](applications/data-layer/DATA_INGESTION_MAPPING.md) - MQTT to Snowflake data flow

### Testing
- [Testing Guide](tests/README.md) - Complete test suite documentation
- [Test Results](tests/TEST_SUMMARY.md) - Latest test execution results

### Use Cases
- See [use-cases/](use-cases/) for Air Quality, Machine Utilization, and Job Tracking specifications

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

### Development Guidelines

- Follow the coding standards defined in the project
- Write comprehensive tests for new features
- Update documentation for any API changes
- Ensure all tests pass before submitting PRs

## Current Implementation Status

### ✅ Fully Implemented & Production Ready

**AWS Infrastructure**
- IoT Core (MQTT broker, thing types, certificates)
- Kinesis Data Streams (on-demand scaling)
- CloudWatch (dashboards, alarms, logging)
- IAM roles (Snowflake cross-account integration)
- Secrets Manager (credential storage)

**Snowflake Data Warehouse**
- Multi-tenant infrastructure database
- Tenant onboarding automation
- Streams and tasks for real-time ETL
- Dynamic tables for live aggregations
- RBAC and monitoring views

**Testing & Validation**
- Device simulator (MQTT transmission)
- Integration tests (data flow validation)
- E2E tests (raw → power → normalized → aggregated)
- API testing collection (Postman)

### 🚧 In Progress or Design Complete

**Analytics Layer**
- Streamlit dashboard portal (design complete, code framework ready)
- Data layer schema (MART, ML_MODELS - SQL designed, implementation ready)
- 8 dashboard pages (full specifications documented)

**Streamlit Web Portal**
- Architecture designed ✅
- 8 dashboard page specs documented ✅
- Snowflake connector utilities designed ✅
- **Code implementation**: Need to scaffold from design

### 📋 Planned for Future Phases

**Phase 2 Features**
- REST API Gateway (design exists)
- Lambda functions for custom logic
- Mobile application
- Advanced ML models (SageMaker)

**Phase 3+ Features**
- Apache Flink for complex stream processing
- Power BI Embedded analytics
- Grafana monitoring dashboards
- Predictive maintenance models
- Supply chain optimization
- Computer vision integration

For details, see [Feature Roadmap](FEATURE_ROADMAP.md).

## Support

- **Documentation**: [Wiki](https://github.com/yourusername/smdh/wiki)
- **Issues**: [GitHub Issues](https://github.com/yourusername/smdh/issues)
- **Discussions**: [GitHub Discussions](https://github.com/yourusername/smdh/discussions)
- **Email**: smdh-support@example.com

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- AWS for cloud infrastructure services
- Snowflake for data warehouse capabilities
- The manufacturing community for use case insights
- Open source contributors and maintainers

---

**Built by AI Applied for the manufacturing industry**
