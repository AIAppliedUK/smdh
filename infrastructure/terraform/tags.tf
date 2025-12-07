# SMDH Tagging Strategy
# Defines mandatory and optional tags for all resources

locals {
  # Mandatory tags for all resources
  mandatory_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    Repository  = "smdh"
    Owner       = var.owner
    CostCenter  = var.cost_center
  }

  # Optional operational tags
  operational_tags = {
    DeployedBy  = var.deployed_by
    DeployedAt  = timestamp()
    TerraformWorkspace = terraform.workspace
  }

  # Compliance tags
  compliance_tags = {
    DataClassification = var.data_classification
    Compliance         = var.compliance_requirement
    BackupPolicy       = var.backup_policy
  }

  # Merged common tags (applied to all resources)
  common_tags = merge(
    local.mandatory_tags,
    local.operational_tags,
    local.compliance_tags,
    var.tags
  )
}

# Tag validation - Ensure all mandatory tags are provided
resource "null_resource" "validate_tags" {
  lifecycle {
    precondition {
      condition     = var.owner != ""
      error_message = "Tag 'Owner' is mandatory and must be specified"
    }

    precondition {
      condition     = var.cost_center != ""
      error_message = "Tag 'CostCenter' is mandatory and must be specified"
    }

    precondition {
      condition     = contains(["dev", "staging", "prod"], var.environment)
      error_message = "Tag 'Environment' must be one of: dev, staging, prod"
    }

    precondition {
      condition     = contains(["Public", "Internal", "Confidential", "Restricted"], var.data_classification)
      error_message = "Tag 'DataClassification' must be one of: Public, Internal, Confidential, Restricted"
    }
  }
}
