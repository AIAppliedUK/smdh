 SMDH Tagging Strategy

 Overview

This document defines the comprehensive tagging strategy for the SMDH platform to enable:
- Cost Allocation: Track costs per tenant, environment, and component
- Operational Monitoring: Identify resources for troubleshooting
- Compliance: Meet regulatory tagging requirements
- Automation: Enable automated resource management
- Security: Classify data and enforce policies

 Tag Categories

 . Mandatory Tags (Applied to ALL Resources)

These tags are REQUIRED and enforced via Terraform validation:

| Tag Name | Description | Example | Purpose |
|----------|-------------|---------|---------|
| `Project` | Project identifier | `smdh` | Group all SMDH resources |
| `Environment` | Environment name | `prod`, `dev`, `staging` | Separate environments |
| `ManagedBy` | Management tool | `Terraform` | Identify IaC-managed resources |
| `Owner` | Team/person responsible | `Platform-Team` | Contact for issues |
| `CostCenter` | Billing allocation code | `ENG-` | Cost allocation |
| `Repository` | Source code location | `smdh` | Link to code |

Terraform Configuration:
```hcl
 Set in terraform.tfvars
owner       = "Platform-Team"
cost_center = "ENG-"
environment = "prod"
```

 . Component Tags (Applied by Module)

These tags identify the technical component:

| Tag Name | Description | Example | Applied By |
|----------|-------------|---------|------------|
| `Component` | Infrastructure component | `IoT-Core`, `Data-Ingestion` | Module |
| `Service` | AWS service name | `AWS-IoT`, `Kinesis-Stream` | Module |
| `Description` | Human-readable description | `MQTT broker and device registry` | Module |

Automatically Applied:
- IoT Core module: `Component: IoT-Core`, `Service: AWS-IoT`
- Kinesis module: `Component: Data-Ingestion`, `Service: Kinesis-Stream`
- CloudWatch module: `Component: Monitoring`, `Service: CloudWatch`

 . Tenant-Specific Tags (Per-Tenant Resources)

These enable per-tenant cost tracking:

| Tag Name | Description | Example | Purpose |
|----------|-------------|---------|---------|
| `TenantId` | Unique tenant identifier | `company_a` | Tenant cost allocation |
| `TenantName` | Human-readable name | `Company A Manufacturing Ltd` | Identification |
| `BillingTenant` | Billing identifier | `company_a` | Cost reports |
| `NumSites` | Number of sites | `` | Capacity planning |
| `ContactEmail` | Tenant contact | `ops@companya.com` | Alerting |

Cost Allocation Query:
```sql
-- AWS Cost Explorer filter
Tag: TenantId = company_a
```

 . Compliance Tags

Required for data governance and security:

| Tag Name | Description | Values | Purpose |
|----------|-------------|--------|---------|
| `DataClassification` | Data sensitivity level | `Public`, `Internal`, `Confidential`, `Restricted` | Security policies |
| `Compliance` | Regulatory requirements | `GDPR`, `ISO`, `None` | Audit compliance |
| `BackupPolicy` | Backup retention | `Daily`, `Weekly`, `Monthly`, `None` | Data protection |
| `EncryptionRequired` | Must encrypt at rest | `true`, `false` | Security enforcement |

Default Values:
- DataClassification: `Internal`
- Compliance: `None`
- BackupPolicy: `Daily`

 . Operational Tags

Support operations and troubleshooting:

| Tag Name | Description | Example | Purpose |
|----------|-------------|---------|---------|
| `DeployedBy` | Who deployed | `john.smith@company.com` | Audit trail |
| `DeployedAt` | When deployed | `--T::Z` | Change tracking |
| `TerraformWorkspace` | TF workspace | `prod` | State management |
| `ServiceTier` | Criticality | `Critical`, `High`, `Medium`, `Low` | SLA enforcement |
| `Critical` | Business critical | `true`, `false` | Priority alerting |

 . Integration Tags

Identify cross-service integrations:

| Tag Name | Description | Example | Applied To |
|----------|-------------|---------|------------|
| `Integration` | External system | `Snowflake` | IAM roles |
| `DataFlow` | Data pipeline | `IoT-to-Snowflake` | Kinesis |

 Tag Hierarchy

