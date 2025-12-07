# SMDH IoT Pipeline Testing Suite

Testing toolkit for validating the complete IoT data pipeline: IoT Core → Kinesis → Snowflake.

## Test Organization

```
tests/
├── device-simulators/           # IoT device simulation tools
│   ├── ug65_e2e_test.py        # UG65 LoRaWAN format via MQTT (full pipeline)
│   ├── kinesis_facility_test.py # Direct Kinesis test (bypasses IoT Core)
│   └── test-iot-transmission.py # Generic IoT device simulator
├── scripts/                     # Bash utility scripts
│   ├── mqtt-quick-test.sh
│   └── cert-helper.sh
├── api-testing/                 # REST API testing collections
│   └── smdh-iot-postman-collection.json
├── conftest.py                  # Pytest fixtures
├── requirements.txt             # Python dependencies
└── README.md                    # This file
```

## Test Files Overview

| File | Purpose | Pipeline Coverage |
|------|---------|-------------------|
| `ug65_e2e_test.py` | UG65 LoRaWAN gateway MQTT test | IoT Core → Kinesis → Openflow → Snowflake |
| `kinesis_facility_test.py` | Direct Kinesis ingestion test | Kinesis → Openflow → Snowflake |
| `test-iot-transmission.py` | Generic MQTT device simulator | IoT Core → Kinesis |

## Quick Start

### 1. Install Dependencies

```bash
pip install -r requirements.txt

# macOS - Install mosquitto for MQTT testing
brew install mosquitto
```

### 2. Get Certificates

Certificates are stored in `infrastructure/deployment/certificates/`:
```
certificates/
├── ca/AmazonRootCA1.pem
├── {tenant_id}_{site_id}_certificate.pem
└── {tenant_id}_{site_id}_private_key.pem
```

### 3. Get IoT Endpoint

```bash
aws iot describe-endpoint --endpoint-type iot:Data-ATS --region eu-west-2
```

## Testing Methods

### Method 1: UG65 E2E Test (Full Pipeline via MQTT)

Tests the complete pipeline: IoT Core → Kinesis → Openflow → Snowflake

```bash
cd tests/device-simulators

python ug65_e2e_test.py \
    --tenant-id manufacturing_demo \
    --site-id SITE_001 \
    --count 5
```

**Options:**
| Parameter | Default | Description |
|-----------|---------|-------------|
| `--tenant-id` | `test_tenant` | Tenant identifier |
| `--site-id` | `SITE_001` | Site identifier |
| `--count` | `5` | Number of messages to send |
| `--interval` | `2` | Seconds between messages |
| `--cert` | Auto-detected | Path to certificate |
| `--key` | Auto-detected | Path to private key |

**Message Format:** Milesight UG65 LoRaWAN gateway format:
```json
{
  "applicationId": "smdh",
  "deviceEUI": "24E124707E043923",
  "deviceName": "AM308-TempHumidity-Floor1",
  "time": "2025-12-06T10:30:00.123Z",
  "data": {
    "temperature": 22.5,
    "humidity": 48.2,
    "co2": 520
  },
  "rx": {
    "gatewayEUI": "24E124FFFEF35F39",
    "rssi": -102,
    "snr": 5.2
  }
}
```

### Method 2: Kinesis Direct Test (Bypasses IoT Core)

Tests Kinesis → Openflow → Snowflake without needing IoT certificates:

```bash
cd tests/device-simulators

python kinesis_facility_test.py \
    --tenant-id manufacturing_demo \
    --batches 3 \
    --interval 5
```

**Options:**
| Parameter | Default | Description |
|-----------|---------|-------------|
| `--tenant-id` | `test_tenant` | Tenant identifier |
| `--stream-name` | Auto-generated | Kinesis stream name |
| `--region` | `eu-west-2` | AWS region |
| `--batches` | `3` | Number of facility snapshots |
| `--interval` | `5` | Seconds between batches |

**Simulated Sensors:**
- Environmental (temperature, humidity, CO2, TVOC, PM2.5, noise, light)
- Clamp current (3-phase power monitoring)
- Vibration (x/y/z axis, RMS, temperature)
- Device status (battery, RSSI, firmware)

### Method 3: Generic MQTT Test

For custom device simulation:

```bash
python tests/device-simulators/test-iot-transmission.py \
    --endpoint a28fbiixmeupm0-ats.iot.eu-west-2.amazonaws.com \
    --cert path/to/certificate.pem \
    --key path/to/private_key.pem \
    --ca path/to/AmazonRootCA1.pem \
    --client-id smdh-gateway-manufacturing_demo-SITE_001 \
    --tenant-id manufacturing_demo \
    --site-id SITE_001 \
    --mode single
```

## Verification

### Check Data in Snowflake

```sql
USE DATABASE SMDH_TENANT_MANUFACTURING_DEMO;

-- Check landing table (raw Openflow data)
SELECT COUNT(*) FROM RAW."SMDH-MANUFACTURING_DEMO-STREAM";

-- Check routed data in typed tables
SELECT 'sensor_readings' AS tbl, COUNT(*) FROM RAW.SENSOR_READINGS
UNION ALL SELECT 'environmental', COUNT(*) FROM RAW.ENVIRONMENTAL_READINGS
UNION ALL SELECT 'power_readings', COUNT(*) FROM RAW.POWER_READINGS;

-- View recent data
SELECT * FROM RAW.SENSOR_READINGS
WHERE ingestion_timestamp >= DATEADD(MINUTE, -10, CURRENT_TIMESTAMP())
ORDER BY ingestion_timestamp DESC
LIMIT 20;
```

### Check AWS Pipeline

```bash
# Check Kinesis stream
aws kinesis describe-stream-summary \
    --stream-name smdh-manufacturing_demo-stream \
    --region eu-west-2

# Check IoT rule metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/IoT \
    --metric-name RuleMessageThrottled \
    --dimensions Name=RuleName,Value=smdh_route_manufacturing_demo \
    --start-time $(date -u -v-1H +%Y-%m-%dT%H:%M:%SZ) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
    --period 300 \
    --statistics Sum \
    --region eu-west-2
```

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Certificate errors | Check permissions: `chmod 600 *.pem` |
| Connection refused | Verify IoT endpoint and port 8883 |
| Messages not in Kinesis | Check IoT Rule is enabled |
| No data in Snowflake | Check Openflow connector is running |
| Data in landing table but not typed tables | Check routing task is resumed |

### Debug Commands

```bash
# Test certificate validity
openssl x509 -in cert.pem -text -noout | grep -A2 "Validity"

# Test connectivity
openssl s_client -connect a28fbiixmeupm0-ats.iot.eu-west-2.amazonaws.com:8883 \
    -cert cert.pem -key key.pem -CAfile AmazonRootCA1.pem

# Check IoT Core logs
aws logs tail /aws/iot/smdh --follow --region eu-west-2
```

## Security Notes

1. **Never commit certificates to git** - They're in `.gitignore`
2. **Store certificates securely** - Use AWS Secrets Manager for production
3. **Use least privilege** - Devices only publish to their tenant/site topics
