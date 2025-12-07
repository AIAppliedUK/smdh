# SMDH Deployment Checklist

Complete step-by-step guide to deploy SMDH from scratch.

**Last Updated:** December 3, 2025
**Estimated Deployment Time:** 1-2 hours (first time), 30 minutes (subsequent deployments)

---

## 📋 PRE-DEPLOYMENT REQUIREMENTS

### AWS Account Setup

- [ ] AWS Account created (eu-west-2 region)
- [ ] AWS CLI v2 installed and configured
  ```bash
  aws configure
  # Enter: Access Key ID, Secret Access Key, Region (eu-west-2), Output (json)
  ```
- [ ] Appropriate IAM permissions for:
  - IoT Core (thing, certificate, policy, rule creation)
  - Kinesis (stream creation)
  - CloudWatch (log group, dashboard, alarms)
  - IAM (role creation)
  - Secrets Manager (secret creation)
  - S3 (terraform state bucket)
  - DynamoDB (state locking table)

### Snowflake Account Setup

- [ ] Snowflake account created (eu-west-2 region recommended)
- [ ] Account type: **Enterprise Edition or higher** (required for Dynamic Tables)
- [ ] Snowflake version: **7.0 or higher** (for Dynamic Tables support)
- [ ] SnowSQL CLI installed
  ```bash
  brew install snowflake-snowsql  # macOS
  # or download from: https://docs.snowflake.com/en/user-guide/snowsql-install-config.html
  ```
- [ ] Snowflake admin user created (for setup)
- [ ] Snowflake account ID available (Format: `xy12345`)

### Tools & Dependencies

- [ ] Terraform v1.0+ installed
  ```bash
  brew install terraform  # macOS
  # or download from: https://www.terraform.io/downloads.html
  ```
- [ ] Git installed (for version control)
- [ ] Python 3.9+ installed (for testing scripts)
- [ ] Git credentials configured (`git config user.email`, `user.name`)

### Information to Gather

Before starting, collect:

```
AWS Information:
- AWS Account ID: ___________________
- AWS Region: eu-west-2 (London)
- AWS Access Key: ___________________
- AWS Secret Key: ___________________

Snowflake Information:
- Snowflake Account ID: ___________________
- Snowflake User: ___________________
- Snowflake Password: ___________________
- Snowflake Region: eu-west-2
- Snowflake Warehouse: smdh_admin_wh (or create)

Project Information:
- Project Name: smdh
- Environment: dev (or staging/prod)
- Number of Initial Sites: 2
- Number of Initial Tenants: 1 (test_tenant)
```

---

## 🔧 PHASE 1: INFRASTRUCTURE (AWS with Terraform)

### Step 1.1: Create S3 Backend for Terraform State

```bash
# Create S3 bucket for state
aws s3 mb s3://smdh-terraform-state --region eu-west-2

# Enable versioning (for state recovery)
aws s3api put-bucket-versioning \
  --bucket smdh-terraform-state \
  --versioning-configuration Status=Enabled

# Block public access (security)
aws s3api put-public-access-block \
  --bucket smdh-terraform-state \
  --public-access-block-configuration \
  "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

# Create DynamoDB table for state locking
aws dynamodb create-table \
  --table-name smdh-terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5 \
  --region eu-west-2
```

- [ ] S3 bucket created: `smdh-terraform-state`
- [ ] Versioning enabled
- [ ] Public access blocked
- [ ] DynamoDB table created: `smdh-terraform-locks`

### Step 1.2: Initialize Terraform

```bash
cd infrastructure/terraform

# Initialize (downloads providers, sets up backend)
terraform init

# Verify backend connection
terraform state list  # Should be empty initially
```

- [ ] Terraform initialized successfully
- [ ] Backend configured (state in S3)
- [ ] State locking ready (DynamoDB)

### Step 1.3: Create Environment Configuration

