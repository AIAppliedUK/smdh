# SMDH IoT Core Module
# Creates AWS IoT Core resources including Thing Types and base configuration

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Get IoT endpoint for the region
data "aws_iot_endpoint" "data_ats" {
  endpoint_type = "iot:Data-ATS"
}

# Create Thing Type for Milesight UG65 LoRaWAN Gateways
resource "aws_iot_thing_type" "lorawan_gateway" {
  name = var.lorawan_thing_type_name

  properties {
    description = "Milesight UG65 LoRaWAN Gateway devices for SMDH platform"
    searchable_attributes = [
      "tenant_id",
      "site_id",
      "device_type"
    ]
  }

  tags = merge(
    var.tags,
    {
      Name        = var.lorawan_thing_type_name
      Description = "SMDH Milesight UG65 LoRaWAN Gateway Thing Type"
      ThingType   = "Gateway"
      Manufacturer = "Milesight"
      Model       = "UG65"
    }
  )

  # Ignore tag changes due to AWS provider default_tags inconsistency with IoT resources
  lifecycle {
    ignore_changes = [tags_all]
  }
}

# Create Thing Type for DevTank OSM devices
resource "aws_iot_thing_type" "devtank_osm" {
  name = var.devtank_thing_type_name

  properties {
    description = "DevTank OpenSmartMonitor devices for SMDH platform"
    searchable_attributes = [
      "tenant_id",
      "site_id",
      "device_type"
    ]
  }

  tags = merge(
    var.tags,
    {
      Name        = var.devtank_thing_type_name
      Description = "SMDH DevTank OSM Thing Type"
      ThingType   = "Sensor"
    }
  )

  # Ignore tag changes due to AWS provider default_tags inconsistency with IoT resources
  lifecycle {
    ignore_changes = [tags_all]
  }
}

# Create Thing Type for Air Quality Sensors
resource "aws_iot_thing_type" "air_quality_sensor" {
  name = var.air_quality_thing_type_name

  properties {
    description = "Air Quality Sensors (PM, AQI, pollutants) for SMDH platform"
    searchable_attributes = [
      "tenant_id",
      "site_id",
      "manufacturer"
    ]
  }

  tags = merge(
    var.tags,
    {
      Name        = var.air_quality_thing_type_name
      Description = "SMDH Air Quality Sensor Thing Type"
      ThingType   = "Sensor"
      SensorClass = "Environmental"
    }
  )

  lifecycle {
    ignore_changes = [tags_all]
  }
}

# Create Thing Type for Power/Energy Sensors
resource "aws_iot_thing_type" "power_sensor" {
  name = var.power_sensor_thing_type_name

  properties {
    description = "Power and Energy Sensors (voltage, current, power factor) for SMDH platform"
    searchable_attributes = [
      "tenant_id",
      "site_id",
      "manufacturer"
    ]
  }

  tags = merge(
    var.tags,
    {
      Name        = var.power_sensor_thing_type_name
      Description = "SMDH Power/Energy Sensor Thing Type"
      ThingType   = "Sensor"
      SensorClass = "Electrical"
    }
  )

  lifecycle {
    ignore_changes = [tags_all]
  }
}

# Create Thing Type for Water Sensors
resource "aws_iot_thing_type" "water_sensor" {
  name = var.water_sensor_thing_type_name

  properties {
    description = "Water Sensors (flow, pressure, quality) for SMDH platform"
    searchable_attributes = [
      "tenant_id",
      "site_id",
      "manufacturer"
    ]
  }

  tags = merge(
    var.tags,
    {
      Name        = var.water_sensor_thing_type_name
      Description = "SMDH Water Sensor Thing Type"
      ThingType   = "Sensor"
      SensorClass = "Fluid"
    }
  )

  lifecycle {
    ignore_changes = [tags_all]
  }
}

# Create Thing Type for Gas Sensors
resource "aws_iot_thing_type" "gas_sensor" {
  name = var.gas_sensor_thing_type_name

  properties {
    description = "Gas Sensors (CO2, TVOC, O2, NO2) for SMDH platform"
    searchable_attributes = [
      "tenant_id",
      "site_id",
      "manufacturer"
    ]
  }

  tags = merge(
    var.tags,
    {
      Name        = var.gas_sensor_thing_type_name
      Description = "SMDH Gas Sensor Thing Type"
      ThingType   = "Sensor"
      SensorClass = "Environmental"
    }
  )

  lifecycle {
    ignore_changes = [tags_all]
  }
}

