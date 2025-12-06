#!/bin/bash
# Send test records to Kinesis stream

STREAM_NAME="smdh-test_tenant-stream"
REGION="eu-west-2"

for i in 1 2 3 4 5; do
  TEMP=$((20 + i))
  HUMIDITY=$((40 + i))

  JSON="{\"applicationId\":\"smdh\",\"deviceEUI\":\"24E124707E043923\",\"deviceName\":\"AM308-Test\",\"time\":\"2025-12-05T08:30:0${i}.000Z\",\"fPort\":85,\"data\":{\"temperature\":${TEMP},\"humidity\":${HUMIDITY}},\"tenant_id\":\"test_tenant\",\"site_id\":\"SITE_001\"}"

  # Base64 encode
  B64=$(printf '%s' "$JSON" | base64)

  echo "Sending record $i..."
  aws kinesis put-record \
    --stream-name "$STREAM_NAME" \
    --partition-key "test_tenant-SITE_001" \
    --data "$B64" \
    --region "$REGION"

  sleep 1
done

echo "Done sending 5 test records"
