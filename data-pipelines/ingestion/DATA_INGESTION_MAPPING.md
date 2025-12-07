# Data Ingestion Mapping: OpenSmartMonitor to Snowflake

## Overview

This document maps the data flow from OpenSmartMonitor sensors through AWS IoT to Snowflake tables, showing exact field mappings, transformations, and processing logic.

## Data Flow Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│ OpenSmartMonitor Sensors & LoRaWAN Gateways (Physical Layer)    │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐             │
│  │ Air Quality │  │ Power/Energy│  │ Water Flow  │             │
│  ├─────────────┤  ├─────────────┤  ├─────────────┤             │
│  │ Gas (CO2)   │  │ Environmental││ Acoustic    │             │
│  ├─────────────┤  ├─────────────┤  ├─────────────┤             │
│  │ Light       │  │ LoRaWAN GW  │  │ Pump Stns  │             │
│  └─────────────┘  └─────────────┘  └─────────────┘             │
└──────────────────────────────────────────────────────────────────┘
         ↓                    ↓                   ↓
         MQTT over WiFi/LoRaWAN/Cellular
         ↓                    ↓                   ↓
┌──────────────────────────────────────────────────────────────────┐
│ AWS IoT Core (Milesight UG65 LoRaWAN Gateway)                   │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │ IoT Rules Engine: route_to_kinesis                       │   │
│  │   • SQL: SELECT * FROM 'smdh/+/+/sensor-data'          │   │
│  │   • Action: Forward to Kinesis Stream (partitioned)    │   │
│  └──────────────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────────┘
         ↓
┌──────────────────────────────────────────────────────────────────┐
│ Kinesis Data Stream (smdh-sensor-data-stream)                    │
│  • On-Demand mode (auto-scaling)                                 │
│  • Partition by: tenant_id (distributes across shards)          │
│  • Retention: 24 hours                                           │
│  • KMS encryption enabled                                        │
└──────────────────────────────────────────────────────────────────┘
         ↓
┌──────────────────────────────────────────────────────────────────┐
│ Snowflake Openflow Connector (Cross-Account Integration)         │
│  • Auto-ingestion to RAW schema (near real-time < 1 min)        │
│  • JWT authentication with Snowflake private key                │
│  • Error handling and retry logic                               │
└──────────────────────────────────────────────────────────────────┘
         ↓
