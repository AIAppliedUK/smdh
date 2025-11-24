#!/bin/bash

# SMDH MQTT Quick Test Script
# Uses mosquitto_pub for rapid testing without Python dependencies
# Perfect for quick connectivity and message format testing

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default values
DEFAULT_ENDPOINT=""
DEFAULT_TENANT="tenant-001"
DEFAULT_SITE="site_001"
DEFAULT_TOPIC_PREFIX="smdh"

# Function to display usage
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -e ENDPOINT    AWS IoT endpoint (required)"
    echo "  -c CERT        Path to device certificate (required)"
    echo "  -k KEY         Path to private key (required)"
    echo "  -r CA          Path to root CA certificate (required)"
    echo "  -t TENANT      Tenant ID (default: tenant-001)"
    echo "  -s SITE        Site ID (default: site_001)"
    echo "  -i CLIENT_ID   MQTT Client ID (required)"
    echo "  -m MODE        Test mode: simple|burst|continuous|subscribe (default: simple)"
    echo "  -n COUNT       Number of messages for burst mode (default: 10)"
    echo "  -d DURATION    Duration in seconds for continuous mode (default: 60)"
    echo "  -h             Show this help message"
    echo ""
    echo "Examples:"
    echo "  # Simple single message test"
    echo "  $0 -e xxx.iot.eu-west-1.amazonaws.com -c cert.pem -k private.key -r ca.pem -i device001"
    echo ""
    echo "  # Burst test with 20 messages"
    echo "  $0 -e xxx.iot.eu-west-1.amazonaws.com -c cert.pem -k private.key -r ca.pem -i device001 -m burst -n 20"
    echo ""
    echo "  # Subscribe to command topics"
    echo "  $0 -e xxx.iot.eu-west-1.amazonaws.com -c cert.pem -k private.key -r ca.pem -i device001 -m subscribe"
}

# Parse command line arguments
MODE="simple"
COUNT=10
DURATION=60

while getopts "e:c:k:r:t:s:i:m:n:d:h" opt; do
    case $opt in
        e) ENDPOINT="$OPTARG" ;;
        c) CERT="$OPTARG" ;;
        k) KEY="$OPTARG" ;;
        r) CA="$OPTARG" ;;
        t) TENANT="$OPTARG" ;;
        s) SITE="$OPTARG" ;;
        i) CLIENT_ID="$OPTARG" ;;
        m) MODE="$OPTARG" ;;
        n) COUNT="$OPTARG" ;;
        d) DURATION="$OPTARG" ;;
        h) usage; exit 0 ;;
        *) usage; exit 1 ;;
    esac
done

# Set defaults if not provided
TENANT=${TENANT:-$DEFAULT_TENANT}
SITE=${SITE:-$DEFAULT_SITE}

# Validate required parameters
if [[ -z "$ENDPOINT" || -z "$CERT" || -z "$KEY" || -z "$CA" || -z "$CLIENT_ID" ]]; then
    echo -e "${RED}Error: Missing required parameters${NC}"
    usage
    exit 1
fi

# Validate certificate files exist
for file in "$CERT" "$KEY" "$CA"; do
    if [[ ! -f "$file" ]]; then
        echo -e "${RED}Error: File not found: $file${NC}"
        exit 1
    fi
done

# Check if mosquitto is installed
if ! command -v mosquitto_pub &> /dev/null; then
    echo -e "${YELLOW}Warning: mosquitto_pub not found. Installing with brew...${NC}"
    if command -v brew &> /dev/null; then
        brew install mosquitto
    else
        echo -e "${RED}Error: mosquitto_pub not installed and brew not available${NC}"
        echo "Install mosquitto manually:"
        echo "  macOS: brew install mosquitto"
        echo "  Ubuntu: apt-get install mosquitto-clients"
        echo "  CentOS: yum install mosquitto"
        exit 1
    fi
fi

# Function to generate sensor data JSON
generate_sensor_data() {
    local msg_id=$1
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Generate random values
    local water_level=$(awk -v min=0.5 -v max=3.5 'BEGIN{srand(); print min+rand()*(max-min)}' | cut -c1-4)
    local flow_rate=$(awk -v min=0 -v max=100 'BEGIN{srand(); print min+rand()*(max-min)}' | cut -c1-5)
    local pressure=$(awk -v min=1.0 -v max=2.5 'BEGIN{srand(); print min+rand()*(max-min)}' | cut -c1-4)
    local temperature=$(awk -v min=15 -v max=25 'BEGIN{srand(); print min+rand()*(max-min)}' | cut -c1-4)
    local ph=$(awk -v min=6.5 -v max=8.5 'BEGIN{srand(); print min+rand()*(max-min)}' | cut -c1-3)
    local battery=$((70 + RANDOM % 31))
    local signal=$((-80 + RANDOM % 40))

    cat <<EOF
{
    "messageId": "msg_${msg_id}",
    "timestamp": "${timestamp}",
    "tenantId": "${TENANT}",
    "siteId": "${SITE}",
    "deviceType": "water_level_sensor",
    "measurements": {
        "waterLevel": ${water_level},
        "flowRate": ${flow_rate},
        "pressure": ${pressure},
        "temperature": ${temperature}
    },
    "quality": {
        "ph": ${ph},
        "turbidity": $(awk -v min=0 -v max=5 'BEGIN{srand(); print min+rand()*(max-min)}' | cut -c1-4),
        "conductivity": $((200 + RANDOM % 600))
    },
    "status": {
        "batteryLevel": ${battery},
        "signalStrength": ${signal},
        "uptime": $((1000 + RANDOM % 99000))
    }
}
EOF
}