```bash
# Copy example to actual config
cp environments/dev/terraform.tfvars.example environments/dev/terraform.tfvars

# Edit with your values
vim environments/dev/terraform.tfvars
```

**File: `environments/dev/terraform.tfvars`**
```hcl
# Project configuration
project_name = "smdh"
environment  = "dev"
aws_region   = "eu-west-2"

# Snowflake cross-account integration
snowflake_account_id  = "YOUR_SNOWFLAKE_ACCOUNT_ID"  # e.g., "xy12345"
snowflake_external_id = "550E8400-E29B-41D4-A716-446655440000"  # Generate with: uuidgen

# Kinesis configuration
kinesis_retention_hours = 24

# Enable monitoring
enable_monitoring = true

# Tenants to create
tenants = {
  test_tenant = {
    name       = "Test Tenant"
    num_sites  = 2
    contact_email = "admin@testtenant.com"
  }
}
```

- [ ] `terraform.tfvars` created in `environments/dev/`
- [ ] Snowflake account ID filled in
- [ ] External ID generated (use `uuidgen`)
- [ ] All required fields populated

### Step 1.4: Review Terraform Plan

```bash
# Generate plan (shows what will be created)
terraform plan -var-file=environments/dev/terraform.tfvars -out=tfplan

# Review the plan output carefully
# Should show: 63+ resources to be created
```

- [ ] Plan generated successfully
- [ ] Review shows expected resources (63+)
- [ ] No unexpected deletions
- [ ] No errors in plan

### Step 1.5: Apply Terraform Configuration

```bash
# Apply the plan (creates actual resources)
terraform apply tfplan

# This will take 5-10 minutes
# Watch for any errors during creation
```

- [ ] Terraform apply completed successfully
- [ ] No errors reported
- [ ] All 63+ resources created

### Step 1.6: Capture Terraform Outputs

```bash
# Get IoT endpoint (needed for Snowflake and testing)
terraform output -raw iot_endpoint
# Expected: xxx123xxx.iot.eu-west-2.amazonaws.com

# Get Kinesis stream name
terraform output -raw kinesis_stream_name
# Expected: smdh-sensor-data-stream

# Get Snowflake IAM role ARN (needed for Snowflake trust policy)
terraform output -raw snowflake_iam_role_arn
# Expected: arn:aws:iam::123456789012:role/smdh-snowflake-kinesis-role-dev

# Get Snowflake storage AWS IAM user ARN and external ID
terraform output snowflake_sync_data
# Save this for step 2.4
```

Save these values:
```
IoT Endpoint: ___________________
Kinesis Stream: smdh-sensor-data-stream
Snowflake Role ARN: ___________________
AWS IAM User ARN: ___________________
AWS External ID: ___________________
```

- [ ] IoT endpoint captured
- [ ] Kinesis stream name confirmed
- [ ] Snowflake role ARN saved
- [ ] AWS IAM user info saved

---

## ❄️ PHASE 2: SNOWFLAKE SETUP

### Step 2.1: Verify Snowflake Prerequisites

```bash
# Set environment variables
export SNOWFLAKE_ACCOUNT="xy12345"  # Your account ID
export SNOWFLAKE_USER="admin"
export SNOWFLAKE_REGION="eu-west-2"

# Test connection
snowsql -a $SNOWFLAKE_ACCOUNT -u $SNOWFLAKE_USER -q "SELECT CURRENT_ACCOUNT();"

# You should see your account ID
```

- [ ] Snowflake CLI working
- [ ] Connection to Snowflake successful
- [ ] Account ID verified

### Step 2.2: Create Admin Warehouse (if needed)

```bash
snowsql -a $SNOWFLAKE_ACCOUNT -u $SNOWFLAKE_USER \
  -q "CREATE WAREHOUSE IF NOT EXISTS smdh_admin_wh WITH WAREHOUSE_SIZE = 'SMALL' AUTO_SUSPEND = 600;"
```

