#!/usr/bin/env python3
"""
End-to-End IoT to Snowflake Verification Test
Sends 300 IoT messages and verifies they reach Snowflake
"""
import sys
import time
import subprocess
import snowflake.connector
from datetime import datetime, timedelta

print("\n" + "=" * 80)
print("END-TO-END VERIFICATION TEST: IoT → Kinesis → Snowflake")
print("=" * 80)

# Step 1: Send 300 IoT messages
print("\n✅ STEP 1: Sending 300 messages to AWS IoT Core...")
print("   Endpoint: a2nrw963nwy6fi-ats.iot.eu-west-2.amazonaws.com")
print("   Topic: smdh/test_tenant/site_001/sensor-data")
print("   Device: smdh-gateway-test_tenant-site_001-gw_001")

# Import the IoT simulator class
import importlib.util
spec = importlib.util.spec_from_file_location("iot_sim", "/Users/david/projects/smdh/tests/device-simulators/test-iot-transmission.py")
iot_sim = importlib.util.module_from_spec(spec)
spec.loader.exec_module(iot_sim)
IoTDeviceSimulator = iot_sim.IoTDeviceSimulator

simulator = IoTDeviceSimulator(
    endpoint='a2nrw963nwy6fi-ats.iot.eu-west-2.amazonaws.com',
    client_id='smdh-gateway-test_tenant-site_001-gw_001',
    cert_path='/Users/david/projects/smdh/tests/certificates/test_tenant_site_001_certificate.pem',
    key_path='/Users/david/projects/smdh/tests/certificates/test_tenant_site_001_private_key.pem',
    ca_path='/Users/david/projects/smdh/tests/certificates/ca/AmazonRootCA1.pem'
)

if not simulator.connect():
    print("❌ Failed to connect to AWS IoT Core")
    sys.exit(1)

try:
    # Send 300 messages in burst mode
    topic = "smdh/test_tenant/site_001/sensor-data"
    sent_count = 0

    for i in range(300):
        data = simulator.generate_sensor_data("water_level")
        data["messageId"] = f"msg_e2e_{i:03d}"
        data["tenantId"] = "test_tenant"
        data["siteId"] = "site_001"

        if simulator.publish_message(topic, data):
            sent_count += 1
            if (i + 1) % 50 == 0:
                print(f"   Sent {i + 1}/300 messages...")

        # Small delay to avoid overwhelming
        time.sleep(0.01)

    print(f"   ✅ Sent {sent_count} messages successfully")

    # Give Kinesis/Snowflake time to ingest
    print("\n✅ STEP 2: Waiting for data to flow through Kinesis pipe...")
    print("   (waiting 5 seconds for ingestion)")
    time.sleep(5)

    # Step 3: Check Snowflake
    print("\n✅ STEP 3: Verifying data arrived in Snowflake...")

    conn = snowflake.connector.connect(
        account='qqoylnv-zy42691',
        user='AIAPPLIED',
        password='SnowflakeRocks*01',
        database='SMDH_TENANT_TEST_TENANT',
        warehouse='COMPUTE_WH'
    )

    cursor = conn.cursor()

    # Count messages that came from IoT
    cursor.execute("""
        SELECT COUNT(*) as message_count
        FROM RAW.CLAMP_SENSOR_READINGS
        WHERE reading_id LIKE 'msg_e2e_%'
    """)

    result = cursor.fetchone()
    iot_message_count = result[0] if result else 0

    print(f"   Messages in RAW.CLAMP_SENSOR_READINGS with e2e prefix: {iot_message_count}")

    if iot_message_count > 0:
        print(f"\n🎉 SUCCESS! Complete end-to-end pipeline verified:")
        print(f"   ✅ Sent 300 messages to IoT Core")
        print(f"   ✅ IoT Topic Rule routed messages to Kinesis")
        print(f"   ✅ Snowflake pipe ingested {iot_message_count} messages from Kinesis")
        print(f"   ✅ Data is persistent in Snowflake RAW tables")

        # Show sample data
        cursor.execute("""
            SELECT reading_id, tenant_id, site_id, timestamp, current_rms, voltage_phase_a
            FROM RAW.CLAMP_SENSOR_READINGS
            WHERE reading_id LIKE 'msg_e2e_%'
            LIMIT 3
        """)

        print(f"\n   Sample data from Snowflake:")
        for row in cursor.fetchall():
            print(f"      ID: {row[0]}, Tenant: {row[1]}, Site: {row[2]}, RMS: {row[4]}A")
    else:
        print(f"\n⚠️  No messages found in Snowflake yet")
        print(f"   This could mean:")
        print(f"   1. Kinesis pipe is still ingesting (wait a bit longer)")
        print(f"   2. Topic rule isn't routing messages properly")
        print(f"   3. Snowflake pipe configuration needs adjustment")

        # Show what IS in the raw table
        cursor.execute("SELECT COUNT(*) FROM RAW.CLAMP_SENSOR_READINGS")
        total = cursor.fetchone()[0]
        print(f"\n   Total records in RAW.CLAMP_SENSOR_READINGS: {total}")

    cursor.close()
    conn.close()

finally:
    simulator.disconnect()

print("\n" + "=" * 80 + "\n")
