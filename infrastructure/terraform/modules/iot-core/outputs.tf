# IoT Core Module Outputs

output "iot_endpoint" {
  description = "AWS IoT Core endpoint (hostname only)"
  value       = data.aws_iot_endpoint.data_ats.endpoint_address
}

output "iot_endpoint_address" {
  description = "Full AWS IoT Core endpoint address for MQTT connections"
  value       = "mqtt://${data.aws_iot_endpoint.data_ats.endpoint_address}:8883"
}

output "lorawan_thing_type_name" {
  description = "Name of the LoRaWAN Gateway thing type"
  value       = aws_iot_thing_type.lorawan_gateway.name
}

output "lorawan_thing_type_arn" {
  description = "ARN of the LoRaWAN Gateway thing type"
  value       = aws_iot_thing_type.lorawan_gateway.arn
}

output "devtank_thing_type_name" {
  description = "Name of the DevTank OSM thing type"
  value       = aws_iot_thing_type.devtank_osm.name
}

output "devtank_thing_type_arn" {
  description = "ARN of the DevTank OSM thing type"
  value       = aws_iot_thing_type.devtank_osm.arn
}

output "network_server_thing_type_name" {
  description = "Name of the Network Server thing type (ChirpStack or similar)"
  value       = aws_iot_thing_type.network_server.name
}

output "network_server_thing_type_arn" {
  description = "ARN of the Network Server thing type"
  value       = aws_iot_thing_type.network_server.arn
}

output "air_quality_thing_type_name" {
  description = "Name of the Air Quality Sensor thing type"
  value       = aws_iot_thing_type.air_quality_sensor.name
}

output "power_sensor_thing_type_name" {
  description = "Name of the Power/Energy Sensor thing type"
  value       = aws_iot_thing_type.power_sensor.name
}

output "water_sensor_thing_type_name" {
  description = "Name of the Water Sensor thing type"
  value       = aws_iot_thing_type.water_sensor.name
}

output "gas_sensor_thing_type_name" {
  description = "Name of the Gas Sensor thing type"
  value       = aws_iot_thing_type.gas_sensor.name
}

output "environmental_sensor_thing_type_name" {
  description = "Name of the Environmental Sensor thing type"
  value       = aws_iot_thing_type.environmental_sensor.name
}

output "acoustic_sensor_thing_type_name" {
  description = "Name of the Acoustic Sensor thing type"
  value       = aws_iot_thing_type.acoustic_sensor.name
}

output "light_sensor_thing_type_name" {
  description = "Name of the Light Sensor thing type"
  value       = aws_iot_thing_type.light_sensor.name
}

output "sensor_thing_types" {
  description = "Map of all sensor thing type names"
  value = {
    air_quality   = aws_iot_thing_type.air_quality_sensor.name
    power_energy  = aws_iot_thing_type.power_sensor.name
    water         = aws_iot_thing_type.water_sensor.name
    gas           = aws_iot_thing_type.gas_sensor.name
    environmental = aws_iot_thing_type.environmental_sensor.name
    acoustic      = aws_iot_thing_type.acoustic_sensor.name
    light         = aws_iot_thing_type.light_sensor.name
  }
}

output "iot_kinesis_role_arn" {
  description = "IAM role ARN for IoT Rules Engine to write to Kinesis"
  value       = aws_iam_role.iot_kinesis.arn
}

output "iot_kinesis_role_name" {
  description = "IAM role name for IoT Rules Engine"
  value       = aws_iam_role.iot_kinesis.name
}

output "iot_logging_role_arn" {
  description = "IAM role ARN for IoT Core logging"
  value       = aws_iam_role.iot_logging.arn
}
