# SMDH IoT Infrastructure Testing Suite

Complete testing toolkit for validating data transmission from devices to the AWS IoT infrastructure.

## 📁 Test Organization

```
tests/
├── device-simulators/     # IoT device simulation tools
│   └── test-iot-transmission.py
├── scripts/              # Bash utility scripts
│   ├── mqtt-quick-test.sh
│   └── cert-helper.sh
├── api-testing/          # REST API testing collections
│   └── smdh-iot-postman-collection.json
├── integration/          # Integration test scripts
│   └── validate-data-flow.py
├── e2e/                  # End-to-end test scenarios
├── unit/                 # Unit tests
├── requirements.txt      # Python dependencies
└── README.md            # This file
```

## 📁 Test Files Overview

| File | Location | Purpose | Type |
|------|----------|---------|------|
| `test-iot-transmission.py` | `device-simulators/` | Full-featured Python IoT device simulator | Python/MQTT |
| `mqtt-quick-test.sh` | `scripts/` | Lightweight bash script for quick MQTT tests | Bash/mosquitto |
| `smdh-iot-postman-collection.json` | `api-testing/` | REST API testing collection | Postman |
| `cert-helper.sh` | `scripts/` | Certificate management and extraction | Bash |
| `validate-data-flow.py` | `integration/` | End-to-end data flow validation | Python/AWS SDK |

## 🚀 Quick Start

### 1. Install Dependencies

```bash
# Python dependencies
pip install -r requirements.txt

# macOS - Install mosquitto for MQTT testing
brew install mosquitto

# Linux - Install mosquitto
sudo apt-get install mosquitto-clients  # Ubuntu/Debian
sudo yum install mosquitto              # CentOS/RHEL
```

### 2. Extract Certificates

First, extract device certificates from Terraform state:

```bash
# Download AWS Root CA
./scripts/cert-helper.sh download-ca

# Extract certificates for a specific device
./scripts/cert-helper.sh extract-cert -t tenant-001 -s site_001 -d gw_001

# Your certificates will be in:
# ./certificates/tenant-001/site_001/
```

### 3. Get IoT Endpoint

```bash
# Get your IoT endpoint
aws iot describe-endpoint --endpoint-type iot:Data-ATS --region eu-west-1

# Should return something like:
# xxx123xxx.iot.eu-west-1.amazonaws.com
```

## 🧪 Testing Methods

### Method 1: Python Device Simulator (Recommended)

The most comprehensive testing tool with realistic sensor data generation:

```bash
# Single message test
python device-simulators/test-iot-transmission.py \
    --endpoint xxx.iot.eu-west-1.amazonaws.com \
    --cert certificates/tenant-001/site_001/gw_001_certificate.pem \
    --key certificates/tenant-001/site_001/gw_001_private_key.pem \
    --ca certificates/ca/AmazonRootCA1.pem \
    --client-id smdh-gateway-tenant-001-site_001-gw_001 \
    --tenant-id tenant-001 \
    --site-id site_001 \
    --mode single

# Continuous simulation (60 seconds, message every 10 seconds)
python device-simulators/test-iot-transmission.py \
    --endpoint xxx.iot.eu-west-1.amazonaws.com \
    --cert certificates/tenant-001/site_001/gw_001_certificate.pem \
    --key certificates/tenant-001/site_001/gw_001_private_key.pem \
    --ca certificates/ca/AmazonRootCA1.pem \
    --client-id smdh-gateway-tenant-001-site_001-gw_001 \
    --tenant-id tenant-001 \
    --site-id site_001 \
    --mode continuous \
    --interval 10 \
    --duration 60

# Burst mode (send 20 messages quickly)
python device-simulators/test-iot-transmission.py \
    --endpoint xxx.iot.eu-west-1.amazonaws.com \
    --cert certificates/tenant-001/site_001/gw_001_certificate.pem \
    --key certificates/tenant-001/site_001/gw_001_private_key.pem \
    --ca certificates/ca/AmazonRootCA1.pem \
    --client-id smdh-gateway-tenant-001-site_001-gw_001 \
    --tenant-id tenant-001 \
    --mode burst \
    --burst-count 20
```

### Method 2: Quick MQTT Test (Bash)

For rapid connectivity testing without Python dependencies:

