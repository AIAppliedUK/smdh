# SMDH Terraform Infrastructure

This directory contains the complete Infrastructure as Code (IaC) for the Smart Manufacturing Data Hub (SMDH) platform using Terraform.

## 📁 Directory Structure

```
terraform/
├── main.tf                 # Root configuration orchestrating all modules
├── providers.tf            # AWS provider and backend configuration
├── variables.tf            # Input variable definitions
├── outputs.tf              # Output value definitions
├── README.md              # This file
├── modules/               # Reusable Terraform modules
│   ├── iot-core/          # AWS IoT Core resources
│   ├── kinesis/           # Kinesis Data Streams
│   ├── iam/               # IAM roles for Snowflake integration
│   ├── secrets-manager/   # Secrets Manager for credentials
│   ├── cloudwatch/        # Monitoring and alerting
│   └── tenant/            # Per-tenant resources
└── environments/          # Environment-specific configurations
    ├── dev/
    │   └── terraform.tfvars.example
    ├── staging/
    │   └── terraform.tfvars.example
    └── prod/
        └── terraform.tfvars.example
```

## 🚀 Quick Start

### Prerequisites

1. **Install Terraform** (v1.0+)
   ```bash
   brew install terraform  # macOS
   # or download from https://www.terraform.io/downloads
   ```

2. **Configure AWS CLI**
   ```bash
   aws configure
   # Enter your AWS Access Key ID, Secret Access Key, and region (eu-west-2)
   ```

3. **Create S3 Backend** (for state storage)
   ```bash
   aws s3 mb s3://smdh-terraform-state --region eu-west-2
   aws dynamodb create-table \
     --table-name smdh-terraform-locks \
     --attribute-definitions AttributeName=LockID,AttributeType=S \
     --key-schema AttributeName=LockID,KeyType=HASH \
     --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5 \
     --region eu-west-2
   ```

### Initial Setup

1. **Copy environment configuration**
   ```bash
   cd infrastructure/terraform
   cp environments/dev/terraform.tfvars.example environments/dev/terraform.tfvars
   ```

2. **Edit configuration**
   ```bash
   # Update environments/dev/terraform.tfvars with your values
   vim environments/dev/terraform.tfvars
   ```

3. **Initialize Terraform**
   ```bash
   terraform init
   ```

4. **Review the plan**
   ```bash
   terraform plan -var-file=environments/dev/terraform.tfvars
   ```

5. **Apply configuration**
   ```bash
   terraform apply -var-file=environments/dev/terraform.tfvars
   ```

## 🔧 Module Overview

### IoT Core Module
Creates AWS IoT Core resources:
- Thing Types (LoRaWAN Gateway, DevTank OSM)
- IAM roles for IoT logging and Kinesis integration
- IoT endpoint configuration

### Kinesis Module
Creates Kinesis Data Stream:
- On-demand capacity mode (auto-scaling)
- Encryption at rest
- CloudWatch alarms for monitoring

### IAM Module
Creates IAM roles:
- Snowflake cross-account role for Kinesis access
- Optional Lambda execution role

### Secrets Manager Module
Manages sensitive credentials:
- Snowflake private key storage
- Snowflake configuration

### CloudWatch Module
Monitoring and alerting:
- Log groups for IoT Core
- CloudWatch dashboard
- SNS topics for alarms
- Pre-configured alarms

### Tenant Module
Per-tenant resources (created for each tenant):
- **Thing Groups** (hierarchical device management)
  - Tenant-level group (all devices)
  - Site-level groups (devices per location)
  - Dynamic groups (disconnected, active)
- **Billing Groups** (cost tracking per tenant)
- IoT Things (gateways/devices)
- X.509 certificates
- IoT Policies with topic isolation
- IoT Rules Engine rules
- SNS topics for alerts
- CloudWatch alarms

## 📝 Adding a New Tenant

1. **Edit terraform.tfvars**
   ```hcl
   tenants = {
     existing_tenant = {
       name = "Existing Tenant"
       num_sites = 5
     }

     new_tenant = {
       name             = "New Tenant Company Ltd"
       num_sites        = 3
       retention_days   = 730
       warehouse_size   = "SMALL"
       contact_email    = "alerts@newtenant.com"
       sensors_per_site = 8
     }
   }
   ```

2. **Apply changes**
   ```bash
   terraform plan -var-file=environments/prod/terraform.tfvars
   terraform apply -var-file=environments/prod/terraform.tfvars
   ```

3. **Retrieve certificates**
   ```bash
   # Certificates are in Terraform outputs (sensitive)
   terraform output -json tenant_certificate_arns
   ```

## 🏗️ Thing Groups & Billing Groups

### Overview

AWS IoT Thing Groups and Billing Groups provide hierarchical device management and cost tracking:

```
smdh-tenant-company_a (Tenant Thing Group)
├── smdh-company_a-site_001 (Site Thing Group)
│   ├── smdh-gateway-company_a-site_001-gw_001 (Device)
│   └── smdh-gateway-company_a-site_001-gw_002 (Device)
├── smdh-company_a-site_002 (Site Thing Group)
│   └── smdh-gateway-company_a-site_002-gw_001 (Device)
├── Dynamic Groups:
│   ├── smdh-company_a-disconnected (Auto-tracks offline devices)
│   └── smdh-company_a-active (Auto-tracks active devices)
└── smdh-billing-company_a (Billing Group for cost tracking)
```

### Viewing Thing Group Hierarchy

```bash
# See complete hierarchy
terraform output thing_group_hierarchy

# Example output:
# {
#   "company_a": {
#     "tenant_group": "smdh-tenant-company_a",
#     "site_groups": {
#       "site_001": "smdh-company_a-site_001",
#       "site_002": "smdh-company_a-site_002"
#     },
#     "dynamic_groups": {
#       "disconnected": "smdh-company_a-disconnected",
#       "active": "smdh-company_a-active"
#     }
#   }
# }
```

### Querying Devices Using Thing Groups

```bash
# List all devices for a tenant (recursive includes all site groups)
TENANT_GROUP=$(terraform output -json thing_group_hierarchy | jq -r '.company_a.tenant_group')
aws iot list-things-in-thing-group \
  --thing-group-name "$TENANT_GROUP" \
  --recursive \
  --region eu-west-2

# List devices at a specific site
SITE_GROUP=$(terraform output -json thing_group_hierarchy | jq -r '.company_a.site_groups.site_001')
aws iot list-things-in-thing-group \
  --thing-group-name "$SITE_GROUP" \
  --region eu-west-2

# Check disconnected devices (uses dynamic group)
DISCONNECTED=$(terraform output -json thing_group_hierarchy | jq -r '.company_a.dynamic_groups.disconnected')
aws iot list-things-in-thing-group \
  --thing-group-name "$DISCONNECTED" \
  --region eu-west-2
```

### Cost Tracking with Billing Groups

```bash
# View billing groups
terraform output billing_groups

# Check costs using the billing group
cd ../scripts
./check_iot_costs.sh --tenant-id company_a --period 30

# Export cost report to CSV
./check_iot_costs.sh --tenant-id company_a --period 30 --export-csv company_a_costs.csv
```

### Health Monitoring with Thing Groups

```bash
# Check system health (leverages thing groups)
cd ../scripts
./check_system_health.sh --tenant-id company_a

# Check specific site health
./check_system_health.sh --tenant-id company_a --site-id site_001 --verbose

# Health check returns:
# - 0 (Healthy): ≥85% health score
# - 1 (Degraded): 60-84% health score
# - 2 (Critical): <60% health score
```

### Syncing to Snowflake

Terraform outputs include structured data for syncing to Snowflake:

```bash
# View Snowflake sync data
terraform output snowflake_sync_data

# Run sync script
cd ../snowflake/scripts
./sync_aws_iot_metadata.sh --tenant-id company_a

# Query in Snowflake
snowsql -q "SELECT * FROM smdh_infrastructure.monitoring.v_thing_group_hierarchy WHERE tenant_id = 'company_a';"
```

### Ready-to-Use Commands

Terraform provides pre-configured commands:

```bash
# Get all monitoring commands
terraform output monitoring_commands

# Output includes:
# - check_health: System health checks
# - check_costs: Cost tracking
# - sync_to_snowflake: Snowflake metadata sync
# - list_thing_groups: List all thing groups
# - list_billing_groups: List all billing groups

# Get tenant-specific AWS CLI queries
terraform output thing_group_queries

# Output includes ready-to-run AWS CLI commands for:
# - Listing all devices for a tenant
# - Checking disconnected devices
# - Querying billing group memberships
```

### Bulk Operations on Sites

```bash
# Example: Update firmware for all devices at a site
SITE_GROUP="smdh-company_a-site_001"
DEVICES=$(aws iot list-things-in-thing-group --thing-group-name "$SITE_GROUP" --query 'things' --output text)

for device in $DEVICES; do
  echo "Updating $device..."
  # Update firmware, rotate certificates, etc.
done
```

### Dynamic Group Usage

Dynamic groups automatically track device states:

```bash
# Get disconnected devices (updates automatically)
DISCONNECTED_GROUP=$(terraform output -json thing_group_hierarchy | jq -r '.company_a.dynamic_groups.disconnected')
aws iot list-things-in-thing-group --thing-group-name "$DISCONNECTED_GROUP" --region eu-west-2

# Get recently active devices
ACTIVE_GROUP=$(terraform output -json thing_group_hierarchy | jq -r '.company_a.dynamic_groups.active')
aws iot list-things-in-thing-group --thing-group-name "$ACTIVE_GROUP" --region eu-west-2
```

