#!/usr/bin/env python3
"""
UG65 End-to-End Test - Sends properly formatted LoRaWAN messages through AWS IoT Core

This script simulates a Milesight UG65 gateway sending sensor data through the complete
SMDH pipeline: AWS IoT Core -> Kinesis -> Snowflake Openflow -> Snowflake Database

Message format follows the UG65 MQTT Integration Guide specification.

Usage:
    python ug65_e2e_test.py --tenant-id test_tenant --site-id SITE_001 --count 5
"""

import json
import time
import random
import argparse
from datetime import datetime
from typing import Dict, Any
from AWSIoTPythonSDK.MQTTLib import AWSIoTMQTTClient
import logging

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# Default paths relative to project root
DEFAULT_ENDPOINT = "a28fbiixmeupm0-ats.iot.eu-west-2.amazonaws.com"
DEFAULT_CA_PATH = "infrastructure/deployment/certificates/ca/AmazonRootCA1.pem"
DEFAULT_CERT_PATH = "infrastructure/deployment/certificates/test_tenant_site_001_certificate.pem"
DEFAULT_KEY_PATH = "infrastructure/deployment/certificates/test_tenant_site_001_private_key.pem"


class UG65Simulator:
    """Simulates a Milesight UG65 LoRaWAN gateway sending sensor data"""

    # Simulated device registry - realistic Milesight sensor EUIs
    DEVICES = {
        "AM308_001": {
            "deviceEUI": "24E124707E043923",
            "deviceName": "AM308-TempHumidity-Floor1",
            "type": "AM308",
            "sensors": ["temperature", "humidity", "co2", "battery"]
        },
        "AM308_002": {
            "deviceEUI": "24E124707E043924",
            "deviceName": "AM308-TempHumidity-Floor2",
            "type": "AM308",
            "sensors": ["temperature", "humidity", "co2", "battery"]
        },
        "EM300_001": {
            "deviceEUI": "24E124137C046591",
            "deviceName": "EM300-TH-Warehouse",
            "type": "EM300-TH",
            "sensors": ["temperature", "humidity", "battery"]
        },
        "VS121_001": {
            "deviceEUI": "24E124128D147832",
            "deviceName": "VS121-PeopleCounter-Entry",
            "type": "VS121",
            "sensors": ["people_count_all", "people_count_in", "people_count_out", "region_count"]
        },
        "WS303_001": {
            "deviceEUI": "24E124446C148295",
            "deviceName": "WS303-LeakDetector-Plant",
            "type": "WS303",
            "sensors": ["water_leak", "battery"]
        }
    }

    # Gateway EUI for the simulated UG65
    GATEWAY_EUI = "24E124FFFEF35F39"

    def __init__(self, endpoint: str, cert_path: str, key_path: str, ca_path: str, client_id: str):
        """Initialize the UG65 simulator"""
        self.client_id = client_id
        self.mqtt_client = AWSIoTMQTTClient(client_id)
        self.mqtt_client.configureEndpoint(endpoint, 8883)
        self.mqtt_client.configureCredentials(ca_path, key_path, cert_path)

        # Configure connection parameters
        self.mqtt_client.configureAutoReconnectBackoffTime(1, 32, 20)
        self.mqtt_client.configureOfflinePublishQueueing(-1)
        self.mqtt_client.configureDrainingFrequency(2)
        self.mqtt_client.configureConnectDisconnectTimeout(10)
        self.mqtt_client.configureMQTTOperationTimeout(5)

        self.frame_counter = random.randint(1, 1000)

    def connect(self) -> bool:
        """Connect to AWS IoT Core"""
        try:
            self.mqtt_client.connect()
            logger.info(f"Connected to AWS IoT Core as {self.client_id}")
            return True
        except Exception as e:
            logger.error(f"Failed to connect: {e}")
            return False

    def disconnect(self):
        """Disconnect from AWS IoT Core"""
        self.mqtt_client.disconnect()
        logger.info("Disconnected from AWS IoT Core")

    def _generate_rx_metadata(self) -> Dict[str, Any]:
        """Generate realistic LoRa radio metadata"""
        return {
            "gatewayEUI": self.GATEWAY_EUI,
            "frequency": random.choice([868.1, 868.3, 868.5, 867.1, 867.3, 867.5, 867.7, 867.9]),
            "dataRate": random.choice(["SF7BW125", "SF8BW125", "SF9BW125", "SF10BW125"]),
            "coderate": "4/5",
            "rssi": random.randint(-120, -60),
            "snr": round(random.uniform(-20.0, 10.0), 1)
        }

    def _generate_am308_data(self) -> Dict[str, Any]:
        """Generate AM308 environmental sensor data"""
        return {
            "temperature": round(random.uniform(18.0, 28.0), 1),
            "humidity": round(random.uniform(35.0, 65.0), 1),
            "co2": random.randint(400, 1200),
            "battery": random.randint(70, 100)
        }

    def _generate_em300_data(self) -> Dict[str, Any]:
        """Generate EM300-TH temperature/humidity data"""
        return {
            "temperature": round(random.uniform(15.0, 35.0), 1),
            "humidity": round(random.uniform(30.0, 80.0), 1),
            "battery": random.randint(60, 100)
        }

    def _generate_vs121_data(self) -> Dict[str, Any]:
        """Generate VS121 people counter data"""
        total = random.randint(0, 50)
        in_count = random.randint(0, total)
        out_count = total - in_count
        return {
            "people_count_all": total,
            "people_count_in": in_count,
            "people_count_out": out_count,
            "region_count": [random.randint(0, 10) for _ in range(4)]
        }

    def _generate_ws303_data(self) -> Dict[str, Any]:
        """Generate WS303 water leak detector data"""
        return {
            "water_leak": random.choice([0, 0, 0, 0, 1]),  # 20% chance of leak
            "battery": random.randint(50, 100)
        }

    def generate_ug65_message(self, device_id: str) -> Dict[str, Any]:
        """
        Generate a UG65-formatted uplink message following the MQTT integration spec

        Format follows docs/sensor-docs/Zoho WorkDrive/ug65_mqtt_integration.md
        """
        device = self.DEVICES[device_id]
        self.frame_counter += 1

        # Generate sensor data based on device type
        if device["type"] == "AM308":
            data = self._generate_am308_data()
        elif device["type"] == "EM300-TH":
            data = self._generate_em300_data()
        elif device["type"] == "VS121":
            data = self._generate_vs121_data()
        elif device["type"] == "WS303":
            data = self._generate_ws303_data()
        else:
            data = {"temperature": round(random.uniform(18.0, 28.0), 1)}

        # Build UG65 uplink message per spec
        message = {
            "applicationId": "smdh",
            "deviceEUI": device["deviceEUI"],
            "deviceName": device["deviceName"],
            "time": datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%S.") + f"{random.randint(0,999):03d}Z",
            "fPort": 85,
            "fCntUp": self.frame_counter,
            "adr": True,
            "confirmedUplink": False,
            "data": data,
            "rx": self._generate_rx_metadata()
        }

        return message

    def publish_message(self, tenant_id: str, site_id: str, message: Dict[str, Any]) -> bool:
        """Publish a UG65 message to the correct MQTT topic"""
        # Topic pattern must match IoT rule: smdh/{tenant_id}/{site_id}/sensor-data
        topic = f"smdh/{tenant_id}/{site_id}/sensor-data"

        try:
            message_json = json.dumps(message)
            self.mqtt_client.publish(topic, message_json, 1)
            logger.info(f"Published to {topic}: deviceEUI={message['deviceEUI']}")
            return True
        except Exception as e:
            logger.error(f"Failed to publish: {e}")
            return False


