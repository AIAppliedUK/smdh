SMDH Terraform Infrastructure - Complete

Summary

Terraform Modules ( modules)

IoT Core Module ([terraform/modules/iot-core/](terraform/modules/iot-core/))

- Thing Types for LoRaWAN Gateways and DevTank OSM devices
- IAM roles for IoT logging and Kinesis integration
- Automatic IoT endpoint discovery
- Files: main.tf, variables.tf, outputs.tf

  Kinesis Module ([terraform/modules/kinesis/](terraform/modules/kinesis/))

- On-demand Kinesis Data Stream
- KMS encryption at rest
- CloudWatch alarms for iterator age and throughput
- Files: main.tf, variables.tf, outputs.tf

  IAM Module ([terraform/modules/iam/](terraform/modules/iam/))

- Cross-account role for Snowflake (Openflow connector)
- External ID security for role assumption
- Kinesis read permissions
- Optional Lambda execution role
- Files: main.tf, variables.tf, outputs.tf

  Secrets Manager Module ([terraform/modules/secrets-manager/](terraform/modules/secrets-manager/))

- Snowflake private key storage
- Snowflake configuration secret
- Optional automatic rotation support
- Files: main.tf, variables.tf, outputs.tf

  CloudWatch Module ([terraform/modules/cloudwatch/](terraform/modules/cloudwatch/))

- IoT Core log group with retention
- Platform monitoring dashboard
- SNS topic for alarms
- Pre-configured alarms (connection failures, publish failures, no data)
- Files: main.tf, variables.tf, outputs.tf

  Tenant Module ([terraform/modules/tenant/](terraform/modules/tenant/))

- Most Complex Module - Creates all per-tenant resources:
  - IoT Things (gateways) for each site
  - X. certificates (automatically generated)
  - IoT Policy with strict topic isolation
  - IoT Rules Engine rule to route to Kinesis
  - SNS topic for tenant-specific alerts
  - CloudWatch alarms per tenant
- Files: main.tf, variables.tf, outputs.tf

. Root Configuration

Main Configuration ([terraform/](terraform/))

- main.tf - Orchestrates all modules
- providers.tf - AWS provider with S backend
- variables.tf - Complete variable definitions with validation
- outputs.tf - Comprehensive outputs including sensitive data
- .gitignore - Protects sensitive files from git

. Environment Configurations

Development Environment ([terraform/environments/dev/](terraform/environments/dev/))

- terraform.tfvars.example with dev settings
- Lower retention periods
- Test tenant configuration
- Deletion protection disabled

  Production Environment ([terraform/environments/prod/](terraform/environments/prod/))

- terraform.tfvars.example with production settings
- Standard retention periods
- Multiple tenant examples
- Deletion protection enabled

. Documentation

Comprehensive README ([terraform/README.md](terraform/README.md))

- Quick start guide
- Module overview
- Adding new tenants
- Security considerations
- Testing procedures
- Troubleshooting guide

  Key Features

Multi-Tenancy

- Complete Isolation: Each tenant has separate IoT policies, certificates, topics, and SNS alerts
- Automatic Scaling: Add tenants by just adding them to `terraform.tfvars`
- Topic Isolation: IoT policies enforce `smdh/{tenant_id}/` topic restrictions

Security

- X. Certificates: Automatically generated for each gateway
- External ID: Required for Snowflake cross-account role trust
- Encryption: KMS encryption for Kinesis and Secrets Manager
- Least Privilege: IAM policies follow principle of least privilege

Monitoring

- CloudWatch Dashboard: Real-time metrics for IoT and Kinesis
- Alarms: Pre-configured alarms for failures and anomalies
- Per-Tenant Alerts: SNS topics route to tenant contact emails
- Comprehensive Logging: All IoT activity logged to CloudWatch

Operational Excellence

- State Management: S backend with DynamoDB locking
- Idempotent: Safe to re-apply without data loss
- Modular: Each component can be updated independently
- Validated Variables: Input validation prevents configuration errors

  Resource Count

When deployed with tenant ( sites):

| Resource Type        | Count | Purpose                         |
| -------------------- | ----- | ------------------------------- |
| IoT Thing Types      |       | LoRaWAN + DevTank               |
| IoT Things           |       | One per site                    |
| IoT Certificates     |       | One per gateway                 |
| IoT Policies         |       | Per tenant                      |
| IoT Rules            |       | Route to Kinesis                |
| Kinesis Stream       |       | Shared buffer                   |
| IAM Roles            |       | IoT logging, Kinesis, Snowflake |
| Secrets              |       | Private key + config            |
| Log Groups           |       | IoT logs                        |
| SNS Topics           |       | Platform + tenant               |
| CloudWatch Alarms    |       | Platform + tenant               |
| CloudWatch Dashboard |       | Platform metrics                |

Total for tenants ( sites): ~ resources

Next Steps

. Set Up Backend ( minutes)

```bash
 Create S bucket for Terraform state
aws s mb s://smdh-terraform-state --region eu-west-

 Create DynamoDB table for state locking
aws dynamodb create-table \
  --table-name smdh-terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --provisioned-throughput ReadCapacityUnits=,WriteCapacityUnits= \
  --region eu-west-
```

. Configure Snowflake Integration ( minutes)

You need two pieces of information from Snowflake:

. Snowflake AWS Account ID

- Contact Snowflake support or check their documentation
- This is the AWS account Snowflake uses for your region

. Generate External ID

```bash
uuidgen
 Example: E-EB-D-A-
```

. Create Your Configuration ( minutes)

```bash
cd infrastructure/terraform

 Copy example config
cp environments/dev/terraform.tfvars.example environments/dev/terraform.tfvars

 Edit with your values
vim environments/dev/terraform.tfvars
```