┌──────────────────────────────────────────────────────────────────┐
│ Snowflake RAW Schema Tables (Multi-tenant)                       │
│  • raw.sensor_readings (unified all sensor types)               │
│  • raw.air_quality_readings                                      │
│  • raw.power_energy_readings                                     │
│  • raw.water_readings                                            │
│  • raw.gas_readings                                              │
│  • raw.environmental_readings                                    │
│  • raw.acoustic_readings                                         │
│  • raw.light_readings                                            │
│  • raw.gateway_telemetry                                         │
└──────────────────────────────────────────────────────────────────┘
```

## MQTT Message Formats

### PULSE - Clamp Sensor Message

**Topic**: `smdh/{tenant_id}/pulse/{machine_id}/current`

**Payload Example**:
```json
{
  "deviceId": "osm_pulse_001",
  "machineId": "MACHINE_001",
  "siteId": "SITE_001",
  "timestamp": "2025-01-22T14:35:22.123Z",
  "sensorType": "clamp_current",
  "measurements": {
    "current_phase_a": 15.3,
    "current_phase_b": 14.8,
    "current_phase_c": 15.1,
    "current_rms": 15.07,
    "voltage_nominal": 400,
    "power_factor": 0.85,
    "frequency": 50.0
  },
  "metadata": {
    "firmwareVersion": "1.2.3",
    "signalQuality": 95,
    "batteryLevel": 87
  }
}
```

### SENTINEL - Vibration & Temperature Message

**Topic**: `smdh/{tenant_id}/sentinel/{machine_id}/vibration`

**Payload Example**:
```json
{
  "deviceId": "osm_sentinel_001",
  "machineId": "MACHINE_001",
  "siteId": "SITE_001",
  "timestamp": "2025-01-22T14:35:22.123Z",
  "sensorType": "vibration",
  "measurements": {
    "vibration_x": 0.45,
    "vibration_y": 0.38,
    "vibration_z": 0.52,
    "vibration_rms": 0.47,
    "temperature": 42.3,
    "dominant_frequency": 120.5
  },
  "metadata": {
    "firmwareVersion": "1.2.3",
    "samplingRate": 4000
  }
}
```

### HAVEN - Environmental Message

**Topic**: `smdh/{tenant_id}/haven/{zone_id}/environment`

**Payload Example**:
```json
{
  "deviceId": "osm_haven_001",
  "zoneId": "ZONE_A_FLOOR1",
  "siteId": "SITE_001",
  "timestamp": "2025-01-22T14:35:22.123Z",
  "sensorType": "environmental",
  "measurements": {
    "temperature": 21.5,
    "humidity": 45.2,
    "co2_ppm": 450,
    "voc_index": 125,
    "particulates_pm25": 12.3,
    "particulates_pm10": 18.7,
    "noise_db": 68.5,
    "light_lux": 450
  },
  "metadata": {
    "firmwareVersion": "1.2.3",
    "calibrationDate": "2025-01-01"
  }
}
```

### Air Quality Sensor Message

**Topic**: `smdh/{tenant_id}/{site_id}/sensor-data`

**Payload Example**:
```json
{
  "timestamp": "2025-01-22T14:35:22.123Z",
  "device_type": "air_quality_sensor",
  "device_model": "OpenSmartMonitor_AQ",
  "measurements": {
    "pm10": 25.5,
    "pm25": 12.3,
    "pm100": 2.1,
    "aqi": 45,
    "aqi_category": "good"
  },
  "status": {
    "batteryLevel": 85,
    "signalStrength": -65,
    "uptime": 45000
  }
}
```

### Power/Energy Sensor Message

**Topic**: `smdh/{tenant_id}/{site_id}/sensor-data`

**Payload Example**:
```json
{
  "timestamp": "2025-01-22T14:35:22.123Z",
  "device_type": "power_energy_sensor",
  "device_model": "OpenSmartMonitor_Power",
  "measurements": {
    "voltage_v": 230.5,
    "current_a": 15.3,
    "power_w": 3500.0,
    "power_factor": 0.95,
    "energy_kwh": 125.45,
    "frequency_hz": 50.0
  },
  "status": {
    "phase_a": "active",
    "phase_b": "active",
    "phase_c": "active",
    "uptime": 45000
  }
}
```

### Water Sensor Message

**Topic**: `smdh/{tenant_id}/{site_id}/sensor-data`

**Payload Example**:
```json
{
  "timestamp": "2025-01-22T14:35:22.123Z",
  "device_type": "water_sensor",
  "device_model": "OpenSmartMonitor_Water",
  "measurements": {
    "flow_rate_lpm": 45.2,
    "pressure_bar": 2.5,
    "ph": 7.2,
    "turbidity_ntu": 0.5,
    "conductivity_us_cm": 650,
    "temperature_c": 18.5
  },
  "status": {
    "batteryLevel": 80,
    "signalStrength": -70,
    "uptime": 45000
  }
}
```

### Gas Sensor Message

**Topic**: `smdh/{tenant_id}/{site_id}/sensor-data`

**Payload Example**:
```json
{
  "timestamp": "2025-01-22T14:35:22.123Z",
  "device_type": "gas_sensor",
  "device_model": "OpenSmartMonitor_Gas",
  "measurements": {
    "co2_ppm": 450,
    "tvoc_ppb": 125.5,
    "o2_percent": 20.9,
    "no2_ppb": 25.3,
    "iaq": 100
  },
  "status": {
    "batteryLevel": 88,
    "signalStrength": -62,
    "uptime": 45000
  }
}
```

### Environmental Sensor Message

**Topic**: `smdh/{tenant_id}/{site_id}/sensor-data`

**Payload Example**:
```json
{
  "timestamp": "2025-01-22T14:35:22.123Z",
  "device_type": "environmental_sensor",
  "device_model": "OpenSmartMonitor_Environmental",
  "measurements": {
    "temperature_c": 21.5,
    "humidity_percent": 45.2,
    "dew_point_c": 10.3,
    "pressure_hpa": 1013.25
  },
  "status": {
    "batteryLevel": 82,
    "signalStrength": -68,
    "uptime": 45000
  }
}
```

### Acoustic Sensor Message

**Topic**: `smdh/{tenant_id}/{site_id}/sensor-data`

**Payload Example**:
```json
{
  "timestamp": "2025-01-22T14:35:22.123Z",
  "device_type": "acoustic_sensor",
  "device_model": "OpenSmartMonitor_Acoustic",
  "measurements": {
    "sound_level_db": 68.5,
    "sound_level_dba": 65.2,
    "frequency_hz": 1500,
    "peak_frequency_hz": 2000
  },
  "status": {
    "batteryLevel": 75,
    "signalStrength": -72,
    "uptime": 45000
  }
}
```

### Light Sensor Message

**Topic**: `smdh/{tenant_id}/{site_id}/sensor-data`

**Payload Example**:
```json
{
  "timestamp": "2025-01-22T14:35:22.123Z",
  "device_type": "light_sensor",
  "device_model": "OpenSmartMonitor_Light",
  "measurements": {
    "illuminance_lux": 450,
    "color_temperature_k": 4000,
    "cri_index": 90,
    "uv_index": 3
  },
  "status": {
    "batteryLevel": 90,
    "signalStrength": -60,
    "uptime": 45000
  }
}
```

### Milesight UG65 Gateway Telemetry

**Topic**: `smdh/{tenant_id}/{site_id}/sensor-data`

**Payload Example**:
```json
{
  "timestamp": "2025-01-22T14:35:22.123Z",
  "gateway_id": "gw_milesight_ug65_001",
  "model": "Milesight-UG65",
  "manufacturer": "Milesight",
  "firmware_version": "1.2.5",
  "status": "online",
  "uptime_seconds": 2592000,
  "system": {
    "cpu_usage_percent": 25.3,
    "memory_used_mb": 256,
    "memory_total_mb": 512,
    "disk_used_percent": 35.2,
    "temperature_celsius": 42.5
  },
  "lora_radio": {
    "channels_active": 8,
    "packets_received": 150230,
    "packets_transmitted": 85340,
    "error_rate_percent": 0.23,
    "uplink_utilization_percent": 12.5,
    "downlink_utilization_percent": 8.3
  },
  "connectivity": {
    "ethernet_connected": true,
    "ethernet_speed_mbps": 1000,
    "wifi_connected": false,
    "cellular_connected": false,
    "wan_ip": "192.168.1.100",
    "signal_strength_dbm": -45
  },
  "devices": {
    "connected_devices": 47,
    "devices_by_class": {
      "class_a": 35,
      "class_b": 8,
      "class_c": 4
    }
  }
}
```

## AWS IoT Rule Configuration

### Rule: route_to_kinesis

```sql
SELECT
  topic(2) as tenant_id,
  topic(3) as sensor_type,
  topic(4) as entity_id,
  * as payload,
  timestamp() as iot_timestamp