# Function to publish a message
publish_message() {
    local topic="$1"
    local payload="$2"

    echo "$payload" | mosquitto_pub \
        -h "$ENDPOINT" \
        -p 8883 \
        --cafile "$CA" \
        --cert "$CERT" \
        --key "$KEY" \
        -i "$CLIENT_ID" \
        -t "$topic" \
        -q 1 \
        -d \
        -s

    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}✓ Message published to ${topic}${NC}"
        return 0
    else
        echo -e "${RED}✗ Failed to publish message${NC}"
        return 1
    fi
}

# Main test execution
echo -e "${GREEN}=====================================${NC}"
echo -e "${GREEN}SMDH IoT MQTT Testing Tool${NC}"
echo -e "${GREEN}=====================================${NC}"
echo ""
echo "Configuration:"
echo "  Endpoint:  $ENDPOINT"
echo "  Client ID: $CLIENT_ID"
echo "  Tenant:    $TENANT"
echo "  Site:      $SITE"
echo "  Mode:      $MODE"
echo ""

TOPIC="${DEFAULT_TOPIC_PREFIX}/${TENANT}/${SITE}/sensor-data"

case $MODE in
    simple)
        echo -e "${YELLOW}Sending single test message...${NC}"
        DATA=$(generate_sensor_data "000001")
        echo "Payload:"
        echo "$DATA" | jq . 2>/dev/null || echo "$DATA"
        echo ""
        publish_message "$TOPIC" "$DATA"
        ;;

    burst)
        echo -e "${YELLOW}Sending burst of ${COUNT} messages...${NC}"
        SUCCESS=0
        FAILED=0

        for i in $(seq 1 $COUNT); do
            MSG_ID=$(printf "%06d" $i)
            DATA=$(generate_sensor_data "$MSG_ID")
            echo -n "Message $i/$COUNT: "

            if publish_message "$TOPIC" "$DATA" >/dev/null 2>&1; then
                echo -e "${GREEN}✓${NC}"
                ((SUCCESS++))
            else
                echo -e "${RED}✗${NC}"
                ((FAILED++))
            fi

            sleep 0.1
        done

        echo ""
        echo -e "${GREEN}Results: ${SUCCESS} succeeded, ${FAILED} failed${NC}"
        ;;

    continuous)
        echo -e "${YELLOW}Starting continuous transmission for ${DURATION} seconds...${NC}"
        echo "Press Ctrl+C to stop"
        echo ""

        START_TIME=$(date +%s)
        MSG_COUNT=0

        while true; do
            CURRENT_TIME=$(date +%s)
            ELAPSED=$((CURRENT_TIME - START_TIME))

            if [[ $ELAPSED -ge $DURATION ]]; then
                break
            fi

            MSG_ID=$(printf "%06d" $((MSG_COUNT + 1)))
            DATA=$(generate_sensor_data "$MSG_ID")

            echo -n "[$ELAPSED/${DURATION}s] Message $((MSG_COUNT + 1)): "

            if publish_message "$TOPIC" "$DATA" >/dev/null 2>&1; then
                echo -e "${GREEN}✓${NC}"
                ((MSG_COUNT++))
            else
                echo -e "${RED}✗${NC}"
            fi

            sleep 5
        done

        echo ""
        echo -e "${GREEN}Transmission complete! Sent ${MSG_COUNT} messages${NC}"
        ;;

    subscribe)
        echo -e "${YELLOW}Subscribing to command topics...${NC}"
        echo "Topic: ${DEFAULT_TOPIC_PREFIX}/${TENANT}/commands/#"
        echo "Press Ctrl+C to stop"
        echo ""

        mosquitto_sub \
            -h "$ENDPOINT" \
            -p 8883 \
            --cafile "$CA" \
            --cert "$CERT" \
            --key "$KEY" \
            -i "$CLIENT_ID" \
            -t "${DEFAULT_TOPIC_PREFIX}/${TENANT}/commands/#" \
            -q 1 \
            -v \
            -d
        ;;

    *)
        echo -e "${RED}Error: Invalid mode: $MODE${NC}"
        usage
        exit 1
        ;;
esac

echo ""
echo -e "${GREEN}Test complete!${NC}"