```
Common Tags (ALL resources)
 Project: smdh
 Environment: prod
 ManagedBy: Terraform
 Owner: Platform-Team
 CostCenter: ENG-
 Repository: smdh
 DataClassification: Internal
 Compliance: GDPR
 BackupPolicy: Daily

Module-Specific Tags
 Component: [varies by module]
 Service: [AWS service]
 Description: [module purpose]

Resource-Specific Tags
 TenantId: [per tenant]
 TenantName: [per tenant]
 BillingTenant: [per tenant]
```

 Cost Allocation Strategy

 AWS Cost Explorer Filters

. By Environment
   ```
   Tag: Environment = prod
   ```

. By Tenant
   ```
   Tag: TenantId = company_a
   ```

. By Component
   ```
   Tag: Component = IoT-Core
   ```

. By Cost Center
   ```
   Tag: CostCenter = ENG-
   ```

 Cost Allocation Report Example

```
Month: November 
Environment: prod
Cost Center: ENG-

Total: $.

By Component:
- IoT-Core:        $. (%)
- Data-Ingestion:  $ . (%)
- Monitoring:      $. (%)
- Security:        $  . (%)

By Tenant:
- company_a:       $ . (%)
- company_b:       $ . (%)
- company_c:       $ . (%)
```

 Per-Tenant Cost Calculation

```
Shared Costs (Platform):
- IoT Core base:   $/month (split evenly)
- Kinesis:         $/month (split evenly)
- Monitoring:      $/month (split evenly)
Shared Total:      $/month

Per-Tenant Costs:
- IoT messages:    ($./million) × messages
- IoT certificates: $/month (free)
- SNS topic:       $./month
- Alarms:          $./month × alarms

Total per Tenant = (Shared / num_tenants) + Per-Tenant
```

 AWS Cost and Usage Reports (CUR)

 Enable CUR with Tags

. AWS Console → Billing → Cost and Usage Reports
. Create Report:
   - Report name: `smdh-cur-report`
   - Time granularity: `Daily`
   - Include resource IDs: `Yes`
   - Enable tag export: `Yes`

. Select Tags to Export:
   - `Project`
   - `Environment`
   - `TenantId`
   - `Component`
   - `CostCenter`
   - `Owner`

 Query CUR in Athena

```sql
-- Cost by tenant
SELECT
  line_item_resource_id,
  resource_tags_user_tenant_id AS tenant_id,
  SUM(line_item_unblended_cost) AS cost
FROM smdh_cur_report
WHERE resource_tags_user_project = 'smdh'
GROUP BY tenant_id, line_item_resource_id
ORDER BY cost DESC;
```

 Tagging Best Practices

 DO 

. Use consistent naming
   - Use PascalCase for tag keys: `CostCenter`, `TenantId`
   - Use lowercase with hyphens for values: `company-a`, `iot-core`

. Keep values machine-readable
   - Good: `company_a`, `eng-`
   - Bad: `Company A Manufacturing Ltd.`, `Engineering Dept. `

. Document tag meanings
   - Maintain this TAGGING_STRATEGY.md
   - Update when adding new tags

. Validate tags in Terraform
   - Use validation blocks
   - Enforce mandatory tags

. Review tags monthly
   - Audit Cost Explorer
   - Identify untagged resources
   - Update tagging policy

 DON'T 

. Don't use PII in tags
   - Bad: `email=john.smith@company.com`
   - Good: `Owner=Platform-Team`

. Don't create too many tags
   - AWS limit:  tags per resource
   - Keep to essential tags only

. Don't use special characters
   - Avoid: `!`, `@`, ``, `$`, `%`
   - Use: Letters, numbers, `-`, `_`, `.`

. Don't hardcode values
   - Use Terraform variables
   - Use locals for computed tags

. Don't forget tenant isolation
   - Always tag with `TenantId`
   - Always tag with `BillingTenant`

 Enforcement

 Terraform Validation

```hcl
 In tags.tf
resource "null_resource" "validate_tags" {
  lifecycle {
    precondition {
      condition     = var.owner != ""
      error_message = "Tag 'Owner' is mandatory"
    }

    precondition {
      condition     = var.cost_center != ""
      error_message = "Tag 'CostCenter' is mandatory"
    }
  }
}
```

 AWS Config Rules (Optional)

