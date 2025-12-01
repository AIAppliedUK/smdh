 SMDH Terraform Infrastructure

This directory contains the complete Infrastructure as Code (IaC) for the Smart Manufacturing Data Hub (SMDH) platform using Terraform.

  Directory Structure

```
terraform/
 main.tf                  Root configuration orchestrating all modules
 providers.tf             AWS provider and backend configuration
 variables.tf             Input variable definitions
 outputs.tf               Output value definitions
 README.md               This file
 modules/                Reusable Terraform modules
    iot-core/           AWS IoT Core resources
    kinesis/            Kinesis Data Streams
    iam/                IAM roles for Snowflake integration
    secrets-manager/    Secrets Manager for credentials
    cloudwatch/         Monitoring and alerting
    tenant/             Per-tenant resources
 environments/           Environment-specific configurations
     dev/
        terraform.tfvars.example
     staging/
        terraform.tfvars.example
     prod/
         terraform.tfvars.example
```

  Quick Start

 Prerequisites

. Install Terraform (v.+)
   ```bash
   brew install terraform   macOS
    or download from https://www.terraform.io/downloads
   ```

. Configure AWS CLI
   ```bash
   aws configure
    Enter your AWS Access Key ID, Secret Access Key, and region (eu-west-)
   ```

. Create S Backend (for state storage)
   ```bash
   aws s mb s://smdh-terraform-state --region eu-west-
   aws dynamodb create-table \
     --table-name smdh-terraform-locks \
     --attribute-definitions AttributeName=LockID,AttributeType=S \
     --key-schema AttributeName=LockID,KeyType=HASH \
     --provisioned-throughput ReadCapacityUnits=,WriteCapacityUnits= \
     --region eu-west-
   ```

 Initial Setup

. Copy environment configuration
   ```bash
   cd infrastructure/terraform
   cp environments/dev/terraform.tfvars.example environments/dev/terraform.tfvars
   ```

. Edit configuration
   ```bash
    Update environments/dev/terraform.tfvars with your values
   vim environments/dev/terraform.tfvars
   ```

. Initialize Terraform
   ```bash
   terraform init
   ```

. Review the plan
   ```bash
   terraform plan -var-file=environments/dev/terraform.tfvars
   ```

. Apply configuration
   ```bash
   terraform apply -var-file=environments/dev/terraform.tfvars
   ```

  Module Overview

 IoT Core Module
Creates AWS IoT Core resources:
- Thing Types (LoRaWAN Gateway, DevTank OSM)
- IAM roles for IoT logging and Kinesis integration
- IoT endpoint configuration

 Kinesis Module
Creates Kinesis Data Stream:
- On-demand capacity mode (auto-scaling)
- Encryption at rest
- CloudWatch alarms for monitoring

 IAM Module
Creates IAM roles:
- Snowflake cross-account role for Kinesis access
- Optional Lambda execution role

 Secrets Manager Module
Manages sensitive credentials:
- Snowflake private key storage
- Snowflake configuration

 CloudWatch Module
Monitoring and alerting:
- Log groups for IoT Core
- CloudWatch dashboard
- SNS topics for alarms
- Pre-configured alarms

 Tenant Module
Per-tenant resources (created for each tenant):
- Thing Groups (hierarchical device management)
  - Tenant-level group (all devices)
  - Site-level groups (devices per location)
  - Dynamic groups (disconnected, active)
- Billing Groups (cost tracking per tenant)
- IoT Things (gateways/devices)
- X. certificates
- IoT Policies with topic isolation
- IoT Rules Engine rules
- SNS topics for alerts
- CloudWatch alarms

  Adding a New Tenant

. Edit terraform.tfvars
   ```hcl
   tenants = {
     existing_tenant = {
       name = "Existing Tenant"
       num_sites = 
     }

     new_tenant = {
       name             = "New Tenant Company Ltd"
       num_sites        = 
       retention_days   = 
       warehouse_size   = "SMALL"
       contact_email    = "alerts@newtenant.com"
       sensors_per_site = 
     }
   }
   ```

. Apply changes
   ```bash
   terraform plan -var-file=environments/prod/terraform.tfvars
   terraform apply -var-file=environments/prod/terraform.tfvars
   ```

. Retrieve certificates
   ```bash
    Certificates are in Terraform outputs (sensitive)
   terraform output -json tenant_certificate_arns
   ```

  Thing Groups & Billing Groups

 Overview

AWS IoT Thing Groups and Billing Groups provide hierarchical device management and cost tracking:

