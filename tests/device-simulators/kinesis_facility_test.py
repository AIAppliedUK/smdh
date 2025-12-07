#!/usr/bin/env python3
"""
Kinesis Direct Facility Test

Sends simulated sensor data from a full manufacturing facility directly to Kinesis,
bypassing IoT Core. This tests the Kinesis → Openflow → Snowflake pipeline.

Usage:
    python kinesis_facility_test.py --tenant-id test_tenant --count 10
"""

import json
import time
import random
import argparse
import base64
from datetime import datetime
from typing import Dict, Any, List
import boto3
import logging

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)


class FacilityConfig:
    """Manufacturing facility configuration"""

    SITES = {
        'SITE_001': {
            'name': 'Manufacturing Floor - Main',
            'machines': [
                {'id': 'CNC_MACHINE_001', 'type': 'CNC', 'line': 'LINE_001'},
                {'id': 'CNC_MACHINE_002', 'type': 'CNC', 'line': 'LINE_001'},
                {'id': 'MILL_MACHINE_001', 'type': 'MILL', 'line': 'LINE_002'},
                {'id': 'MILL_MACHINE_002', 'type': 'MILL', 'line': 'LINE_002'},
            ],
            'zones': ['ZONE_FLOOR_001']
        },
        'SITE_002': {
            'name': 'Assembly Line',
            'machines': [
                {'id': 'ASSEMBLY_001', 'type': 'ASSEMBLY', 'line': 'LINE_003'},
                {'id': 'ASSEMBLY_002', 'type': 'ASSEMBLY', 'line': 'LINE_003'},
            ],
            'zones': ['ZONE_ASSEMBLY_001']
        }
    }


def generate_ug65_sensor_message(
    tenant_id: str,
    site_id: str,
    device_eui: str,
    device_name: str,
    sensor_type: str,
    data: Dict[str, Any]
) -> Dict[str, Any]:
    """Generate a UG65-format sensor message (LoRaWAN gateway format)"""

    return {
        'applicationId': 'smdh',
        'deviceEUI': device_eui,
        'deviceName': device_name,
        'time': datetime.utcnow().isoformat() + 'Z',
        'fPort': 85,
        'fCntUp': random.randint(1000, 9999),
        'adr': True,
        'confirmedUplink': False,
        'data': data,
        'rx': {
            'gatewayEUI': '24E124FFFEF35F39',
            'frequency': 868.1,
            'dataRate': 'SF9BW125',
            'rssi': random.randint(-110, -70),
            'snr': round(random.uniform(-5, 10), 1)
        },
        # IoT Rule enrichment fields
        'tenant_id': tenant_id,
        'site_id': site_id,
        'iot_timestamp': int(time.time() * 1000),
        'device_id': f'smdh-gateway-{tenant_id}-{site_id}'
    }


def generate_environmental_data() -> Dict[str, Any]:
    """Generate environmental sensor data (AM308/EM300 style)"""
    temperature = round(random.uniform(18, 28), 1)
    humidity = round(random.uniform(35, 65), 1)

    return {
        'temperature': temperature,
        'humidity': humidity,
        'co2': random.randint(400, 800),
        'tvoc': random.randint(50, 200),
        'pm25': round(random.uniform(5, 30), 1),
        'noise': round(random.uniform(50, 80), 1),
        'light': random.randint(200, 1000),
        'battery': random.randint(70, 100)
    }


def generate_clamp_sensor_data(power_state: str = 'WORKING') -> Dict[str, Any]:
    """Generate clamp current sensor data (power monitoring)"""

    if power_state == 'OFF':
        current = round(random.uniform(0.05, 0.15), 2)
    elif power_state == 'IDLE':
        current = round(random.uniform(2.0, 4.0), 2)
    else:  # WORKING
        current = round(random.uniform(12.0, 18.0), 2)

    voltage = round(random.uniform(395, 405), 1)
    power_factor = round(random.uniform(0.85, 0.98), 3)

    return {
        'sensorType': 'clamp_current',
        'current_phase_a': current + round(random.uniform(-0.5, 0.5), 2),
        'current_phase_b': current + round(random.uniform(-0.5, 0.5), 2),
        'current_phase_c': current + round(random.uniform(-0.5, 0.5), 2),
        'current_rms': current,
        'voltage': voltage,
        'power_factor': power_factor,
        'frequency': 50.0,
        'power_kw': round(current * voltage * power_factor * 1.732 / 1000, 2),
        'battery': random.randint(80, 100)
    }