```json
{
  "ConfigRuleName": "required-tags",
  "Description": "Ensure all resources have mandatory tags",
  "Source": {
    "Owner": "AWS",
    "SourceIdentifier": "REQUIRED_TAGS"
  },
  "InputParameters": {
    "tagKey": "Project",
    "tagKey": "Environment",
    "tagKey": "Owner",
    "tagKey": "CostCenter"
  }
}
```

 Tag Usage Examples

 Example : Production IoT Thing

```json
{
  "Project": "smdh",
  "Environment": "prod",
  "ManagedBy": "Terraform",
  "Owner": "Platform-Team",
  "CostCenter": "ENG-",
  "Repository": "smdh",
  "Component": "Tenant-Resources",
  "Service": "Multi-Tenant-IoT",
  "TenantId": "company_a",
  "TenantName": "Company A Manufacturing Ltd",
  "BillingTenant": "company_a",
  "DataClassification": "Internal",
  "Compliance": "GDPR",
  "DeployedAt": "--T::Z"
}
```

 Example : Kinesis Stream

```json
{
  "Project": "smdh",
  "Environment": "prod",
  "ManagedBy": "Terraform",
  "Owner": "Platform-Team",
  "CostCenter": "ENG-",
  "Component": "Data-Ingestion",
  "Service": "Kinesis-Stream",
  "Description": "Sensor data buffer and ordering",
  "DataFlow": "IoT-to-Snowflake",
  "Critical": "true",
  "ServiceTier": "High",
  "BackupPolicy": "None"
}
```

 Example : Secrets Manager Secret

```json
{
  "Project": "smdh",
  "Environment": "prod",
  "ManagedBy": "Terraform",
  "Owner": "Platform-Team",
  "CostCenter": "ENG-",
  "Component": "Security",
  "Service": "Secrets-Manager",
  "Description": "Snowflake credentials and configuration",
  "DataClassification": "Restricted",
  "EncryptionRequired": "true",
  "Compliance": "GDPR"
}
```

 Monthly Tag Review Checklist

- [ ] Run Cost Explorer reports by tag
- [ ] Identify untagged or mis-tagged resources
- [ ] Verify tenant cost allocation is accurate
- [ ] Update this document with new tag requirements
- [ ] Review tag compliance with security policy
- [ ] Check for orphaned resources (no owner tag)
- [ ] Validate cost center codes are still valid

 Reporting Queries

 . List All Resources by Tenant

```bash
aws resourcegroupstaggingapi get-resources \
  --tag-filters Key=TenantId,Values=company_a \
  --region eu-west-
```

 . Find Untagged Resources

```bash
aws resourcegroupstaggingapi get-resources \
  --resource-type-filters "AWS::IoT::Thing" \
  --region eu-west- | \
  jq '.ResourceTagMappingList[] | select(.Tags | length == )'
```

 . Cost by Tag (AWS CLI)

```bash
aws ce get-cost-and-usage \
  --time-period Start=--,End=-- \
  --granularity MONTHLY \
  --metrics UnblendedCost \
  --group-by Type=TAG,Key=TenantId
```

 Integration with Monitoring

 CloudWatch Insights Query by Tenant

```
fields @timestamp, @message
| filter TenantId = "company_a"
| sort @timestamp desc
| limit 
```

 CloudWatch Alarm with Tags

```hcl
resource "aws_cloudwatch_metric_alarm" "example" {
  alarm_name = "example-alarm"

  tags = {
    TenantId   = "company_a"
    Component  = "Monitoring"
    Critical   = "true"
  }
}
```

 Tag Lifecycle

. Creation: Tags applied via Terraform during resource creation
. Update: Tags can be updated via Terraform (plan → apply)
. Audit: Monthly tag compliance review
. Deprecation: Remove obsolete tags via Terraform
. Deletion: Tags removed when resource is destroyed

 References

- [AWS Tagging Best Practices](https://docs.aws.amazon.com/general/latest/gr/aws_tagging.html)
- [AWS Cost Allocation Tags](https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv/cost-alloc-tags.html)
- [Terraform Default Tags](https://www.terraform.io/language/providers/awsdefault_tags)

---

Document Version: .
Last Updated: --
Next Review: Monthly
Owner: Platform Team
