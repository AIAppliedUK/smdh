# Smart Manufacturing Data Hub (SMDH)

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![AWS](https://img.shields.io/badge/AWS-Cloud-orange)](https://aws.amazon.com/)
[![Snowflake](https://img.shields.io/badge/Snowflake-Data%20Warehouse-blue)](https://www.snowflake.com/)
[![React](https://img.shields.io/badge/React-18+-61dafb)](https://reactjs.org/)

## Overview

The Smart Manufacturing Data Hub (SMDH) is a cloud-native, multi-tenant IoT platform designed to support 30-40 small and medium-sized enterprises (SMEs) in manufacturing. The platform integrates three critical use cases while maintaining a unified, scalable infrastructure.

### 🎯 Supported Use Cases

1. **Machine Utilization Analytics (MUA)** - Real-time monitoring of machine performance, energy consumption, and operational efficiency
2. **Air Quality Management Analytics (AQMA)** - Environmental monitoring to ensure worker safety and regulatory compliance  
3. **Job Location Tracking** - RFID/barcode-based tracking of products through manufacturing workflows

## 🏗️ Architecture

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
- **AWS** (eu-west-2 London region)
- **Snowflake** Multi-Tenant Data Warehouse
- **React 18+** with TypeScript
- **Material-UI (MUI)** framework

**Data Processing:**
- **AWS IoT Core** for MQTT message ingestion
- **Apache Flink** on Amazon EMR for real-time processing
- **Amazon Kinesis** for stream processing
- **AWS Lambda** for serverless compute

**Analytics & Visualization:**
- **Amazon QuickSight** for primary BI dashboards
- **Grafana** for real-time monitoring
- **Power BI Embedded** for advanced analytics
- **Amazon SageMaker** for machine learning

## 📁 Project Structure

```
smdh/
├── docs/                          # Documentation
│   ├── architecture/              # Architecture diagrams and guides
│   ├── api/                       # API documentation
│   └── deployment/                # Deployment guides
├── infrastructure/                # Infrastructure as Code
│   ├── terraform/                 # Terraform configurations
│   ├── cloudformation/            # CloudFormation templates
│   └── kubernetes/                # K8s manifests
├── applications/                  # Application code
│   ├── web-portal/                # React web application
│   ├── api-gateway/               # API Gateway configurations
│   └── lambda-functions/          # Serverless functions
├── data-pipelines/                # Data processing pipelines
│   ├── ingestion/                 # Data ingestion scripts
│   ├── transformation/            # ETL processes
│   └── analytics/                 # Analytics and ML models
├── use-cases/                     # Use case specific implementations
│   ├── machine-utilization/       # MUA implementation
│   ├── air-quality/               # AQMA implementation
│   └── job-tracking/              # Job tracking implementation
├── tests/                         # Test suites
│   ├── unit/                      # Unit tests
│   ├── integration/               # Integration tests
│   └── e2e/                       # End-to-end tests
└── tools/                         # Development tools and scripts
    ├── deployment/                # Deployment scripts
    ├── monitoring/                # Monitoring configurations
    └── utilities/                 # Utility scripts
```

## 🚀 Quick Start

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

1. **Deploy AWS infrastructure**
   ```bash
   cd infrastructure/terraform
   terraform init
   terraform plan
   terraform apply
   ```

2. **Configure Snowflake**
   ```bash
   cd ../../data-pipelines/snowflake
   python setup_snowflake.py
   ```

3. **Deploy data pipelines**
   ```bash
   cd ../ingestion
   python deploy_pipelines.py
   ```

## 📊 Data Sources

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

## 🔐 Security & Compliance

- **Encryption**: TLS 1.2+ in transit, KMS encryption at rest
- **Authentication**: AWS Cognito with MFA support
- **Authorization**: Row-Level Security (RLS) in Snowflake
- **Compliance**: GDPR, ISO 27001, SOC 2 Type II ready
- **Network Security**: VPC with private subnets, WAF protection

## 📈 Monitoring & Observability

- **CloudWatch**: Centralized logging and metrics
- **X-Ray**: Distributed tracing
- **Grafana**: Real-time monitoring dashboards
- **PagerDuty**: Incident management and alerting

## 🧪 Testing

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

## 📚 Documentation

- [Architecture Guide](docs/architecture/SMDH_Architecture_Complete_Guide.md)
- [API Documentation](docs/api/README.md)
- [Deployment Guide](docs/deployment/README.md)
- [Use Case Documentation](use-cases/README.md)

## 🤝 Contributing

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

## 📋 Roadmap

### Phase 1 (Current)
- ✅ Core infrastructure setup
- ✅ Basic MUA implementation
- ✅ AQMA foundation
- ✅ Job tracking prototype

### Phase 2 (Q1 2024)
- 🔄 Advanced analytics dashboards
- 🔄 Machine learning models
- 🔄 Mobile application
- 🔄 API marketplace

### Phase 3 (Q2 2024)
- 📅 Predictive maintenance
- 📅 Supply chain optimization
- 📅 Computer vision integration
- 📅 Voice assistant integration

## 🆘 Support

- **Documentation**: [Wiki](https://github.com/yourusername/smdh/wiki)
- **Issues**: [GitHub Issues](https://github.com/yourusername/smdh/issues)
- **Discussions**: [GitHub Discussions](https://github.com/yourusername/smdh/discussions)
- **Email**: smdh-support@example.com

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- AWS for cloud infrastructure services
- Snowflake for data warehouse capabilities
- The manufacturing community for use case insights
- Open source contributors and maintainers

---

**Built with ❤️ for the manufacturing industry**