def run_e2e_test(args):
    """Run the end-to-end test"""
    logger.info("=" * 70)
    logger.info("UG65 End-to-End Test - SMDH IoT Pipeline")
    logger.info("=" * 70)
    logger.info(f"Tenant ID: {args.tenant_id}")
    logger.info(f"Site ID:   {args.site_id}")
    logger.info(f"Endpoint:  {args.endpoint}")
    logger.info(f"Messages:  {args.count}")
    logger.info("=" * 70)

    # Create simulator
    simulator = UG65Simulator(
        endpoint=args.endpoint,
        cert_path=args.cert,
        key_path=args.key,
        ca_path=args.ca,
        # Client ID must match policy pattern: smdh-gateway-{tenant_id}-*
        client_id=f"smdh-gateway-{args.tenant_id}-{args.site_id}"
    )

    # Connect
    if not simulator.connect():
        logger.error("Failed to connect to AWS IoT Core")
        return 1

    try:
        messages_sent = 0
        device_ids = list(UG65Simulator.DEVICES.keys())

        for i in range(args.count):
            # Cycle through devices
            device_id = device_ids[i % len(device_ids)]

            # Generate and publish message
            message = simulator.generate_ug65_message(device_id)

            if simulator.publish_message(args.tenant_id, args.site_id, message):
                messages_sent += 1
                logger.info(f"  [{i+1}/{args.count}] Sent {message['deviceName']}")
                logger.info(f"           Data: {json.dumps(message['data'])}")
            else:
                logger.warning(f"  [{i+1}/{args.count}] Failed to send message")

            # Wait between messages (except for last one)
            if i < args.count - 1:
                time.sleep(args.interval)

        logger.info("=" * 70)
        logger.info(f"Test Complete: {messages_sent}/{args.count} messages sent successfully")
        logger.info("=" * 70)
        logger.info("")
        logger.info("NEXT STEPS - Verify data in Snowflake:")
        logger.info("  1. Wait 1-2 minutes for Openflow to process")
        logger.info("  2. Run this query in Snowflake:")
        logger.info("")
        logger.info(f"  USE DATABASE SMDH_TENANT_{args.tenant_id.upper()};")
        logger.info("  SELECT * FROM raw.sensor_readings")
        logger.info("  WHERE ingestion_timestamp >= DATEADD(MINUTE, -10, CURRENT_TIMESTAMP())")
        logger.info("  ORDER BY ingestion_timestamp DESC;")
        logger.info("")

    except KeyboardInterrupt:
        logger.info("\nTest interrupted by user")
    finally:
        simulator.disconnect()

    return 0 if messages_sent == args.count else 1