- [ ] Admin warehouse created or already exists

### Step 2.3: Run Automatic Setup (Recommended)

```bash
cd infrastructure/snowflake

# Run complete setup (drops existing, creates fresh)
./validate_setup.sh test_tenant

# This runs:
# 1. Drop all existing objects
# 2. Create infrastructure database
# 3. Create shared resources (warehouses, roles)
# 4. Set up Openflow connector
# 5. Create test_tenant database and schema
# 6. Validate all objects

# Takes 5-10 minutes
```

- [ ] Setup script completed without errors
- [ ] Validation report shows all objects created

### Step 2.4: Create Openflow Deployment (Snowsight UI - One Time)

**Note:** Openflow Deployments and Runtimes cannot be created via SQL - this requires the Snowsight UI.

1. Open **Snowsight** → **Ingestion** → **Openflow**
2. Click **+ Create deployment**
3. Complete the wizard:
   - **Prerequisites**: Click Next
   - **Deployment location**: Select your region, click Next
   - **Configuration**:
     - **Name**: `smdh-openflow-deployment`
     - **Usage roles**: `OPENFLOW_ADMIN`
     - **Operate roles**: `OPENFLOW_ADMIN`, `OPENFLOW_RUNTIME_ROLE_KINESIS`
     - **Monitor roles**: `OPENFLOW_ADMIN`, `OPENFLOW_RUNTIME_ROLE_KINESIS`
4. Click **Create deployment**
5. **Wait 15-20 minutes** for deployment to become Active

- [ ] Deployment `smdh-openflow-deployment` created
- [ ] Deployment status: **Active** (wait 15-20 min)

### Step 2.5: Create Openflow Runtime (Snowsight UI - One Time)

1. In Snowsight → **Ingestion** → **Openflow** → **Runtimes** tab
2. Click **+ Create runtime**
3. Configure:
   - **Name**: `smdh-kinesis-runtime`
   - **Deployment**: `smdh-openflow-deployment`
   - **Role**: `OPENFLOW_RUNTIME_ROLE_KINESIS`
   - **Warehouse**: `SMDH_WH`
   - **External Access Integration**: `OPENFLOW_AWS_EAI`
4. Click **Create**
5. **Wait 5-10 minutes** for runtime to become Active

- [ ] Runtime `smdh-kinesis-runtime` created
- [ ] Runtime status: **Active** (wait 5-10 min)

### Step 2.6: Add Kinesis Connector (Snowsight UI - Per Tenant)

For each tenant, add a Kinesis connector:

1. In Snowsight → **Ingestion** → **Openflow** → **Runtimes**
2. Click on `smdh-kinesis-runtime`
3. Click **Add Connector** → **Amazon Kinesis**
4. Configure **Source**:

   | Field | Value |
   |-------|-------|
   | AWS Region | `eu-west-2` |
   | AWS Access Key ID | *(your AWS access key)* |
   | AWS Secret Access Key | *(your AWS secret key)* |
   | Stream Name | `smdh-test_tenant-stream` |
   | Application Name | `smdh-openflow-test_tenant` |
   | Initial Position | `LATEST` |
   | Message Format | `JSON` |

5. Configure **Destination**:

   | Field | Value |
   |-------|-------|
   | Database | `SMDH_TENANT_TEST_TENANT` |
   | Schema | `RAW` |
   | Role | `OPENFLOW_RUNTIME_ROLE_KINESIS` |
   | Warehouse | `SMDH_WH` |

6. Configure **Stream-to-Table Mapping**:
   ```
   smdh-test_tenant-stream:SENSOR_READINGS
   ```

7. Click **Create** → **Start**

- [ ] Kinesis connector created for test_tenant
- [ ] Connector status: **Running**

### Step 2.7: Configure Openflow Trust Relationship

After running the setup scripts (Step 2.3), Snowflake output will show:

```
STORAGE_AWS_IAM_USER_ARN: arn:aws:iam::...user/...
STORAGE_AWS_EXTERNAL_ID: 550e8400-e29b-41d4-a716-446655440000
```

These values go into the AWS IAM trust policy:

```bash
# Get the current Snowflake role
SNOWFLAKE_ROLE=$(terraform output -raw snowflake_iam_role_arn)

# Update trust policy with Snowflake credentials
# In AWS Console: IAM → Roles → smdh-snowflake-kinesis-role-dev
# Edit Trust Relationship, add Snowflake principal

# Or use AWS CLI:
aws iam update-assume-role-policy \
  --role-name smdh-snowflake-kinesis-role-dev \
  --policy-document file://trust-policy.json
```

Create file: `trust-policy.json`
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "SNOWFLAKE_IAM_USER_ARN_FROM_STEP_2_3"
      },
      "Action": "sts:AssumeRole",
      "Condition": {
        "StringEquals": {
          "sts:ExternalId": "SNOWFLAKE_EXTERNAL_ID_FROM_STEP_2_3"
        }
      }
    }
  ]
}
```

- [ ] Snowflake IAM user ARN captured
- [ ] AWS trust policy updated
- [ ] Snowflake can assume AWS role

### Step 2.8: Verify Snowflake Setup

```bash
# Check infrastructure database
snowsql -a $SNOWFLAKE_ACCOUNT -u $SNOWFLAKE_USER \
  -q "SHOW DATABASES LIKE 'smdh%';"

# Should show:
# - smdh_infrastructure (shared)
# - smdh_tenant_test_tenant (test tenant)

# Check warehouses
snowsql -a $SNOWFLAKE_ACCOUNT -u $SNOWFLAKE_USER \
  -q "SHOW WAREHOUSES LIKE 'smdh%';"

# Should show 5 warehouses

# Validate tenant
snowsql -a $SNOWFLAKE_ACCOUNT -u $SNOWFLAKE_USER \
  -f infrastructure/snowflake/scripts/validate_tenant.sql \
  -D tenant_id="test_tenant"
```

- [ ] smdh_infrastructure database exists
- [ ] smdh_tenant_test_tenant database exists
- [ ] All 5 warehouses created
- [ ] Validation passed for test_tenant

---

## 🧪 PHASE 3: TESTING & VALIDATION

### Step 3.1: Install Test Dependencies

```bash
cd ../../tests

# Install Python test requirements
pip install -r requirements.txt

# Install mosquitto tools (for MQTT testing)
brew install mosquitto  # macOS
# or: sudo apt-get install mosquitto-clients  # Linux
```

- [ ] Python dependencies installed
- [ ] mosquitto tools installed
- [ ] No pip errors

### Step 3.2: Extract Test Certificates

```bash
# Download AWS Root CA
./scripts/cert-helper.sh download-ca

# Extract certificates for test device
./scripts/cert-helper.sh extract-cert \
  -t test_tenant \
  -s site_001 \
  -d gw_001

# Verify certificates exist
ls -la certificates/test_tenant/site_001/
# Should show:
# - gw_001_certificate.pem
# - gw_001_private_key.pem
# - gw_001_public_key.pem
```

- [ ] AWS Root CA downloaded
- [ ] Test certificates extracted
- [ ] Certificate files exist and readable

### Step 3.3: Quick MQTT Connectivity Test

```bash
# Get your IoT endpoint
IOT_ENDPOINT=$(cd ../infrastructure/terraform && terraform output -raw iot_endpoint)

# Quick MQTT test
./scripts/mqtt-quick-test.sh \
  -e $IOT_ENDPOINT \
  -c certificates/test_tenant/site_001/gw_001_certificate.pem \
  -k certificates/test_tenant/site_001/gw_001_private_key.pem \
  -r certificates/ca/AmazonRootCA1.pem \
  -i smdh-gateway-test_tenant-site_001-gw_001