```bash
# Make script executable
chmod +x scripts/mqtt-quick-test.sh

# Simple test
./scripts/mqtt-quick-test.sh \
    -e xxx.iot.eu-west-1.amazonaws.com \
    -c certificates/tenant-001/site_001/gw_001_certificate.pem \
    -k certificates/tenant-001/site_001/gw_001_private_key.pem \
    -r certificates/ca/AmazonRootCA1.pem \
    -i smdh-gateway-tenant-001-site_001-gw_001 \
    -t tenant-001 \
    -s site_001

# Burst test
./scripts/mqtt-quick-test.sh \
    -e xxx.iot.eu-west-1.amazonaws.com \
    -c certificates/tenant-001/site_001/gw_001_certificate.pem \
    -k certificates/tenant-001/site_001/gw_001_private_key.pem \
    -r certificates/ca/AmazonRootCA1.pem \
    -i smdh-gateway-tenant-001-site_001-gw_001 \
    -m burst \
    -n 10

# Subscribe to command topics
./scripts/mqtt-quick-test.sh \
    -e xxx.iot.eu-west-1.amazonaws.com \
    -c certificates/tenant-001/site_001/gw_001_certificate.pem \
    -k certificates/tenant-001/site_001/gw_001_private_key.pem \
    -r certificates/ca/AmazonRootCA1.pem \
    -i smdh-gateway-tenant-001-site_001-gw_001 \
    -m subscribe
```

### Method 3: Postman REST API Testing

For testing AWS IoT REST API endpoints:

1. Import `api-testing/smdh-iot-postman-collection.json` into Postman
2. Configure environment variables:
   - `IOT_ENDPOINT`: Your IoT endpoint
   - `AWS_ACCESS_KEY`: Your AWS access key
   - `AWS_SECRET_KEY`: Your AWS secret key
   - `AWS_REGION`: Your AWS region
   - `TENANT_ID`: Tenant to test (e.g., tenant-001)
   - `SITE_ID`: Site to test (e.g., site_001)

3. Run individual requests or use Collection Runner for bulk testing

### Method 4: End-to-End Validation

Validate complete data flow from IoT Core to Kinesis:

```bash
# Run end-to-end test
python integration/validate-data-flow.py \
    --region eu-west-1 \
    --stream smdh-sensor-data-stream \
    --tenant tenant-001 \
    --site site_001 \
    --mode test \
    --messages 5 \
    --wait 30

# Continuous monitoring for 5 minutes
python integration/validate-data-flow.py \
    --region eu-west-1 \
    --stream smdh-sensor-data-stream \
    --tenant tenant-001 \
    --site site_001 \
    --mode monitor \
    --duration 5

# Check CloudWatch metrics only
python integration/validate-data-flow.py \
    --region eu-west-1 \
    --stream smdh-sensor-data-stream \
    --tenant tenant-001 \
    --mode metrics
```

## 📊 Data Formats

### Sensor Data Message Format

```json
{
  "messageId": "msg_000001",
  "timestamp": "2024-01-15T10:30:00Z",
  "tenantId": "tenant-001",
  "siteId": "site_001",
  "deviceType": "water_level_sensor",
  "measurements": {
    "waterLevel": 2.5,
    "flowRate": 45.2,
    "pressure": 1.8,
    "temperature": 22.3
  },
  "quality": {
    "ph": 7.2,
    "turbidity": 0.5,
    "conductivity": 450
  },
  "status": {
    "batteryLevel": 85,
    "signalStrength": -65,
    "uptime": 15000
  }
}
```

### Device Status Message Format

```json
{
  "messageId": "status_000001",
  "timestamp": "2024-01-15T10:30:00Z",
  "tenantId": "tenant-001",
  "siteId": "site_001",
  "deviceType": "gateway",
  "status": "online",
  "systemInfo": {
    "uptime": 86400,
    "cpuUsage": 35.5,
    "memoryUsage": 42.3,
    "diskUsage": 28.7,
    "temperature": 45.2
  },
  "network": {
    "connectedDevices": 12,
    "packetsReceived": 5432,
    "packetsTransmitted": 5410,
    "errorRate": 0.004
  }
}
```

## 🔍 Verification Steps

### 1. Check IoT Core Reception

