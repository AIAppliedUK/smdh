# SMDH IAM Module
# Creates IAM roles for cross-account access (Snowflake) and service integrations

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# IAM role for Snowflake to read from Kinesis (Openflow connector)
resource "aws_iam_role" "snowflake_kinesis" {
  name               = "${var.project_name}-snowflake-kinesis-role-${var.environment}"
  assume_role_policy = local.snowflake_assume_policy
  description        = "Allows Snowflake Openflow connector to read from Kinesis streams"

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-snowflake-kinesis-role"
      Description = "Snowflake cross-account Kinesis access"
      Purpose     = "Snowflake Openflow Integration"
    }
  )
}

# Trust policy for Snowflake to assume the role (without External ID)
data "aws_iam_policy_document" "snowflake_assume_base" {
  statement {
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = var.snowflake_account_id != "" ? ["arn:aws:iam::${var.snowflake_account_id}:root"] : ["*"]
    }

    actions = ["sts:AssumeRole"]
  }
}

# Trust policy for Snowflake with External ID
data "aws_iam_policy_document" "snowflake_assume_with_external_id" {
  statement {
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = var.snowflake_account_id != "" ? ["arn:aws:iam::${var.snowflake_account_id}:root"] : ["*"]
    }

    actions = ["sts:AssumeRole"]

    condition {
      test     = "StringEquals"
      variable = "sts:ExternalId"
      values   = [var.snowflake_external_id]
    }
  }
}

# Select the appropriate policy based on whether External ID is provided
locals {
  snowflake_assume_policy = var.snowflake_external_id != "" ? data.aws_iam_policy_document.snowflake_assume_with_external_id.json : data.aws_iam_policy_document.snowflake_assume_base.json
}

# Policy for Snowflake to read from Kinesis
data "aws_iam_policy_document" "snowflake_kinesis_read" {
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
      "kinesis:SubscribeToShard"
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
}

resource "aws_iam_role_policy" "snowflake_kinesis_read" {
  name   = "snowflake-kinesis-read-policy"
  role   = aws_iam_role.snowflake_kinesis.id
  policy = data.aws_iam_policy_document.snowflake_kinesis_read.json
}

# Optional: IAM role for Lambda functions (if needed for custom processing)
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

# Policy for Lambda to read from Secrets Manager
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
