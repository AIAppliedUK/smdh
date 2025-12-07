# IoT Core Module Variables

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "smdh"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "lorawan_thing_type_name" {
  description = "Name for Milesight UG65 LoRaWAN Gateway thing type"
  type        = string
  default     = "Milesight-UG65"
}

variable "devtank_thing_type_name" {
  description = "Name for DevTank OSM thing type"
  type        = string
  default     = "DevTankOSM"
}

variable "network_server_thing_type_name" {
  description = "Name for LoRaWAN Network Server thing type (ChirpStack or similar)"
  type        = string
  default     = "NetworkServer"
}

variable "air_quality_thing_type_name" {
  description = "Name for Air Quality Sensor thing type"
  type        = string
  default     = "AirQualitySensor"
}

variable "power_sensor_thing_type_name" {
  description = "Name for Power/Energy Sensor thing type"
  type        = string
  default     = "PowerEnergySensor"
}

variable "water_sensor_thing_type_name" {
  description = "Name for Water Sensor thing type"
  type        = string
  default     = "WaterSensor"
}

variable "gas_sensor_thing_type_name" {
  description = "Name for Gas Sensor thing type"
  type        = string
  default     = "GasSensor"
}

variable "environmental_sensor_thing_type_name" {
  description = "Name for Environmental Sensor thing type"
  type        = string
  default     = "EnvironmentalSensor"
}

variable "acoustic_sensor_thing_type_name" {
  description = "Name for Acoustic Sensor thing type"
  type        = string
  default     = "AcousticSensor"
}

variable "light_sensor_thing_type_name" {
  description = "Name for Light Sensor thing type"
  type        = string
  default     = "LightSensor"
}

variable "log_level" {
  description = "IoT Core logging level (ERROR, WARN, INFO, DEBUG, DISABLED)"
  type        = string
  default     = "INFO"

  validation {
    condition     = contains(["ERROR", "WARN", "INFO", "DEBUG", "DISABLED"], var.log_level)
    error_message = "Log level must be one of: ERROR, WARN, INFO, DEBUG, DISABLED"
  }
}

variable "kinesis_stream_arns" {
  description = "List of Kinesis stream ARNs that IoT Rules can write to"
  type        = list(string)
  default     = ["*"]
}

variable "tags" {
  description = "Additional tags to apply to resources"
  type        = map(string)
  default     = {}
}