# Expected: "MQTT test successful" message
```

- [ ] MQTT connection successful
- [ ] No certificate errors
- [ ] Message published to IoT Core

### Step 3.4: Test IoT Transmission

```bash
# Send test data to IoT Core
python device-simulators/test-iot-transmission.py \
  --endpoint $IOT_ENDPOINT \
  --cert certificates/test_tenant/site_001/gw_001_certificate.pem \
  --key certificates/test_tenant/site_001/gw_001_private_key.pem \
  --ca certificates/ca/AmazonRootCA1.pem \
  --client-id smdh-gateway-test_tenant-site_001-gw_001 \
  --tenant-id test_tenant \
  --site-id site_001 \
  --mode single

# Expected: Message successfully published
# Check Kinesis:
aws kinesis describe-stream \
  --stream-name smdh-sensor-data-stream \
  --region eu-west-2
```

- [ ] Test message published successfully
- [ ] Kinesis stream shows activity (IncomingRecords > 0)

### Step 3.5: Verify Data in Snowflake

```bash
# Query Snowflake for the test data
snowsql -a $SNOWFLAKE_ACCOUNT -u $SNOWFLAKE_USER \
  -q "USE DATABASE smdh_tenant_test_tenant; SELECT COUNT(*) FROM RAW.SENSOR_READINGS WHERE timestamp > DATEADD(hour, -1, CURRENT_TIMESTAMP());"

# Should show records arriving
```

- [ ] Data visible in Snowflake
- [ ] Record count > 0
- [ ] Timestamp recent

### Step 3.6: Run Integration Tests (Optional)

```bash
# Run integration tests
pytest integration/test_stream_data_flow.py -v

# Expected: All tests pass
```

- [ ] Integration tests pass
- [ ] Data transformations work

---

## 📊 PHASE 4: VERIFICATION

### Step 4.1: CloudWatch Dashboard

```bash
# Get dashboard URL
cd ../infrastructure/terraform
terraform output cloudwatch_dashboard_url

# Open in browser, verify:
# - IoT metrics showing
# - Kinesis metrics showing
# - No alarms triggered
```

- [ ] Dashboard opens
- [ ] Metrics visible
- [ ] No critical alarms

### Step 4.2: AWS Console Verification

Visit AWS Console and verify:

- [ ] IoT Core
  - [ ] 10 Thing Types exist (LoRaWANGateway, NetworkServer, DevTankOSM, sensors)
  - [ ] 2 Things exist (gateways for 2 sites)
  - [ ] 2 Certificates attached to Things
  - [ ] 1 Policy created (smdh-policy-test_tenant)
  - [ ] 1 Rule created (routing to Kinesis)
  - [ ] Thing Groups hierarchy (tenant, site, dynamic groups)

- [ ] Kinesis
  - [ ] Stream exists: smdh-sensor-data-stream
  - [ ] Mode: ON_DEMAND
  - [ ] Incoming records > 0

- [ ] CloudWatch
  - [ ] Log group exists: /aws/iot/smdh
  - [ ] Recent log streams visible
  - [ ] Dashboard created

### Step 4.3: Snowflake Console Verification

```bash
# Connect to Snowflake console (web)

snowsql -a $SNOWFLAKE_ACCOUNT -u $SNOWFLAKE_USER \
  -q "SELECT * FROM smdh_infrastructure.tenant_configs.tenants;"

# Should show test_tenant registered
```

- [ ] smdh_infrastructure database visible
- [ ] test_tenant registered
- [ ] All 5 warehouses created and running

### Step 4.4: Create Deployment Record

```bash
# Create DEPLOYMENT_NOTES.md with results
cat > infrastructure/DEPLOYMENT_NOTES_LATEST.md <<EOF
# SMDH Deployment Record

**Date:** $(date)
**Environment:** dev
**Status:** ✅ Successful