Required changes:

- `snowflake_account_id` - From Snowflake
- `snowflake_external_id` - Your generated UUID
- `alert_email` - Your email for alerts
- `tenants` - Your tenant configuration

. Deploy Infrastructure ( minutes)

```bash
 Initialize Terraform
terraform init

 Review what will be created
terraform plan -var-file=environments/dev/terraform.tfvars

 Deploy (type 'yes' when prompted)
terraform apply -var-file=environments/dev/terraform.tfvars
```

. Extract Certificates ( minutes)

```bash
 Get certificate PEMs
terraform output -json tenant_certificate_pems > certificates.json

 View certificate details
cat certificates.json | jq
```

. Configure Snowflake Openflow ( minutes)

. Get the IAM role ARN:

```bash
terraform output snowflake_iam_role_arn
```

. In Snowflake, configure the Openflow connector:

```sql
-- Configure external access integration
CREATE EXTERNAL ACCESS INTEGRATION smdh_kinesis_integration
  ROLE_ARN = 'arn:aws:iam::YOUR_ACCOUNT:role/smdh-snowflake-kinesis-role-dev'
  EXTERNAL_ID = 'YOUR_EXTERNAL_ID'
  ENABLED = TRUE;
```

File Structure Created

```
infrastructure/terraform/
 main.tf                                Root orchestration
 providers.tf                           AWS provider config
 variables.tf                           Input variables
 outputs.tf                             Output values
 .gitignore                             Protect sensitive files
 README.md                              Complete documentation
 modules/
    iot-core/                          IoT Core module ( files)
    kinesis/                           Kinesis module ( files)
    iam/                               IAM module ( files)
    secrets-manager/                   Secrets module ( files)
    cloudwatch/                        Monitoring module ( files)
    tenant/                            Tenant module ( files)
 environments/
     dev/
        terraform.tfvars.example       Dev config template
     prod/
         terraform.tfvars.example       Prod config template
```

Total: files, ~, lines of Terraform code

Special Features

. Automatic Certificate Generation

- No manual certificate creation needed
- Private keys stored securely in Terraform state
- Certificates attached to Things automatically

. Smart Multi-Tenancy

- Add tenants by just editing `terraform.tfvars`
- Each tenant gets isolated: Things, Policies, Rules, Alerts
- Terraform handles all the complex wiring

. Production-Ready Monitoring

- Alarms trigger before users notice issues
- Dashboard shows real-time platform health
- Per-tenant SNS topics for isolated alerting

. Secure by Default

- Encryption everywhere (Kinesis, Secrets Manager)
- External ID for Snowflake cross-account trust
- Least privilege IAM policies
- Certificate-based device authentication

  Important Notes

Terraform State Contains Secrets
The Terraform state file contains:

- Private keys for all certificates
- Certificate PEMs
- IAM role details

Protect the state:

- S backend encrypts state at rest
- Use DynamoDB locking to prevent conflicts
- Never commit `.tfstate` files to git
- Use workspace isolation for environments

Cost Estimates ( Tenants)

Based on the architecture:

- IoT Core: ~$/month (M messages/day)
- Kinesis: ~$/month (on-demand, stream)
- Secrets Manager: ~$/month ( secrets)
- CloudWatch: ~$/month (logs + alarms)
- Total AWS: ~$/month ($- per tenant)

  Testing Your Deployment

. Verify IoT Endpoint

```bash
terraform output iot_endpoint
 Should show: xxxxxx.iot.eu-west-.amazonaws.com
```

. Check Kinesis Stream

```bash
aws kinesis describe-stream \
  --stream-name smdh-sensor-data-stream \
  --region eu-west-
```

. Test MQTT Publishing

```bash
aws iot-data publish \
  --topic "smdh/test_tenant/site_/sensor-data" \
  --payload '{"temperature":.}' \
  --region eu-west-
```

. View Dashboard

```bash
terraform output cloudwatch_dashboard_url
 Open URL in browser
```

This Terraform configuration demonstrates:

- Multi-module architecture for reusability
- Dynamic resource creation using `for_each`
- Sensitive data handling with Terraform
- AWS IoT Core certificate and policy management
- Cross-account IAM roles for Snowflake
- Complete monitoring setup with CloudWatch
- Production-ready infrastructure with state management

  Related Documentation

- [Implementation Plan](SMDH_Implementation_Plan.md) - Overall implementation strategy
- [Architecture Design](../docs/detailed-design/SMDH%AWS%design.md) - Why these choices were made
- [Terraform README](terraform/README.md) - Detailed Terraform usage
- [Implementation Guide](SMDH_Infrastructure_Implementation.md) - Step-by-step procedures

  Completion Checklist

- [x] IoT Core module with Thing Types
- [x] Kinesis module with encryption
- [x] IAM module for Snowflake integration
- [x] Secrets Manager module
- [x] CloudWatch module with dashboard
- [x] Tenant module with multi-tenancy
- [x] Root configuration tying all together
- [x] Environment configurations (dev/prod)
- [x] Comprehensive documentation
- [x] .gitignore for security
- [ ] YOUR TURN: Configure Snowflake values
- [ ] YOUR TURN: Deploy to AWS
- [ ] YOUR TURN: Test end-to-end data flow

  Ready to Deploy!

You now have production-ready Terraform infrastructure. The next step is to:

. Set up the S backend
. Get Snowflake configuration values
. Create your `terraform.tfvars`
. Run `terraform apply`

Then move on to Phase : Snowflake Setup Scripts (from the Implementation Plan).

---

Created: --
Status: Complete and Ready for Deployment
Next Phase: Snowflake SQL Scripts
ScotgovRocks\*01
