# SMDH Infrastructure Test Catalog

## Purpose

This document provides a comprehensive catalog of all infrastructure scripts, their purposes, dependencies, and certification criteria. It serves as the basis for thorough testing to ensure the SMDH platform can be reliably torn down and recreated.

---

## 1. Script Inventory

### 1.1 Snowflake Shell Scripts

| Script | Location | Purpose | Dependencies |
|--------|----------|---------|--------------|
| `snowflake.sh` | `snowflake/scripts/` | Main orchestrator for core infrastructure (deploy/drop/status) | SnowSQL CLI, ACCOUNTADMIN role |
| `onboard_tenant.sh` | `snowflake/scripts/` | Automated tenant onboarding (8-step process) | Core infrastructure deployed |
| `validate_setup.sh` | `snowflake/scripts/` | Full teardown and recreation with validation | SnowSQL CLI |
| `setup_kinesis_integration.sh` | `snowflake/scripts/` | Configure AWS Kinesis connector | AWS IAM role configured |
| `sync_aws_iot_metadata.sh` | `snowflake/scripts/` | Sync AWS IoT metadata to Snowflake | AWS CLI, Terraform outputs |

### 1.2 Snowflake SQL Scripts - Core Infrastructure

| Script | Location | Purpose | Creates |
|--------|----------|---------|---------|
| `00_drop_all.sql` | `sql/core/` | Complete teardown of SMDH infrastructure | N/A (destructive) |
| `00_prerequisites.sql` | `sql/core/` | Environment validation | N/A (validation only) |
| `01_infrastructure_setup.sql` | `sql/core/` | Infrastructure database and schemas | `smdh_infrastructure` database, schemas, tables, monitoring views |
| `02_shared_resources.sql` | `sql/core/` | Warehouses, roles, resource monitors | `SMDH_WH` warehouse, platform roles |
| `03_openflow_connector.sql` | `sql/core/` | Kinesis integration configuration | Openflow connector (requires AWS values) |

### 1.3 Snowflake SQL Scripts - Tenant Setup

| Script | Location | Purpose | Creates |
|--------|----------|---------|---------|
| `10_create_tenant_database.sql` | `sql/tenant/` | Tenant database and registration | `smdh_tenant_{id}` database, base roles |
| `11_create_schemas.sql` | `sql/tenant/` | Schema configuration | 4 schemas: raw, normalized, aggregated, analytics |
| `12_create_tables.sql` | `sql/tenant/` | Data tables | 10+ tables for sensor data storage |
| `13_create_streams.sql` | `sql/tenant/` | CDC streams | 6 streams for real-time processing |
| `14_create_tasks.sql` | `sql/tenant/` | ETL tasks | 5 automated tasks |
| `15_create_dynamic_tables.sql` | `sql/tenant/` | Real-time aggregations | 6 dynamic tables |
| `16_create_roles.sql` | `sql/tenant/` | RBAC configuration | 7 tenant-specific roles |
| `17_create_monitoring.sql` | `sql/tenant/` | Monitoring views and procedures | 13+ monitoring views, health check procedure |

### 1.4 Snowflake SQL Scripts - Utility

| Script | Location | Purpose |
|--------|----------|---------|
| `check_current_state.sql` | `sql/utility/` | Show current infrastructure state |
| `check_role.sql` | `sql/utility/` | Validate current role permissions |
| `validate_tenant.sql` | `sql/utility/` | Comprehensive tenant validation |

### 1.5 Terraform Modules

| Module | Location | Purpose | Creates |
|--------|----------|---------|---------|
| `main.tf` | `terraform/` | Root orchestration | All module coordination |
| `iot-core` | `terraform/modules/iot-core/` | AWS IoT Core | Thing types, logging roles, IoT endpoint |
| `kinesis` | `terraform/modules/kinesis/` | Kinesis Data Streams | On-demand stream with encryption |
| `iam` | `terraform/modules/iam/` | IAM roles | Snowflake cross-account role |
| `secrets-manager` | `terraform/modules/secrets-manager/` | Credentials | Snowflake configuration secret |
| `cloudwatch` | `terraform/modules/cloudwatch/` | Monitoring | Log groups, dashboard, SNS topics |
| `tenant` | `terraform/modules/tenant/` | Per-tenant resources | Thing groups, certificates, policies, rules |

### 1.6 Operational Scripts

| Script | Location | Purpose |
|--------|----------|---------|
| `check_system_health.sh` | `scripts/` | AWS IoT health monitoring |
| `check_iot_costs.sh` | `scripts/` | IoT cost tracking and reporting |

---

## 2. Test Plan

### 2.1 Test Phases

| Phase | Description | Duration | Risk |
|-------|-------------|----------|------|
| 1. Snowflake Teardown | Drop all existing SMDH infrastructure | 1-2 min | LOW |
| 2. Snowflake Core Deploy | Deploy core infrastructure | 2-3 min | MEDIUM |
| 3. Snowflake Tenant Onboard | Create test tenant | 3-5 min | MEDIUM |
| 4. Snowflake Validation | Verify all objects created | 1-2 min | LOW |
| 5. Terraform Plan | Review AWS infrastructure plan | 2-3 min | LOW |
| 6. Terraform Apply | Deploy AWS resources | 5-10 min | HIGH |
| 7. End-to-End Validation | Verify complete integration | 2-3 min | LOW |

### 2.2 Prerequisites

- [ ] SnowSQL CLI installed and configured
- [ ] AWS CLI configured with appropriate credentials
- [ ] Terraform v1.0+ installed
- [ ] Environment variables set:
  - `SNOWSQL_PWD` or Snowflake password configured
  - `SNOWFLAKE_ACCOUNT`
  - `SNOWFLAKE_USER`
  - `AWS_REGION=eu-west-2`