```bash
# Check IoT Core logs in CloudWatch
aws logs tail /aws/iot/smdh --follow --region eu-west-1
```

### 2. Verify Kinesis Data

```bash
# Check if data is arriving in Kinesis
aws kinesis describe-stream \
    --stream-name smdh-sensor-data-stream \
    --region eu-west-1

# Get records from Kinesis
aws kinesis get-shard-iterator \
    --stream-name smdh-sensor-data-stream \
    --shard-id shardId-000000000000 \
    --shard-iterator-type LATEST \
    --region eu-west-1
```

### 3. Monitor CloudWatch Metrics

```bash
# Check IoT metrics
aws cloudwatch get-metric-statistics \
    --namespace AWS/IoT \
    --metric-name PublishIn.Success \
    --start-time 2024-01-15T00:00:00Z \
    --end-time 2024-01-15T23:59:59Z \
    --period 3600 \
    --statistics Sum \
    --region eu-west-1
```

## 🛠️ Troubleshooting

### Common Issues and Solutions

| Issue | Solution |
|-------|----------|
| Certificate errors | Ensure certificates have correct permissions (600 for private key) |
| Connection refused | Verify IoT endpoint is correct and port 8883 is open |
| Messages not in Kinesis | Check IoT Rule is enabled and targeting correct stream |
| Authentication failed | Verify device is registered and certificate is attached |
| No data in CloudWatch | Wait 5-10 minutes for metrics to appear |

### Debug Commands

```bash
# Test certificate validity
openssl x509 -in certificates/tenant-001/site_001/gw_001_certificate.pem -text -noout

# Test connectivity
openssl s_client -connect xxx.iot.eu-west-1.amazonaws.com:8883 \
    -cert certificates/tenant-001/site_001/gw_001_certificate.pem \
    -key certificates/tenant-001/site_001/gw_001_private_key.pem \
    -CAfile certificates/ca/AmazonRootCA1.pem

# Check IoT thing status
aws iot describe-thing \
    --thing-name smdh-gateway-tenant-001-site_001-gw_001 \
    --region eu-west-1

# List IoT rules
aws iot list-topic-rules --region eu-west-1
```

## 📈 Load Testing

For load testing, use the Python simulator in burst mode with multiple processes:

```bash
# Run 10 parallel simulators, each sending 100 messages
for i in {1..10}; do
    python device-simulators/test-iot-transmission.py \
        --endpoint xxx.iot.eu-west-1.amazonaws.com \
        --cert certificates/tenant-001/site_001/gw_001_certificate.pem \
        --key certificates/tenant-001/site_001/gw_001_private_key.pem \
        --ca certificates/ca/AmazonRootCA1.pem \
        --client-id smdh-gateway-tenant-001-site_001-gw_001-$i \
        --tenant-id tenant-001 \
        --mode burst \
        --burst-count 100 &
done

# Wait for all to complete
wait
```

## 🔐 Security Notes

1. **Never commit certificates or keys to git**
   - Add `certificates/` to `.gitignore`
   - Store securely in AWS Secrets Manager or Parameter Store

2. **Rotate certificates regularly**
   - AWS IoT certificates don't expire by default
   - Implement rotation policy based on your security requirements

3. **Use least privilege policies**
   - Devices should only publish to their tenant/site topics
   - Restrict subscribe permissions to necessary command topics

## 📚 Additional Resources

- [AWS IoT Core Documentation](https://docs.aws.amazon.com/iot/latest/developerguide/)
- [MQTT Protocol Specification](http://docs.oasis-open.org/mqtt/mqtt/v3.1.1/mqtt-v3.1.1.html)
- [AWS IoT Device SDK](https://github.com/aws/aws-iot-device-sdk-python)
- [Mosquitto Documentation](https://mosquitto.org/documentation/)

## 💡 Tips

1. Start with the bash MQTT test for quick connectivity validation
2. Use the Python simulator for realistic data patterns
3. Validate end-to-end flow after any infrastructure changes
4. Monitor CloudWatch metrics during load tests
5. Use Postman collection for API-level troubleshooting

## 🤝 Contributing

When adding new test scenarios:
1. Follow existing naming conventions
2. Include clear documentation
3. Add sample commands to this README
4. Test with multiple tenant configurations