def generate_vibration_data(power_state: str = 'WORKING') -> Dict[str, Any]:
    """Generate vibration sensor data"""

    if power_state == 'OFF':
        vibration = round(random.uniform(0.01, 0.05), 3)
        temp = round(random.uniform(18, 22), 1)
    elif power_state == 'IDLE':
        vibration = round(random.uniform(0.1, 0.3), 3)
        temp = round(random.uniform(25, 35), 1)
    else:  # WORKING
        vibration = round(random.uniform(0.3, 1.2), 3)
        temp = round(random.uniform(40, 60), 1)

    return {
        'sensorType': 'vibration',
        'vibration_x': vibration + round(random.uniform(-0.1, 0.1), 3),
        'vibration_y': vibration + round(random.uniform(-0.1, 0.1), 3),
        'vibration_z': vibration + round(random.uniform(-0.1, 0.1), 3),
        'vibration_rms': vibration,
        'temperature': temp,
        'dominant_frequency': round(random.uniform(50, 200), 1),
        'battery': random.randint(75, 100)
    }


def generate_device_status(device_id: str) -> Dict[str, Any]:
    """Generate device status message"""
    return {
        'sensorType': 'device_status',
        'status': random.choice(['online', 'online', 'online', 'low_battery']),
        'battery': random.randint(20, 100),
        'rssi': random.randint(-110, -60),
        'snr': round(random.uniform(-5, 15), 1),
        'firmware': '1.2.3',
        'uptime_hours': random.randint(1, 720)
    }


def send_facility_data(
    kinesis_client,
    stream_name: str,
    tenant_id: str,
    batch_count: int = 1
) -> int:
    """Send a complete facility snapshot to Kinesis"""

    messages_sent = 0
    records = []

    # Generate device EUI counter
    eui_counter = 1

    for site_id, site_config in FacilityConfig.SITES.items():
        # Environmental sensors for each zone
        for zone_id in site_config['zones']:
            device_eui = f'24E124ENV{eui_counter:06d}'
            eui_counter += 1

            device_name = f'AM308-Environmental-{zone_id}'
            data = generate_environmental_data()

            message = generate_ug65_sensor_message(
                tenant_id, site_id, device_eui, device_name, 'environmental', data
            )

            records.append({
                'Data': json.dumps(message).encode('utf-8'),
                'PartitionKey': f'{tenant_id}-{site_id}'
            })
            logger.info(f"  📊 Environmental: {device_name} - Temp: {data['temperature']}°C, Humidity: {data['humidity']}%")

        # Machine sensors
        for machine in site_config['machines']:
            machine_id = machine['id']
            machine_type = machine['type']

            # Determine power state
            power_state = random.choices(
                ['WORKING', 'IDLE', 'OFF'],
                weights=[0.7, 0.2, 0.1]
            )[0]

            # Clamp sensor (power monitoring)
            device_eui = f'24E124CLP{eui_counter:06d}'
            eui_counter += 1
            device_name = f'CT-Clamp-{machine_id}'
            data = generate_clamp_sensor_data(power_state)

            message = generate_ug65_sensor_message(
                tenant_id, site_id, device_eui, device_name, 'clamp', data
            )

            records.append({
                'Data': json.dumps(message).encode('utf-8'),
                'PartitionKey': f'{tenant_id}-{site_id}'
            })
            logger.info(f"  ⚡ Clamp: {device_name} - Current: {data['current_rms']}A, Power: {data['power_kw']}kW ({power_state})")

            # Vibration sensor (only for CNC and MILL machines)
            if machine_type in ['CNC', 'MILL']:
                device_eui = f'24E124VIB{eui_counter:06d}'
                eui_counter += 1
                device_name = f'Vibration-{machine_id}'
                data = generate_vibration_data(power_state)

                message = generate_ug65_sensor_message(
                    tenant_id, site_id, device_eui, device_name, 'vibration', data
                )

                records.append({
                    'Data': json.dumps(message).encode('utf-8'),
                    'PartitionKey': f'{tenant_id}-{site_id}'
                })
                logger.info(f"  📳 Vibration: {device_name} - RMS: {data['vibration_rms']}g, Temp: {data['temperature']}°C")

            # Device status (periodic)
            if random.random() < 0.3:  # 30% chance of status message
                device_eui = f'24E124STS{eui_counter:06d}'
                eui_counter += 1
                device_name = f'Status-{machine_id}'
                data = generate_device_status(machine_id)

                message = generate_ug65_sensor_message(
                    tenant_id, site_id, device_eui, device_name, 'status', data
                )

                records.append({
                    'Data': json.dumps(message).encode('utf-8'),
                    'PartitionKey': f'{tenant_id}-{site_id}'
                })
                logger.info(f"  📱 Status: {device_name} - Battery: {data['battery']}%, RSSI: {data['rssi']}dBm")

    # Send records to Kinesis in batches
    batch_size = 100
    for i in range(0, len(records), batch_size):
        batch = records[i:i + batch_size]
        try:
            response = kinesis_client.put_records(
                StreamName=stream_name,
                Records=batch
            )

            failed = response.get('FailedRecordCount', 0)
            if failed > 0:
                logger.warning(f"  ⚠️  {failed} records failed to send")

            messages_sent += len(batch) - failed

        except Exception as e:
            logger.error(f"  ❌ Failed to send batch: {e}")

    return messages_sent