# Create Thing Type for Environmental Sensors
resource "aws_iot_thing_type" "environmental_sensor" {
  name = var.environmental_sensor_thing_type_name

  properties {
    description = "Environmental Sensors (temperature, humidity, pressure, dew point) for SMDH platform"
    searchable_attributes = [
      "tenant_id",
      "site_id",
      "manufacturer"
    ]
  }

  tags = merge(
    var.tags,
    {
      Name        = var.environmental_sensor_thing_type_name
      Description = "SMDH Environmental Sensor Thing Type"
      ThingType   = "Sensor"
      SensorClass = "Environmental"
    }
  )

  lifecycle {
    ignore_changes = [tags_all]
  }
}

# Create Thing Type for Acoustic Sensors
resource "aws_iot_thing_type" "acoustic_sensor" {
  name = var.acoustic_sensor_thing_type_name

  properties {
    description = "Acoustic Sensors (sound level, frequency analysis) for SMDH platform"
    searchable_attributes = [
      "tenant_id",
      "site_id",
      "manufacturer"
    ]
  }

  tags = merge(
    var.tags,
    {
      Name        = var.acoustic_sensor_thing_type_name
      Description = "SMDH Acoustic Sensor Thing Type"
      ThingType   = "Sensor"
      SensorClass = "Acoustic"
    }
  )

  lifecycle {
    ignore_changes = [tags_all]
  }
}

# Create Thing Type for Light Sensors
resource "aws_iot_thing_type" "light_sensor" {
  name = var.light_sensor_thing_type_name

  properties {
    description = "Light Sensors (illuminance, color temperature, CRI) for SMDH platform"
    searchable_attributes = [
      "tenant_id",
      "site_id",
      "manufacturer"
    ]
  }

  tags = merge(
    var.tags,
    {
      Name        = var.light_sensor_thing_type_name
      Description = "SMDH Light Sensor Thing Type"
      ThingType   = "Sensor"
      SensorClass = "Optical"
    }
  )

  lifecycle {
    ignore_changes = [tags_all]
  }
}

# Create CloudWatch logging role for IoT Core
resource "aws_iam_role" "iot_logging" {
  name               = "${var.project_name}-iot-logging-role-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.iot_logging_assume.json

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-iot-logging-role"
    }
  )
}

data "aws_iam_policy_document" "iot_logging_assume" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["iot.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role_policy_attachment" "iot_logging" {
  role       = aws_iam_role.iot_logging.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSIoTLogging"
}

# Configure IoT logging to CloudWatch
resource "aws_iot_logging_options" "main" {
  default_log_level = var.log_level
  role_arn          = aws_iam_role.iot_logging.arn

  depends_on = [aws_iam_role_policy_attachment.iot_logging]
}

# IAM role for IoT Rules Engine to write to Kinesis
resource "aws_iam_role" "iot_kinesis" {
  name               = "${var.project_name}-iot-kinesis-role-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.iot_kinesis_assume.json

  tags = merge(
    var.tags,
    {
      Name        = "${var.project_name}-iot-kinesis-role"
      Description = "Allows IoT Rules Engine to write to Kinesis"
    }
  )
}

data "aws_iam_policy_document" "iot_kinesis_assume" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["iot.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

# Policy for IoT to write to Kinesis (will be attached by Kinesis module)
data "aws_iam_policy_document" "iot_kinesis_policy" {
  statement {
    effect = "Allow"

    actions = [
      "kinesis:PutRecord",
      "kinesis:PutRecords",
      "kinesis:DescribeStream"
    ]

    resources = var.kinesis_stream_arns
  }
}

resource "aws_iam_role_policy" "iot_kinesis" {
  name   = "iot-kinesis-write"
  role   = aws_iam_role.iot_kinesis.id
  policy = data.aws_iam_policy_document.iot_kinesis_policy.json
}