```
smdh-tenant-company_a (Tenant Thing Group)
 smdh-company_a-site_ (Site Thing Group)
    smdh-gateway-company_a-site_-gw_ (Device)
    smdh-gateway-company_a-site_-gw_ (Device)
 smdh-company_a-site_ (Site Thing Group)
    smdh-gateway-company_a-site_-gw_ (Device)
 Dynamic Groups:
    smdh-company_a-disconnected (Auto-tracks offline devices)
    smdh-company_a-active (Auto-tracks active devices)
 smdh-billing-company_a (Billing Group for cost tracking)
```

 Viewing Thing Group Hierarchy

```bash
 See complete hierarchy
terraform output thing_group_hierarchy

 Example output:
 {
   "company_a": {
     "tenant_group": "smdh-tenant-company_a",
     "site_groups": {
       "site_": "smdh-company_a-site_",
       "site_": "smdh-company_a-site_"
     },
     "dynamic_groups": {
       "disconnected": "smdh-company_a-disconnected",
       "active": "smdh-company_a-active"
     }
   }
 }
```

 Querying Devices Using Thing Groups

```bash
 List all devices for a tenant (recursive includes all site groups)
TENANT_GROUP=$(terraform output -json thing_group_hierarchy | jq -r '.company_a.tenant_group')
aws iot list-things-in-thing-group \
  --thing-group-name "$TENANT_GROUP" \
  --recursive \
  --region eu-west-

 List devices at a specific site
SITE_GROUP=$(terraform output -json thing_group_hierarchy | jq -r '.company_a.site_groups.site_')
aws iot list-things-in-thing-group \
  --thing-group-name "$SITE_GROUP" \
  --region eu-west-

 Check disconnected devices (uses dynamic group)
DISCONNECTED=$(terraform output -json thing_group_hierarchy | jq -r '.company_a.dynamic_groups.disconnected')
aws iot list-things-in-thing-group \
  --thing-group-name "$DISCONNECTED" \
  --region eu-west-
```

 Cost Tracking with Billing Groups

```bash
 View billing groups
terraform output billing_groups

 Check costs using the billing group
cd ../scripts
./check_iot_costs.sh --tenant-id company_a --period 

 Export cost report to CSV
./check_iot_costs.sh --tenant-id company_a --period  --export-csv company_a_costs.csv
```

 Health Monitoring with Thing Groups

```bash
 Check system health (leverages thing groups)
cd ../scripts
./check_system_health.sh --tenant-id company_a

 Check specific site health
./check_system_health.sh --tenant-id company_a --site-id site_ --verbose

 Health check returns:
 -  (Healthy): ≥% health score
 -  (Degraded): -% health score
 -  (Critical): <% health score
```

 Syncing to Snowflake

Terraform outputs include structured data for syncing to Snowflake:

```bash
 View Snowflake sync data
terraform output snowflake_sync_data

 Run sync script
cd ../snowflake/scripts
./sync_aws_iot_metadata.sh --tenant-id company_a

 Query in Snowflake
snowsql -q "SELECT  FROM smdh_infrastructure.monitoring.v_thing_group_hierarchy WHERE tenant_id = 'company_a';"
```

 Ready-to-Use Commands

Terraform provides pre-configured commands:

```bash
 Get all monitoring commands
terraform output monitoring_commands

 Output includes:
 - check_health: System health checks
 - check_costs: Cost tracking
 - sync_to_snowflake: Snowflake metadata sync
 - list_thing_groups: List all thing groups
 - list_billing_groups: List all billing groups

 Get tenant-specific AWS CLI queries
terraform output thing_group_queries

 Output includes ready-to-run AWS CLI commands for:
 - Listing all devices for a tenant
 - Checking disconnected devices
 - Querying billing group memberships
```

 Bulk Operations on Sites

```bash
 Example: Update firmware for all devices at a site
SITE_GROUP="smdh-company_a-site_"
DEVICES=$(aws iot list-things-in-thing-group --thing-group-name "$SITE_GROUP" --query 'things' --output text)

for device in $DEVICES; do
  echo "Updating $device..."
   Update firmware, rotate certificates, etc.
done
```

 Dynamic Group Usage

Dynamic groups automatically track device states:

```bash
 Get disconnected devices (updates automatically)
DISCONNECTED_GROUP=$(terraform output -json thing_group_hierarchy | jq -r '.company_a.dynamic_groups.disconnected')
aws iot list-things-in-thing-group --thing-group-name "$DISCONNECTED_GROUP" --region eu-west-

 Get recently active devices
ACTIVE_GROUP=$(terraform output -json thing_group_hierarchy | jq -r '.company_a.dynamic_groups.active')
aws iot list-things-in-thing-group --thing-group-name "$ACTIVE_GROUP" --region eu-west-
```