FROM 'smdh/+/+/+/#'
```

### Rule Action: Forward to Kinesis

```json
{
  "streamName": "smdh-sensor-data-stream",
  "partitionKey": "${topic(2)}_${topic(4)}",
  "roleArn": "arn:aws:iam::ACCOUNT:role/smdh-iot-kinesis-role"
}
```

## Snowflake Openflow Configuration

### Integration Setup

```sql
CREATE OR REPLACE INTEGRATION smdh_kinesis_integration
  TYPE = EXTERNAL_ACCESS
  DIRECTION = INBOUND
  CLOUD = AWS
  REGION = 'eu-west-2'
  AWS_ROLE_ARN = 'arn:aws:iam::ACCOUNT:role/smdh-snowflake-kinesis-role'
  AWS_EXTERNAL_ID = 'your-external-id';
```

### Stream Configuration

```sql
CREATE OR REPLACE STREAM smdh_ingest_stream
  ON TABLE raw.sensor_readings_staging;
```

## Field Mapping Tables

### PULSE → clamp_sensor_readings

| MQTT Field | Snowflake Column | Transformation | Notes |
|-----------|------------------|----------------|-------|
| deviceId | sensor_id | Direct | Sensor identifier |
| machineId | machine_id | Direct | FK to dim_machine |
| siteId | site_id | Direct | FK to dim_site |
| timestamp | timestamp | PARSE_TIMESTAMP | Convert ISO8601 to TIMESTAMP_NTZ |
| measurements.current_phase_a | current_phase_a | CAST to FLOAT | Phase A current |
| measurements.current_phase_b | current_phase_b | CAST to FLOAT | Phase B current |
| measurements.current_phase_c | current_phase_c | CAST to FLOAT | Phase C current |
| measurements.current_rms | current_rms | CAST to FLOAT | RMS current |
| measurements.voltage_nominal | voltage_nominal | CAST to FLOAT | Nominal voltage |
| measurements.power_factor | power_factor | CAST to FLOAT | Power factor |
| measurements.frequency | frequency | CAST to FLOAT | Line frequency |
| (entire payload) | raw_payload | VARIANT | Full JSON for audit |
| (generated) | ingestion_timestamp | CURRENT_TIMESTAMP() | Snowflake receipt time |
| (from IoT rule) | iot_timestamp | FROM payload | IoT Core timestamp |

### SENTINEL → vibration_readings

| MQTT Field | Snowflake Column | Transformation | Notes |
|-----------|------------------|----------------|-------|
| deviceId | sensor_id | Direct | Sensor identifier |
| machineId | machine_id | Direct | FK to dim_machine |
| timestamp | timestamp | PARSE_TIMESTAMP | Convert ISO8601 |
| measurements.vibration_x | vibration_x | CAST to FLOAT | X-axis vibration |
| measurements.vibration_y | vibration_y | CAST to FLOAT | Y-axis vibration |
| measurements.vibration_z | vibration_z | CAST to FLOAT | Z-axis vibration |
| measurements.vibration_rms | vibration_rms | CAST to FLOAT | RMS vibration |
| measurements.temperature | temperature | CAST to FLOAT | Sensor temperature |
| measurements.dominant_frequency | dominant_frequency | CAST to FLOAT | Peak frequency |
| (entire payload) | raw_payload | VARIANT | Full JSON |
| (generated) | ingestion_timestamp | CURRENT_TIMESTAMP() | Receipt time |

### HAVEN → environmental_readings

| MQTT Field | Snowflake Column | Transformation | Notes |
|-----------|------------------|----------------|-------|
| deviceId | sensor_id | Direct | Sensor identifier |
| zoneId | zone_id | Direct | FK to dim_zone |
| siteId | site_id | Direct | FK to dim_site |
| timestamp | timestamp | PARSE_TIMESTAMP | Convert ISO8601 |
| measurements.temperature | temperature | CAST to FLOAT | Ambient temp |
| measurements.humidity | humidity | CAST to FLOAT | Relative humidity |
| measurements.co2_ppm | co2_ppm | CAST to FLOAT | CO2 concentration |
| measurements.voc_index | voc_index | CAST to FLOAT | VOC index |
| measurements.particulates_pm25 | particulates_pm25 | CAST to FLOAT | PM2.5 |
| measurements.particulates_pm10 | particulates_pm10 | CAST to FLOAT | PM10 |
| measurements.noise_db | noise_db | CAST to FLOAT | Noise level |
| measurements.light_lux | light_lux | CAST to FLOAT | Light level |
| (entire payload) | raw_payload | VARIANT | Full JSON |

## Data Transformation Pipeline

### Stage 1: RAW to NORMALIZED (Power Metrics)

**Trigger**: Stream on `raw.clamp_sensor_readings`

**Transformation SQL**:
```sql
INSERT INTO normalized.power_metrics (
    tenant_id,
    machine_id,
    timestamp,
    real_power_kw,
    apparent_power_kva,
    power_factor,
    avg_current_amps,
    max_current_amps,
    voltage_volts,
    interval_minutes,
    energy_kwh
)
SELECT
    c.tenant_id,
    c.machine_id,
    c.timestamp,
    -- Real Power: P = √3 × V × I × PF (for 3-phase)
    CASE
        WHEN m.voltage_type = 'three_phase' THEN
            SQRT(3) * c.voltage_nominal *
            COALESCE(c.current_rms, (c.current_phase_a + c.current_phase_b + c.current_phase_c) / 3) *
            COALESCE(c.power_factor, m.default_power_factor, 0.85) / 1000
        ELSE
            c.voltage_nominal * c.current_rms *
            COALESCE(c.power_factor, m.default_power_factor, 0.85) / 1000
    END as real_power_kw,
    -- Apparent Power: S = √3 × V × I
    CASE
        WHEN m.voltage_type = 'three_phase' THEN
            SQRT(3) * c.voltage_nominal *
            COALESCE(c.current_rms, (c.current_phase_a + c.current_phase_b + c.current_phase_c) / 3) / 1000
        ELSE
            c.voltage_nominal * c.current_rms / 1000
    END as apparent_power_kva,
    COALESCE(c.power_factor, m.default_power_factor, 0.85) as power_factor,
    COALESCE(c.current_rms, (c.current_phase_a + c.current_phase_b + c.current_phase_c) / 3) as avg_current_amps,
    GREATEST(c.current_phase_a, c.current_phase_b, c.current_phase_c, c.current_rms) as max_current_amps,
    c.voltage_nominal as voltage_volts,
    1 as interval_minutes,
    -- Energy = Power × Time (1 minute = 1/60 hour)
    CASE
        WHEN m.voltage_type = 'three_phase' THEN
            SQRT(3) * c.voltage_nominal *
            COALESCE(c.current_rms, (c.current_phase_a + c.current_phase_b + c.current_phase_c) / 3) *
            COALESCE(c.power_factor, m.default_power_factor, 0.85) / 1000 * (1.0/60.0)
        ELSE
            c.voltage_nominal * c.current_rms *
            COALESCE(c.power_factor, m.default_power_factor, 0.85) / 1000 * (1.0/60.0)
    END as energy_kwh