## AWS Resources Created
- IoT Core endpoint: $(cd infrastructure/terraform && terraform output -raw iot_endpoint)
- Kinesis stream: smdh-sensor-data-stream
- CloudWatch dashboard: smdh-platform-dev

## Snowflake Setup
- Infrastructure database: smdh_infrastructure
- Tenant databases: smdh_tenant_test_tenant
- Warehouses: 5 (admin, streaming, etl, analytics, dev)

## Next Steps
- Proceed to Phase 2: Deploy Streamlit web portal
- Run daily validation: ./infrastructure/snowflake/validate_setup.sh test_tenant
EOF
```

- [ ] Deployment record created
- [ ] All outputs captured
- [ ] Handover to development team

---

## ✅ POST-DEPLOYMENT

### Daily Operations

```bash
# Daily health check
cd infrastructure/snowflake
./scripts/cert-helper.sh  # Verify certificates

# Check Snowflake health
snowsql -a $SNOWFLAKE_ACCOUNT -u $SNOWFLAKE_USER \
  -q "CALL smdh_tenant_test_tenant.analytics.sp_health_check();"

# Monitor costs
snowsql -a $SNOWFLAKE_ACCOUNT -u $SNOWFLAKE_USER \
  -q "SELECT * FROM smdh_tenant_test_tenant.analytics.v_cost_monitoring LIMIT 10;"
```

### Weekly Tasks

- [ ] Review CloudWatch alarms
- [ ] Check data freshness (Snowflake)
- [ ] Verify no cost anomalies
- [ ] Review failed tasks (if any)

### Monthly Tasks

- [ ] Analyze performance metrics
- [ ] Evaluate warehouse sizing
- [ ] Plan capacity for next period
- [ ] Archive or delete old test data

---

## 🆘 Troubleshooting

### Terraform Issues

**Problem:** "Error acquiring the lock"
**Solution:** Wait 5 minutes and retry (lock expires)

**Problem:** "Provider version constraints not satisfied"
**Solution:** Run `terraform init -upgrade`

### Snowflake Issues

**Problem:** "SnowSQL: command not found"
**Solution:** Install SnowSQL from https://docs.snowflake.com/en/user-guide/snowsql-install-config.html

**Problem:** "Error: 'DYNAMIC_TABLES' feature not enabled"
**Solution:** Upgrade to Enterprise edition (required)

### IoT Core Issues

**Problem:** "MQTT connection refused"
**Solution:**
1. Verify endpoint correct: `aws iot describe-endpoint --endpoint-type iot:Data-ATS`
2. Verify certificate permissions: `chmod 600 private_key.pem`
3. Verify certificate attached to thing: AWS Console → IoT Core → Things

### Kinesis Issues

**Problem:** "No data in stream"
**Solution:**
1. Check IoT Rule: AWS Console → IoT Core → Rules
2. Verify rule is enabled and targeting correct stream
3. Check CloudWatch Logs for IoT errors

---

## 📚 Additional Resources

- [Terraform README](infrastructure/terraform/README.md)
- [Snowflake Setup Guide](infrastructure/snowflake/README.md)
- [Testing Guide](tests/README.md)
- [Troubleshooting Guide](KNOWN_LIMITATIONS.md)
- [Architecture Decisions](ARCHITECTURE_DECISION_RECORD.md)

---

## Success Criteria

✅ Deployment successful if all these are true:

1. ✅ All 63 AWS resources created
2. ✅ Snowflake smdh_infrastructure database exists
3. ✅ Test tenant database created (smdh_tenant_test_tenant)
4. ✅ MQTT connection test passes
5. ✅ Data flows: IoT Core → Kinesis → Snowflake
6. ✅ CloudWatch dashboard shows metrics
7. ✅ No critical alarms triggered
8. ✅ Snowflake health check passes
9. ✅ Integration tests pass (if run)

---

**Deployment Checklist Version:** 1.2
**Last Updated:** December 3, 2025
**Maintainer:** Platform Team