For more details, see:
- [Thing Groups Guide](THING_GROUPS_GUIDE.md) - Comprehensive usage guide
- [Monitoring Scripts README](../scripts/README.md) - Health check and cost tracking scripts

  Security Considerations

 Snowflake Configuration

You must configure Snowflake account ID and external ID:

. Get Snowflake AWS Account ID
   - Contact Snowflake support or check documentation
   - This is the AWS account that Snowflake uses for cross-account access

. Generate External ID
   ```bash
    Generate a secure random external ID
   uuidgen
    Example output: E-EB-D-A-
   ```

. Update terraform.tfvars
   ```hcl
   snowflake_account_id  = ""   From Snowflake
   snowflake_external_id = "E-EB-D-A-"   Your generated UUID
   ```

. Configure Snowflake to trust the IAM role
   - After applying Terraform, get the IAM role ARN from outputs
   - Configure this in Snowflake Openflow connector

 Certificate Management

- Certificates are generated automatically by Terraform
- Private keys are stored in Terraform state (sensitive)
- Extract certificates after deployment:
  ```bash
  terraform output -json tenant_certificate_pems > certificates.json
  ```
- Deploy to devices securely (see deployment guides)

  Monitoring

 CloudWatch Dashboard

After deployment, access the dashboard:
```bash
terraform output cloudwatch_dashboard_url
```

 View Alarms

```bash
aws cloudwatch describe-alarms \
  --alarm-name-prefix "smdh" \
  --region eu-west-
```

  Testing

 Verify IoT Endpoint

```bash
terraform output iot_endpoint
 Test with MQTT client or AWS IoT test console
```

 Verify Kinesis Stream

```bash
aws kinesis describe-stream \
  --stream-name $(terraform output -raw kinesis_stream_name) \
  --region eu-west-
```

 Test MQTT Publishing

```bash
 Get IoT endpoint
IOT_ENDPOINT=$(terraform output -raw iot_endpoint)

 Publish test message
aws iot-data publish \
  --topic "smdh/test_tenant/site_/sensor-data" \
  --payload '{"temperature":.,"timestamp":"--T::Z"}' \
  --region eu-west-
```

  State Management

 Backend Configuration

State is stored in S with DynamoDB locking:
- Bucket: `smdh-terraform-state`
- Lock table: `smdh-terraform-locks`
- Encryption: Enabled

 State Commands

```bash
 Show current state
terraform show

 List resources
terraform state list

 View specific resource
terraform state show module.iot_core.aws_iot_thing_type.lorawan_gateway
```

  Cleanup (Development Only)

 WARNING: This will destroy all infrastructure

```bash
terraform destroy -var-file=environments/dev/terraform.tfvars
```

  Additional Resources

 SMDH Documentation
- [SMDH Architecture Documentation](../../docs/detailed-design/SMDH%AWS%design.md)
- [Implementation Guide](../SMDH_Infrastructure_Implementation.md)
- [Implementation Plan](../SMDH_Implementation_Plan.md)

 Thing Groups & Monitoring
- [Thing Groups Guide](THING_GROUPS_GUIDE.md) - Comprehensive AWS IoT Thing Groups usage
- [Monitoring Scripts README](../scripts/README.md) - Health checks and cost tracking
- [Snowflake Integration](../snowflake/README.md) - Syncing AWS state to Snowflake

 External Documentation
- [Terraform AWS Provider Docs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [AWS IoT Thing Groups](https://docs.aws.amazon.com/iot/latest/developerguide/thing-groups.html)
- [AWS IoT Billing Groups](https://docs.aws.amazon.com/iot/latest/developerguide/billing-groups.html)

  Troubleshooting

 Issue: Backend initialization fails

```bash
 Verify S bucket exists
aws s ls s://smdh-terraform-state

 Verify DynamoDB table exists
aws dynamodb describe-table --table-name smdh-terraform-locks
```

 Issue: Snowflake role trust fails

- Verify `snowflake_account_id` is correct
- Ensure `snowflake_external_id` matches what's configured in Snowflake
- Check IAM role trust policy in AWS Console

 Issue: Certificate generation fails

- Ensure IoT Core service is available in your region
- Check IAM permissions for certificate creation
- Verify Thing Type exists before creating Things

  Support

For issues or questions:
- Review [Implementation Plan](../SMDH_Implementation_Plan.md)
- Check AWS IoT Core service status
- Verify Terraform version compatibility

---

Maintained by: Platform Team
Last Updated: --
Version: . (with Thing Groups & Billing Groups)