FROM stream_clamp_sensor_readings s
JOIN raw.clamp_sensor_readings c ON s.reading_id = c.reading_id
JOIN mart.dim_machine m ON c.machine_id = m.machine_id
WHERE s.METADATA$ACTION = 'INSERT';
```

### Stage 2: Power Metrics to Machine States

**Trigger**: Task every 1 minute

**ML Process**:
1. Fetch last 1 minute of power_metrics
2. For each machine, lookup threshold from dim_machine
3. Classify state based on power vs thresholds
4. Insert into fact_machine_state

```sql
INSERT INTO mart.fact_machine_state (
    tenant_id,
    machine_id,
    timestamp_utc,
    date_key,
    hour_of_day,
    state,
    state_confidence,
    power_kw,
    current_amps,
    power_factor,
    interval_minutes,
    energy_kwh
)
SELECT
    p.tenant_id,
    p.machine_id,
    p.timestamp as timestamp_utc,
    DATE_TRUNC('day', p.timestamp) as date_key,
    HOUR(p.timestamp) as hour_of_day,
    -- State classification using GMM thresholds
    CASE
        WHEN p.real_power_kw <= m.threshold_off_max_kw THEN 'OFF'
        WHEN p.real_power_kw >= m.threshold_working_min_kw THEN 'WORKING'
        ELSE 'IDLE'
    END as state,
    -- Confidence score based on distance from thresholds
    CASE
        WHEN p.real_power_kw <= m.threshold_off_max_kw THEN
            1.0 - (p.real_power_kw / NULLIF(m.threshold_off_max_kw, 0))
        WHEN p.real_power_kw >= m.threshold_working_min_kw THEN
            (p.real_power_kw - m.threshold_working_min_kw) / NULLIF(p.real_power_kw, 0)
        ELSE 0.5
    END as state_confidence,
    p.real_power_kw as power_kw,
    p.avg_current_amps as current_amps,
    p.power_factor,
    p.interval_minutes,
    p.energy_kwh