def main():
    parser = argparse.ArgumentParser(description='Kinesis Direct Facility Test')
    parser.add_argument('--tenant-id', default='test_tenant', help='Tenant ID')
    parser.add_argument('--stream-name', default=None, help='Kinesis stream name (default: smdh-{tenant_id}-stream)')
    parser.add_argument('--region', default='eu-west-2', help='AWS region')
    parser.add_argument('--batches', type=int, default=3, help='Number of facility snapshots to send')
    parser.add_argument('--interval', type=int, default=5, help='Seconds between batches')

    args = parser.parse_args()

    stream_name = args.stream_name or f'smdh-{args.tenant_id}-stream'

    logger.info("=" * 70)
    logger.info("🏭 SMDH Kinesis Facility Test")
    logger.info("=" * 70)
    logger.info(f"Tenant ID:   {args.tenant_id}")
    logger.info(f"Stream:      {stream_name}")
    logger.info(f"Region:      {args.region}")
    logger.info(f"Batches:     {args.batches}")
    logger.info(f"Interval:    {args.interval}s")
    logger.info("=" * 70)

    # Create Kinesis client
    kinesis = boto3.client('kinesis', region_name=args.region)

    total_sent = 0

    for batch_num in range(1, args.batches + 1):
        logger.info(f"\n📦 Batch {batch_num}/{args.batches} - {datetime.utcnow().isoformat()}Z")
        logger.info("-" * 50)

        sent = send_facility_data(kinesis, stream_name, args.tenant_id, batch_num)
        total_sent += sent

        logger.info(f"\n✅ Batch {batch_num} complete: {sent} messages sent")

        if batch_num < args.batches:
            logger.info(f"⏳ Waiting {args.interval}s before next batch...")
            time.sleep(args.interval)

    logger.info("\n" + "=" * 70)
    logger.info(f"🎉 Test complete! Total messages sent: {total_sent}")
    logger.info("=" * 70)
    logger.info("\nNext steps:")
    logger.info("1. Check Openflow UI for data flow")
    logger.info("2. Query Snowflake:")
    logger.info(f'   SELECT COUNT(*) FROM SMDH_TENANT_{args.tenant_id.upper()}.RAW."SMDH-{args.tenant_id.upper()}-STREAM";')
    logger.info(f'   SELECT * FROM SMDH_TENANT_{args.tenant_id.upper()}.RAW.SENSOR_READINGS ORDER BY timestamp DESC LIMIT 10;')

    return 0


if __name__ == "__main__":
    exit(main())