For more details, see:
- [Thing Groups Guide](THING_GROUPS_GUIDE.md) - Comprehensive usage guide
- [Monitoring Scripts README](../scripts/README.md) - Health check and cost tracking scripts

## 🔐 Security Considerations

### Snowflake Configuration

You must configure Snowflake account ID and external ID:

1. **Get Snowflake AWS Account ID**
   - Contact Snowflake support or check documentation
   - This is the AWS account that Snowflake uses for cross-account access

2. **Generate External ID**
   ```bash
   # Generate a secure random external ID
   uuidgen
   # Example output: 550E8400-E29B-41D4-A716-446655440000
   ```

3. **Update terraform.tfvars**
   ```hcl
   snowflake_account_id  = "123456789012"  # From Snowflake
   snowflake_external_id = "550E8400-E29B-41D4-A716-446655440000"  # Your generated UUID
   ```

4. **Configure Snowflake to trust the IAM role**
   - After applying Terraform, get the IAM role ARN from outputs
   - Configure this in Snowflake Openflow connector

### Certificate Management

- **Certificates are generated automatically** by Terraform
- **Private keys are stored in Terraform state** (sensitive)
- **Extract certificates after deployment**:
  ```bash
  terraform output -json tenant_certificate_pems > certificates.json
  ```
- **Deploy to devices securely** (see deployment guides)

## 📊 Monitoring

### CloudWatch Dashboard

After deployment, access the dashboard:
```bash
terraform output cloudwatch_dashboard_url
```

### View Alarms

```bash
aws cloudwatch describe-alarms \
  --alarm-name-prefix "smdh" \
  --region eu-west-2
```

## 🧪 Testing

### Verify IoT Endpoint

```bash
terraform output iot_endpoint
# Test with MQTT client or AWS IoT test console
```

### Verify Kinesis Stream

```bash
aws kinesis describe-stream \
  --stream-name $(terraform output -raw kinesis_stream_name) \
  --region eu-west-2
```

### Test MQTT Publishing

```bash
# Get IoT endpoint
IOT_ENDPOINT=$(terraform output -raw iot_endpoint)

# Publish test message
aws iot-data publish \
  --topic "smdh/test_tenant/site_001/sensor-data" \
  --payload '{"temperature":22.5,"timestamp":"2024-11-21T10:00:00Z"}' \
  --region eu-west-2
```

## 🔄 State Management

### Backend Configuration

State is stored in S3 with DynamoDB locking:
- **Bucket**: `smdh-terraform-state`
- **Lock table**: `smdh-terraform-locks`
- **Encryption**: Enabled

### State Commands

```bash
# Show current state
terraform show

# List resources
terraform state list

# View specific resource
terraform state show module.iot_core.aws_iot_thing_type.lorawan_gateway
```

## 🗑️ Cleanup (Development Only)

**⚠️ WARNING: This will destroy all infrastructure**

```bash
terraform destroy -var-file=environments/dev/terraform.tfvars
```

## 📚 Additional Resources

### SMDH Documentation
- [SMDH Architecture Documentation](../../docs/detailed-design/SMDH%20AWS%20design.md)
- [Implementation Guide](../SMDH_Infrastructure_Implementation.md)
- [Implementation Plan](../SMDH_Implementation_Plan.md)

### Thing Groups & Monitoring
- **[Thing Groups Guide](THING_GROUPS_GUIDE.md)** - Comprehensive AWS IoT Thing Groups usage
- **[Monitoring Scripts README](../scripts/README.md)** - Health checks and cost tracking
- **[Snowflake Integration](../snowflake/README.md)** - Syncing AWS state to Snowflake

### External Documentation
- [Terraform AWS Provider Docs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [AWS IoT Thing Groups](https://docs.aws.amazon.com/iot/latest/developerguide/thing-groups.html)
- [AWS IoT Billing Groups](https://docs.aws.amazon.com/iot/latest/developerguide/billing-groups.html)

## 🆘 Troubleshooting

### Issue: Backend initialization fails

```bash
# Verify S3 bucket exists
aws s3 ls s3://smdh-terraform-state

# Verify DynamoDB table exists
aws dynamodb describe-table --table-name smdh-terraform-locks
```

### Issue: Snowflake role trust fails

- Verify `snowflake_account_id` is correct
- Ensure `snowflake_external_id` matches what's configured in Snowflake
- Check IAM role trust policy in AWS Console

### Issue: Certificate generation fails

- Ensure IoT Core service is available in your region
- Check IAM permissions for certificate creation
- Verify Thing Type exists before creating Things

## 📞 Support

For issues or questions:
- Review [Implementation Plan](../SMDH_Implementation_Plan.md)
- Check AWS IoT Core service status
- Verify Terraform version compatibility

---

**Maintained by**: Platform Team
**Last Updated**: 2025-11-21
**Version**: 2.0 (with Thing Groups & Billing Groups)