def main():
    parser = argparse.ArgumentParser(
        description='UG65 End-to-End Test - Send LoRaWAN sensor data through SMDH pipeline',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Basic test with 5 messages
  python ug65_e2e_test.py --tenant-id test_tenant --site-id SITE_001

  # Extended test with 20 messages at 2-second intervals
  python ug65_e2e_test.py --tenant-id test_tenant --site-id SITE_001 --count 20 --interval 2

  # Use custom certificates
  python ug65_e2e_test.py --tenant-id abc_mfg --site-id SITE_001 \\
      --cert path/to/cert.pem --key path/to/key.pem
        """
    )

    parser.add_argument('--endpoint', default=DEFAULT_ENDPOINT,
                        help='AWS IoT endpoint')
    parser.add_argument('--cert', default=DEFAULT_CERT_PATH,
                        help='Path to device certificate')
    parser.add_argument('--key', default=DEFAULT_KEY_PATH,
                        help='Path to private key')
    parser.add_argument('--ca', default=DEFAULT_CA_PATH,
                        help='Path to CA certificate')
    parser.add_argument('--tenant-id', required=True,
                        help='Tenant ID (e.g., test_tenant)')
    parser.add_argument('--site-id', default='SITE_001',
                        help='Site ID for topic routing')
    parser.add_argument('--count', type=int, default=5,
                        help='Number of messages to send')
    parser.add_argument('--interval', type=float, default=1.0,
                        help='Interval between messages in seconds')

    args = parser.parse_args()
    return run_e2e_test(args)


if __name__ == "__main__":
    exit(main())