### 2.3 Test Execution Commands

#### Phase 1: Snowflake Teardown
```bash
cd infrastructure/snowflake/scripts
./snowflake.sh drop
```

#### Phase 2: Snowflake Core Deploy
```bash
./snowflake.sh deploy
```

#### Phase 3: Snowflake Tenant Onboard
```bash
./onboard_tenant.sh \
  --tenant-id test_tenant \
  --tenant-name "Test Tenant Ltd" \
  --num-sites 2 \
  --snowflake-account $SNOWFLAKE_ACCOUNT \
  --snowflake-user $SNOWFLAKE_USER
```

#### Phase 4: Snowflake Validation
```bash
./snowflake.sh status
```

#### Phase 5: Terraform Plan
```bash
cd infrastructure/terraform
terraform plan -var-file=environments/dev/terraform.tfvars
```

#### Phase 6: Terraform Apply
```bash
terraform apply -var-file=environments/dev/terraform.tfvars
```

---

## 3. Certification Criteria

### 3.1 Snowflake Core Infrastructure

| Object | Certification Criteria | Pass/Fail |
|--------|----------------------|-----------|
| `smdh_infrastructure` database | EXISTS | |
| `tenant_configs` schema | EXISTS with 4 tables | |
| `monitoring` schema | EXISTS with 5 tables + 6 views | |
| `audit` schema | EXISTS with 2 tables | |
| `SMDH_WH` warehouse | EXISTS, RUNNING | |
| `smdh_infrastructure_admin` role | EXISTS with proper grants | |
| `smdh_monitoring` role | EXISTS with read-only grants | |
| `smdh_tenant_operator` role | EXISTS | |
| `smdh_data_engineer` role | EXISTS | |
| `smdh_platform_monitor` resource monitor | EXISTS | |

### 3.2 Tenant Infrastructure

| Object | Certification Criteria | Pass/Fail |
|--------|----------------------|-----------|
| `smdh_tenant_{id}` database | EXISTS | |
| 4 schemas (raw, normalized, aggregated, analytics) | ALL EXIST | |
| 10+ data tables | ALL EXIST | |
| 6 CDC streams | ALL EXIST, NOT STALE | |
| 5 ETL tasks | ALL EXIST, STATE=started | |
| 6 dynamic tables | ALL EXIST, SCHEDULING_STATE=RUNNING | |
| 7 tenant roles | ALL EXIST with proper grants | |
| 13+ monitoring views | ALL EXIST | |
| `sp_health_check` procedure | EXISTS, EXECUTES | |
| Tenant registered in `tenants` table | EXISTS | |

### 3.3 AWS Infrastructure (Terraform)

| Resource | Certification Criteria | Pass/Fail |
|----------|----------------------|-----------|
| IoT Thing Types | 2 types created (LoRaWANGateway, DevTankOSM) | |
| Kinesis Data Stream | EXISTS with encryption | |
| IAM Roles | Snowflake cross-account role created | |
| Secrets Manager | Snowflake config secret created | |
| CloudWatch Log Groups | IoT logs configured | |
| CloudWatch Dashboard | Created with SMDH metrics | |
| SNS Topic | Alert topic created | |
| Tenant Thing Groups | Hierarchical groups created | |
| Tenant Billing Group | Cost tracking group created | |
| IoT Things (per tenant) | Gateway things created | |
| X.509 Certificates | Generated per gateway | |
| IoT Policies | Topic isolation enforced | |
| IoT Rules | Kinesis routing configured | |

---

## 4. Known Constraints

### 4.1 Snowflake Constraints (from CLAUDE.md)

1. **DEFAULT clause limitation**: Session variables (`$var`) cannot be used in DEFAULT clauses
2. **CREATE TASK syntax order**: Must follow exact order (WAREHOUSE, SCHEDULE, COMMENT, AFTER, WHEN)
3. **Cross-schema task predecessors**: Not allowed - use `SYSTEM$STREAM_HAS_DATA()` instead
4. **INFORMATION_SCHEMA limitations**: Use `SNOWFLAKE.ACCOUNT_USAGE.*` for tasks/streams
5. **Shell variable syntax**: `${var}` not valid in SQL - use `IDENTIFIER()` with session variables

### 4.2 AWS/Terraform Constraints

1. **Thing Type deletion**: Requires 5-minute deprecation period
2. **Certificate deletion**: Must detach from things first
3. **Thing Group deletion**: Must remove all members first

---

## 5. Test Execution Log

### Test Session Information

| Field | Value |
|-------|-------|
| Date | |
| Tester | |
| Snowflake Account | |
| AWS Account | |
| AWS Region | eu-west-2 |
| Environment | dev |

### Test Results Summary

| Phase | Status | Duration | Notes |
|-------|--------|----------|-------|
| 1. Snowflake Teardown | | | |
| 2. Snowflake Core Deploy | | | |
| 3. Snowflake Tenant Onboard | | | |
| 4. Snowflake Validation | | | |
| 5. Terraform Plan | | | |
| 6. Terraform Apply | | | |
| 7. End-to-End Validation | | | |

### Detailed Test Output

*To be filled during test execution*

---

## 6. Rollback Procedures

### Snowflake Rollback
```bash
# Complete teardown
./snowflake.sh drop
```

### Terraform Rollback
```bash
# Destroy all AWS resources
cd infrastructure/terraform
terraform destroy -var-file=environments/dev/terraform.tfvars
```

---

*Document Version: 1.0*
*Last Updated: 2025-12-01*
*Author: Claude Code Testing Agent*
