#!/bin/bash
# =============================================================================
# SMDH IoT Pipeline E2E Test Script
# =============================================================================
# Tests the complete IoT pipeline: AWS IoT Core -> Kinesis -> Snowflake
#
# Usage:
#   ./test_iot_pipeline.sh [tenant_id] [site_id] [count]
#
# Examples:
#   ./test_iot_pipeline.sh                          # Uses defaults
#   ./test_iot_pipeline.sh test_tenant SITE_001 10  # Custom settings
# =============================================================================

set -e

# Configuration
TENANT_ID="${1:-test_tenant}"
SITE_ID="${2:-SITE_001}"
COUNT="${3:-5}"
REGION="eu-west-2"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Certificate paths
CERT_DIR="${PROJECT_ROOT}/infrastructure/deployment/certificates"
CERT_PATH="${CERT_DIR}/${TENANT_ID}_${SITE_ID}_certificate.pem"
KEY_PATH="${CERT_DIR}/${TENANT_ID}_${SITE_ID}_private_key.pem"
CA_PATH="${CERT_DIR}/ca/AmazonRootCA1.pem"

echo "=============================================================================="
echo "SMDH IoT Pipeline E2E Test"
echo "=============================================================================="
echo "Tenant ID:  ${TENANT_ID}"
echo "Site ID:    ${SITE_ID}"
echo "Count:      ${COUNT}"
echo "Region:     ${REGION}"
echo "=============================================================================="
echo ""

# Check if certificates exist
if [[ ! -f "${CERT_PATH}" ]] || [[ ! -f "${KEY_PATH}" ]]; then
    echo "WARNING: Certificate files not found for ${TENANT_ID}/${SITE_ID}"
    echo "  Expected: ${CERT_PATH}"
    echo "  Expected: ${KEY_PATH}"
    echo ""
    echo "Falling back to AWS CLI method (uses IAM credentials)..."
    echo ""
    USE_CLI=true
else
    USE_CLI=false
fi

if [[ "${USE_CLI}" == "true" ]]; then
    # Use AWS CLI to publish messages
    echo "Sending ${COUNT} UG65-formatted messages via AWS CLI..."
    echo ""

    DEVICES=(
        "24E124707E043923|AM308-TempHumidity-Floor1|temperature|21.8|humidity|48.5|co2|420|battery|92"
        "24E124137C046591|EM300-TH-Warehouse|temperature|18.3|humidity|55.2|battery|87"
        "24E124128D147832|VS121-PeopleCounter-Entry|people_count_all|42|people_count_in|25|people_count_out|17"
        "24E124446C148295|WS303-LeakDetector-Plant|water_leak|0|battery|95"
        "24E124707E043924|AM308-TempHumidity-Floor2|temperature|23.4|humidity|42.1|co2|580|battery|78"
    )

    for i in $(seq 1 ${COUNT}); do
        idx=$(( (i - 1) % ${#DEVICES[@]} ))
        IFS='|' read -r DEV_EUI DEV_NAME REST <<< "${DEVICES[$idx]}"
        TIMESTAMP=$(python3 -c "from datetime import datetime, timezone; print(datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%S.%f')[:-3] + 'Z')")
        FCNT=$((4000 + i))

        # Build data object dynamically
        DATA_JSON=$(echo "${DEVICES[$idx]}" | python3 -c "
import sys
parts = sys.stdin.read().strip().split('|')
data = {}
for i in range(2, len(parts), 2):
    key = parts[i]
    val = parts[i+1]
    try:
        if '.' in val:
            data[key] = float(val)
        else:
            data[key] = int(val)
    except:
        data[key] = val
import json
print(json.dumps(data))
")

        cat > /tmp/ug65_msg.json << EOF
{
  "applicationId": "smdh",
  "deviceEUI": "${DEV_EUI}",
  "deviceName": "${DEV_NAME}",
  "time": "${TIMESTAMP}",
  "fPort": 85,
  "fCntUp": ${FCNT},
  "adr": true,
  "confirmedUplink": false,
  "data": ${DATA_JSON},
  "rx": {
    "gatewayEUI": "24E124FFFEF35F39",
    "frequency": 868.1,
    "dataRate": "SF9BW125",
    "rssi": -95,
    "snr": 3.0
  }
}
EOF

        aws iot-data publish \
            --topic "smdh/${TENANT_ID}/${SITE_ID}/sensor-data" \
            --payload file:///tmp/ug65_msg.json \
            --region "${REGION}" \
            --cli-binary-format raw-in-base64-out

        echo "[${i}/${COUNT}] Sent: ${DEV_NAME}"
        sleep 0.5
    done
else
    # Use Python MQTT client
    echo "Sending ${COUNT} UG65-formatted messages via MQTT..."
    echo ""

    python3 "${PROJECT_ROOT}/tests/device-simulators/ug65_e2e_test.py" \
        --tenant-id "${TENANT_ID}" \
        --site-id "${SITE_ID}" \
        --count "${COUNT}" \
        --interval 1 \
        --cert "${CERT_PATH}" \
        --key "${KEY_PATH}" \
        --ca "${CA_PATH}"
fi

echo ""
echo "=============================================================================="
echo "Test Complete!"
echo "=============================================================================="
echo ""
echo "To verify data in Snowflake, run:"
echo ""
TENANT_UPPER=$(echo "${TENANT_ID}" | tr '[:lower:]' '[:upper:]')
echo "  USE DATABASE SMDH_TENANT_${TENANT_UPPER};"
echo "  SELECT * FROM raw.sensor_readings"
echo "  WHERE ingestion_timestamp >= DATEADD(MINUTE, -10, CURRENT_TIMESTAMP())"
echo "  ORDER BY ingestion_timestamp DESC;"
echo ""
