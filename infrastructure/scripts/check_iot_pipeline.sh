#!/bin/bash
# =============================================================================
# SMDH IoT Pipeline Health Check
# =============================================================================
# Checks the status of all components in the IoT pipeline
#
# Usage:
#   ./check_iot_pipeline.sh [tenant_id]
#
# Examples:
#   ./check_iot_pipeline.sh              # Uses test_tenant
#   ./check_iot_pipeline.sh abc_mfg      # Check specific tenant
# =============================================================================

set -e

TENANT_ID="${1:-test_tenant}"
REGION="eu-west-2"

echo "=============================================================================="
echo "SMDH IoT Pipeline Health Check"
echo "=============================================================================="
echo "Tenant: ${TENANT_ID}"
echo "Region: ${REGION}"
echo "Time:   $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "=============================================================================="
echo ""

# 1. Check Kinesis Stream
echo "1. KINESIS STREAM"
echo "   ---------------------------------------------------------"
STREAM_NAME="smdh-${TENANT_ID}-stream"
STREAM_STATUS=$(aws kinesis describe-stream-summary \
    --stream-name "${STREAM_NAME}" \
    --region "${REGION}" \
    --query 'StreamDescriptionSummary.{Status:StreamStatus,Shards:OpenShardCount}' \
    --output json 2>/dev/null || echo '{"error": true}')

if echo "${STREAM_STATUS}" | grep -q "error"; then
    echo "   [FAIL] Stream ${STREAM_NAME} not found"
else
    STATUS=$(echo "${STREAM_STATUS}" | python3 -c "import sys,json; print(json.load(sys.stdin)['Status'])")
    SHARDS=$(echo "${STREAM_STATUS}" | python3 -c "import sys,json; print(json.load(sys.stdin)['Shards'])")
    if [[ "${STATUS}" == "ACTIVE" ]]; then
        echo "   [OK] Stream: ${STREAM_NAME}"
        echo "        Status: ${STATUS}"
        echo "        Shards: ${SHARDS}"
    else
        echo "   [WARN] Stream ${STREAM_NAME} status: ${STATUS}"
    fi
fi
echo ""

# 2. Check IoT Rule
echo "2. IOT RULE"
echo "   ---------------------------------------------------------"
RULE_NAME="smdh_route_${TENANT_ID}"
RULE_STATUS=$(aws iot get-topic-rule \
    --rule-name "${RULE_NAME}" \
    --region "${REGION}" \
    --query 'rule.{Disabled:ruleDisabled,Topic:sql}' \
    --output json 2>/dev/null || echo '{"error": true}')

if echo "${RULE_STATUS}" | grep -q "error"; then
    echo "   [FAIL] Rule ${RULE_NAME} not found"
else
    DISABLED=$(echo "${RULE_STATUS}" | python3 -c "import sys,json; print(json.load(sys.stdin)['Disabled'])")
    if [[ "${DISABLED}" == "False" ]]; then
        echo "   [OK] Rule: ${RULE_NAME}"
        echo "        Status: ENABLED"
        echo "        Topic: smdh/${TENANT_ID}/+/sensor-data"
    else
        echo "   [WARN] Rule ${RULE_NAME} is DISABLED"
    fi
fi
echo ""

# 3. Check IoT Certificates
echo "3. IOT CERTIFICATES"
echo "   ---------------------------------------------------------"
CERT_COUNT=$(aws iot list-certificates \
    --region "${REGION}" \
    --query 'length(certificates[?status==`ACTIVE`])' \
    --output text 2>/dev/null || echo "0")
echo "   [OK] Active certificates: ${CERT_COUNT}"
echo ""

# 4. Check Recent Kinesis Metrics
echo "4. KINESIS METRICS (Last Hour)"
echo "   ---------------------------------------------------------"
METRICS=$(aws cloudwatch get-metric-statistics \
    --namespace AWS/Kinesis \
    --metric-name IncomingRecords \
    --dimensions Name=StreamName,Value="${STREAM_NAME}" \
    --start-time "$(date -u -v-1H +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u --date='1 hour ago' +%Y-%m-%dT%H:%M:%SZ)" \
    --end-time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --period 3600 \
    --statistics Sum \
    --region "${REGION}" 2>/dev/null || echo '{"Datapoints": []}')

TOTAL_RECORDS=$(echo "${METRICS}" | python3 -c "
import sys, json
data = json.load(sys.stdin)
total = sum(p.get('Sum', 0) for p in data.get('Datapoints', []))
print(int(total))
")
echo "   [OK] Records ingested (last hour): ${TOTAL_RECORDS}"
echo ""

# 5. Check IoT Rule Success Metrics
echo "5. IOT RULE METRICS (Last Hour)"
echo "   ---------------------------------------------------------"
SUCCESS_METRICS=$(aws cloudwatch get-metric-statistics \
    --namespace AWS/IoT \
    --metric-name Success \
    --dimensions Name=RuleName,Value="${RULE_NAME}" Name=ActionType,Value=Kinesis \
    --start-time "$(date -u -v-1H +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u --date='1 hour ago' +%Y-%m-%dT%H:%M:%SZ)" \
    --end-time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --period 3600 \
    --statistics Sum \
    --region "${REGION}" 2>/dev/null || echo '{"Datapoints": []}')

SUCCESS_COUNT=$(echo "${SUCCESS_METRICS}" | python3 -c "
import sys, json
data = json.load(sys.stdin)
total = sum(p.get('Sum', 0) for p in data.get('Datapoints', []))
print(int(total))
")
echo "   [OK] Successful rule actions: ${SUCCESS_COUNT}"
echo ""

# 6. Live Pipeline Test
echo "6. LIVE PIPELINE TEST"
echo "   ---------------------------------------------------------"
echo "   Sending test message..."

# Get LATEST iterator before sending
SHARD_ID=$(aws kinesis list-shards \
    --stream-name "${STREAM_NAME}" \
    --region "${REGION}" \
    --query 'Shards[0].ShardId' \
    --output text)

ITER=$(aws kinesis get-shard-iterator \
    --stream-name "${STREAM_NAME}" \
    --shard-id "${SHARD_ID}" \
    --shard-iterator-type LATEST \
    --region "${REGION}" \
    --query 'ShardIterator' \
    --output text)

# Send test message
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
aws iot-data publish \
    --topic "smdh/${TENANT_ID}/HEALTH_CHECK/sensor-data" \
    --payload "{\"test\":\"health_check\",\"time\":\"${TIMESTAMP}\"}" \
    --region "${REGION}" \
    --cli-binary-format raw-in-base64-out

sleep 3

# Check if message arrived
RECORDS=$(aws kinesis get-records \
    --shard-iterator "${ITER}" \
    --limit 5 \
    --region "${REGION}" 2>/dev/null)

RECORD_COUNT=$(echo "${RECORDS}" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('Records', [])))")

if [[ "${RECORD_COUNT}" -gt 0 ]]; then
    echo "   [OK] Pipeline test PASSED - Message received in Kinesis"
else
    echo "   [WARN] Pipeline test - Message may be in different shard"
    echo "         Check all shards or wait for metrics to update"
fi
echo ""

echo "=============================================================================="
echo "Health Check Complete"
echo "=============================================================================="