FROM normalized.power_metrics p
JOIN mart.dim_machine m ON p.machine_id = m.machine_id
WHERE p.normalized_timestamp >= DATEADD(minute, -2, CURRENT_TIMESTAMP())
    AND NOT EXISTS (
        SELECT 1 FROM mart.fact_machine_state s
        WHERE s.machine_id = p.machine_id
            AND s.timestamp_utc = p.timestamp
    );
```

## Data Quality Checks

### Validation Rules

```sql
-- Check for missing critical fields
SELECT COUNT(*) as missing_current_readings
FROM raw.clamp_sensor_readings
WHERE current_rms IS NULL
    AND (current_phase_a IS NULL OR current_phase_b IS NULL OR current_phase_c IS NULL)
    AND ingestion_timestamp >= DATEADD(hour, -1, CURRENT_TIMESTAMP());

-- Check for out-of-range values
SELECT machine_id, timestamp, current_rms
FROM raw.clamp_sensor_readings
WHERE current_rms > 1000  -- Unrealistic current
    OR current_rms < 0
    AND ingestion_timestamp >= DATEADD(hour, -1, CURRENT_TIMESTAMP());

-- Check for data gaps
SELECT
    machine_id,
    MAX(timestamp) as last_reading,
    DATEDIFF(minute, MAX(timestamp), CURRENT_TIMESTAMP()) as minutes_ago
