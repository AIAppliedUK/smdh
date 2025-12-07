# SMDH IAM Module
# Creates IAM user with access keys for OpenFlow Kinesis connector

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Get current AWS account ID for DynamoDB ARN construction
data "aws_caller_identity" "current" {}

# Policy for OpenFlow to read from Kinesis
data "aws_iam_policy_document" "openflow_kinesis_read" {
  statement {
    sid    = "KinesisReadAccess"
    effect = "Allow"

    actions = [
      "kinesis:DescribeStream",
      "kinesis:DescribeStreamSummary",
      "kinesis:GetRecords",
      "kinesis:GetShardIterator",
      "kinesis:ListShards",
      "kinesis:ListStreams",
      "kinesis:SubscribeToShard",
      "kinesis:RegisterStreamConsumer",
      "kinesis:DeregisterStreamConsumer",
      "kinesis:DescribeStreamConsumer",
      "kinesis:ListStreamConsumers"
    ]

    resources = var.kinesis_stream_arns
  }

  statement {
    sid    = "KinesisListAccess"
    effect = "Allow"

    actions = [
      "kinesis:ListStreams",
      "kinesis:ListTagsForStream"
    ]

    resources = ["*"]
  }

  # DynamoDB access required for KCL (Kinesis Consumer Library) checkpointing
  # OpenFlow uses KCL internally for reliable stream consumption
  statement {
    sid    = "DynamoDBKCLAccess"
    effect = "Allow"

    actions = [
      "dynamodb:CreateTable",
      "dynamodb:UpdateTable",
      "dynamodb:DeleteTable",
      "dynamodb:DescribeTable",
      "dynamodb:DescribeTimeToLive",
      "dynamodb:UpdateTimeToLive",
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:DeleteItem",
      "dynamodb:Scan",
      "dynamodb:Query",
      "dynamodb:BatchGetItem",
      "dynamodb:BatchWriteItem"
    ]

    # KCL creates tables with naming pattern: <application-name>
    # Our application names follow: smdh-openflow-{tenant_id}
    resources = [
      "arn:aws:dynamodb:${var.aws_region}:${data.aws_caller_identity.current.account_id}:table/smdh-openflow-*"
    ]
  }

  statement {
    sid    = "DynamoDBKCLListAccess"
    effect = "Allow"

    actions = [
      "dynamodb:ListTables"
    ]

    resources = ["*"]
  }

  # CloudWatch metrics for KCL (optional but recommended)
  statement {
    sid    = "CloudWatchMetricsAccess"
    effect = "Allow"

    actions = [
      "cloudwatch:PutMetricData"
    ]

    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "cloudwatch:namespace"
      values   = ["SMDH/Openflow"]
    }
  }
}

# =============================================================================
# OpenFlow IAM User with Access Keys
# =============================================================================
# OpenFlow requires IAM access keys (not role assumption) for Kinesis access.

resource "aws_iam_user" "openflow_kinesis" {
  name = "${var.project_name}-openflow-kinesis-user-${var.environment}"
  path = "/service-accounts/"

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-openflow-kinesis-user"
      Description = "Service account for Snowflake OpenFlow Kinesis connector"
      Purpose     = "Snowflake OpenFlow Integration"
    }
  )
}

resource "aws_iam_user_policy" "openflow_kinesis" {
  name   = "openflow-kinesis-access"
  user   = aws_iam_user.openflow_kinesis.name
  policy = data.aws_iam_policy_document.openflow_kinesis_read.json
}

resource "aws_iam_access_key" "openflow_kinesis" {
  user = aws_iam_user.openflow_kinesis.name
}

# =============================================================================
# Optional: Lambda Execution Role
# =============================================================================
# For custom processing functions (if needed)

resource "aws_iam_role" "lambda_execution" {
  count = var.create_lambda_role ? 1 : 0

  name               = "${var.project_name}-lambda-execution-role-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume[0].json
  description        = "Execution role for SMDH Lambda functions"

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-lambda-execution-role"
    }
  )
}

data "aws_iam_policy_document" "lambda_assume" {
  count = var.create_lambda_role ? 1 : 0

  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  count = var.create_lambda_role ? 1 : 0

  role       = aws_iam_role.lambda_execution[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "lambda_secrets" {
  count = var.create_lambda_role ? 1 : 0

  statement {
    effect = "Allow"

    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret"
    ]

    resources = var.secrets_manager_arns
  }
}

resource "aws_iam_role_policy" "lambda_secrets" {
  count = var.create_lambda_role ? 1 : 0

  name   = "lambda-secrets-read"
  role   = aws_iam_role.lambda_execution[0].id
  policy = data.aws_iam_policy_document.lambda_secrets[0].json
}
