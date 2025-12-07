# SMDH Terraform Provider Configuration
# Configures AWS provider and backend for state management

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # S3 backend for state management
  # Update bucket name before use
  backend "s3" {
    bucket         = "smdh-terraform-state"
    key            = "infrastructure/terraform.tfstate"
    region         = "eu-west-2"
    encrypt        = true
    dynamodb_table = "smdh-terraform-locks"
  }
}

provider "aws" {
  region = var.aws_region

  # Apply default tags to ALL resources
  default_tags {
    tags = local.common_tags
  }
}

# Data source for current AWS account
data "aws_caller_identity" "current" {}

# Data source for AWS region
data "aws_region" "current" {}