FROM raw.clamp_sensor_readings
GROUP BY machine_id
HAVING minutes_ago > 5;  -- Alert if no data for 5+ minutes
```

## Monitoring Queries

### Ingestion Rate

```sql
SELECT
    DATE_TRUNC('minute', ingestion_timestamp) as minute,
    COUNT(*) as records_ingested
FROM raw.clamp_sensor_readings
WHERE ingestion_timestamp >= DATEADD(hour, -1, CURRENT_TIMESTAMP())
GROUP BY 1
ORDER BY 1 DESC;
```

### Latency Monitoring

```sql
SELECT
    machine_id,
    AVG(DATEDIFF(second, timestamp, ingestion_timestamp)) as avg_latency_seconds,
    MAX(DATEDIFF(second, timestamp, ingestion_timestamp)) as max_latency_seconds
FROM raw.clamp_sensor_readings
WHERE ingestion_timestamp >= DATEADD(hour, -1, CURRENT_TIMESTAMP())
GROUP BY machine_id;
```

## Error Handling

### Dead Letter Queue

Messages that fail validation are routed to a DLQ table:

```sql
CREATE TABLE raw.failed_ingestion (
    failed_id VARCHAR(255) DEFAULT UUID_STRING(),
    raw_message VARIANT,
    error_message VARCHAR(5000),
    error_timestamp TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    retry_count NUMBER DEFAULT 0
);
```

### Retry Logic

Failed messages are automatically retried up to 3 times with exponential backoff.

## Backfill Procedures

If historical data needs to be ingested:

```sql
-- Backfill from S3 archived data
COPY INTO raw.clamp_sensor_readings
FROM @smdh_archive_stage/clamp_sensors/
FILE_FORMAT = (TYPE = 'JSON')
PATTERN = '.*[.]json'
ON_ERROR = 'CONTINUE';
```

## Next Steps

1. **Configure AWS IoT Rules** using the SQL templates above
2. **Set up Kinesis Stream** with appropriate partitioning
3. **Deploy Snowflake Openflow** connector
4. **Create Snowflake Streams and Tasks** for transformation pipeline
5. **Implement monitoring dashboards** for ingestion health
6. **Test end-to-end** with sample sensor data

## References

- [OpenSmartMonitor Documentation](../../docs/sensor-docs/)
- [AWS IoT Core Rules](https://docs.aws.amazon.com/iot/latest/developerguide/iot-rules.html)
- [Snowflake Openflow](https://docs.snowflake.com/en/user-guide/data-load-snowpipe-streaming-overview.html)