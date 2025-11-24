#!/usr/bin/env python3
"""
Realistic Manufacturing Facility Simulator

Simulates a complete multi-site manufacturing facility with:
- Multiple production lines and machines
- Various sensor types (power, vibration, environmental)
- Realistic production schedules and shift patterns
- Real-world equipment behavior

This generates much more realistic test data than single-sensor simulators.

Usage:
    # Simulate ABC Mfg facility for 1 hour (1-minute intervals)
    python realistic_facility_simulator.py \
        --endpoint your-iot-endpoint \
        --cert your-cert.pem \
        --key your-key.pem \
        --ca AmazonRootCA1.pem \
        --duration 3600 \
        --interval 60 \
        --tenant-id abc_mfg

    # Simulate a single shift (8 hours) with 5-minute intervals
    python realistic_facility_simulator.py \
        --endpoint your-iot-endpoint \
        --cert your-cert.pem \
        --key your-key.pem \
        --ca AmazonRootCA1.pem \
        --duration 28800 \
        --interval 300 \
        --tenant-id abc_mfg
"""

import json
import time
import random
import argparse
from datetime import datetime, timedelta
from typing import Dict, List, Any
from AWSIoTPythonSDK.MQTTLib import AWSIoTMQTTClient
import logging

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)


class RealisticFacilitySimulator:
    """Simulates a realistic manufacturing facility with multiple sites and machines"""

    def __init__(self, endpoint: str, client_id: str, cert_path: str, key_path: str, ca_path: str):
        """Initialize the facility simulator"""
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

        # Facility configuration
        self.facilities = self._setup_facility_config()

    def _setup_facility_config(self) -> Dict[str, Any]:
        """Define realistic facility structure"""
        return {
            'sites': {
                'SITE_001': {
                    'name': 'Manufacturing Floor - Main',
                    'location': 'Leeds, UK',
                    'production_lines': {
                        'LINE_001': {
                            'name': 'CNC Machining Line',
                            'machines': {
                                'CNC_MACHINE_001': {'type': 'CNC', 'sensors': ['clamp', 'vibration']},
                                'CNC_MACHINE_002': {'type': 'CNC', 'sensors': ['clamp', 'vibration']},
                                'CNC_MACHINE_003': {'type': 'CNC', 'sensors': ['clamp', 'vibration']},
                                'CNC_MACHINE_004': {'type': 'CNC', 'sensors': ['clamp', 'vibration']},
                            }
                        },
                        'LINE_002': {
                            'name': 'Precision Milling Line',
                            'machines': {
                                'MILL_MACHINE_001': {'type': 'MILL', 'sensors': ['clamp', 'vibration']},
                                'MILL_MACHINE_002': {'type': 'MILL', 'sensors': ['clamp', 'vibration']},
                                'MILL_MACHINE_003': {'type': 'MILL', 'sensors': ['clamp', 'vibration']},
                            }
                        }
                    },
                    'environmental_zones': {
                        'ZONE_FLOOR_001': {'name': 'Production Floor', 'sensors': ['environmental']}
                    }
                },
                'SITE_002': {
                    'name': 'Assembly Line - Sub-Assembly',
                    'location': 'Manchester, UK',
                    'production_lines': {
                        'LINE_003': {
                            'name': 'Manual Assembly Line',
                            'machines': {
                                'ASSEMBLY_STATION_001': {'type': 'ASSEMBLY', 'sensors': ['clamp']},
                                'ASSEMBLY_STATION_002': {'type': 'ASSEMBLY', 'sensors': ['clamp']},
                                'ASSEMBLY_STATION_003': {'type': 'ASSEMBLY', 'sensors': ['clamp']},
                                'ASSEMBLY_STATION_004': {'type': 'ASSEMBLY', 'sensors': ['clamp']},
                            }
                        }
                    },
                    'environmental_zones': {
                        'ZONE_ASSEMBLY_001': {'name': 'Assembly Area', 'sensors': ['environmental']}
                    }
                },
                'SITE_003': {
                    'name': 'Warehouse & Storage',
                    'location': 'Bristol, UK',
                    'production_lines': {},
                    'environmental_zones': {
                        'ZONE_WAREHOUSE_001': {'name': 'Climate Controlled Storage', 'sensors': ['environmental']}
                    }
                }
            }
        }

    def connect(self) -> bool:
        """Connect to AWS IoT Core"""
        try:
            self.mqtt_client.connect()
            logger.info(f"✅ Connected to AWS IoT Core as {self.client_id}")
            return True
        except Exception as e:
            logger.error(f"❌ Failed to connect: {e}")
            return False

    def disconnect(self):
        """Disconnect from AWS IoT Core"""
        self.mqtt_client.disconnect()
        logger.info("Disconnected from AWS IoT Core")

    def _is_production_active(self, timestamp: datetime) -> bool:
        """Check if production is active at this time"""
        weekday = timestamp.weekday()
        hour = timestamp.hour

        # Production: Mon-Fri 06:00-22:00, Sat 08:00-18:00
        if weekday < 5:
            return 6 <= hour < 22
        elif weekday == 5:
            return 8 <= hour < 18
        else:
            return False

    def _is_maintenance_window(self, timestamp: datetime) -> bool:
        """Check if it's a maintenance window"""
        # Maintenance: Sundays 00:00-06:00
        if timestamp.weekday() == 6 and 0 <= timestamp.hour < 6:
            return True
        return False

    def _generate_clamp_sensor_data(
        self,
        sensor_id: str,
        machine_id: str,
        site_id: str,
        timestamp: datetime,
        power_state: str = 'WORKING'
    ) -> Dict[str, Any]:
        """Generate realistic clamp current sensor data"""

        if power_state == 'OFF':
            phase_a = random.uniform(0.05, 0.15)
            phase_b = random.uniform(0.05, 0.15)
            phase_c = random.uniform(0.05, 0.15)
        elif power_state == 'IDLE':
            phase_a = random.uniform(2.0, 3.5)
            phase_b = random.uniform(2.0, 3.5)
            phase_c = random.uniform(2.0, 3.5)
        else:  # WORKING
            base_current = random.uniform(12.0, 16.0)
            phase_a = base_current + random.uniform(-1.0, 1.0)
            phase_b = base_current + random.uniform(-1.0, 1.0)
            phase_c = base_current + random.uniform(-1.0, 1.0)

        current_rms = (phase_a + phase_b + phase_c) / 3
        voltage_nominal = random.uniform(395, 405)
        power_factor = random.uniform(0.83, 0.97)

        return {
            'deviceId': sensor_id,
            'machineId': machine_id,
            'siteId': site_id,
            'timestamp': timestamp.isoformat() + 'Z',
            'sensorType': 'clamp_current',
            'measurements': {
                'current_phase_a': round(phase_a, 2),
                'current_phase_b': round(phase_b, 2),
                'current_phase_c': round(phase_c, 2),
                'current_rms': round(current_rms, 2),
                'voltage_phase_a': round(voltage_nominal + random.uniform(-2, 2), 1),
                'voltage_phase_b': round(voltage_nominal + random.uniform(-2, 2), 1),
                'voltage_phase_c': round(voltage_nominal + random.uniform(-2, 2), 1),
                'voltage_nominal': round(voltage_nominal, 1),
                'power_factor': round(power_factor, 3),
                'frequency': 50.0
            },
            'metadata': {
                'firmwareVersion': '1.2.3',
                'signalQuality': random.randint(85, 99),
                'batteryLevel': random.randint(70, 100)
            }
        }

    def _generate_vibration_sensor_data(
        self,
        sensor_id: str,
        machine_id: str,
        site_id: str,
        timestamp: datetime,
        power_state: str = 'WORKING'
    ) -> Dict[str, Any]:
        """Generate realistic vibration sensor data"""

        if power_state == 'OFF':
            vibration_x = random.uniform(0.01, 0.05)
            vibration_y = random.uniform(0.01, 0.05)
            vibration_z = random.uniform(0.01, 0.05)
            temperature = random.uniform(18, 22)
        elif power_state == 'IDLE':
            vibration_x = random.uniform(0.1, 0.3)
            vibration_y = random.uniform(0.1, 0.3)
            vibration_z = random.uniform(0.1, 0.3)
            temperature = random.uniform(22, 30)
        else:
            vibration_x = random.uniform(0.3, 0.8)
            vibration_y = random.uniform(0.3, 0.8)
            vibration_z = random.uniform(0.3, 0.8)
            temperature = random.uniform(35, 55)

        vibration_rms = (vibration_x + vibration_y + vibration_z) / 3
        dominant_frequency = random.uniform(80, 150) if power_state == 'WORKING' else random.uniform(20, 60)

        return {
            'deviceId': sensor_id,
            'machineId': machine_id,
            'siteId': site_id,
            'timestamp': timestamp.isoformat() + 'Z',
            'sensorType': 'vibration',
            'measurements': {
                'vibration_x': round(vibration_x, 2),
                'vibration_y': round(vibration_y, 2),
                'vibration_z': round(vibration_z, 2),
                'vibration_rms': round(vibration_rms, 2),
                'temperature': round(temperature, 1),
                'dominant_frequency': round(dominant_frequency, 1)
            },
            'metadata': {
                'firmwareVersion': '1.2.3',
                'samplingRate': 4000
            }
        }

    def _generate_environmental_sensor_data(
        self,
        sensor_id: str,
        zone_id: str,
        site_id: str,
        timestamp: datetime
    ) -> Dict[str, Any]:
        """Generate realistic environmental sensor data"""

        hour = timestamp.hour
        base_temp = 15 + 8 * (1 if 6 <= hour <= 18 else 0.7)
        temperature = base_temp + random.uniform(-2, 2)

        base_humidity = 65 - (temperature - 15) * 2
        humidity = max(30, min(80, base_humidity + random.uniform(-5, 5)))

        co2_ppm = random.uniform(450, 650) if 6 <= hour < 22 else random.uniform(350, 450)

        # Calculate dew point
        a = 17.27
        b = 237.7
        alpha = ((a * temperature) / (b + temperature)) + (humidity / 100.0)
        dew_point = round((b * alpha) / (a - alpha), 1)

        return {
            'deviceId': sensor_id,
            'zoneId': zone_id,
            'siteId': site_id,
            'timestamp': timestamp.isoformat() + 'Z',
            'sensorType': 'environmental',
            'measurements': {
                'temperature': round(temperature, 1),
                'humidity': round(humidity, 1),
                'dew_point': dew_point,
                'co2_ppm': round(co2_ppm, 0),
                'voc_index': random.randint(50, 150),
                'particulates_pm25': round(random.uniform(5, 25), 1),
                'particulates_pm10': round(random.uniform(10, 40), 1),
                'noise_db': round(random.uniform(55, 85), 1),
                'light_lux': round(random.uniform(300, 800), 0)
            },
            'metadata': {
                'firmwareVersion': '1.2.3',
                'calibrationDate': '2025-01-01'
            }
        }

    def publish_sensor_reading(self, topic: str, payload: Dict[str, Any]) -> bool:
        """Publish a sensor reading to IoT Core"""
        try:
            message_json = json.dumps(payload)
            self.mqtt_client.publish(topic, message_json, 1)
            return True
        except Exception as e:
            logger.error(f"❌ Failed to publish: {e}")
            return False

    def simulate_facility(
        self,
        tenant_id: str,
        duration_seconds: int = 3600,
        interval_seconds: int = 60
    ):
        """Simulate the entire manufacturing facility"""

        logger.info(f"🚀 Starting facility simulation for {tenant_id}")
        logger.info(f"   Duration: {duration_seconds}s ({duration_seconds/60:.1f} minutes)")
        logger.info(f"   Interval: {interval_seconds}s")

        start_time = time.time()
        current_timestamp = datetime.utcnow()
        message_count = 0

        while time.time() - start_time < duration_seconds:
            # Determine power state based on time
            is_active = self._is_production_active(current_timestamp)
            is_maintenance = self._is_maintenance_window(current_timestamp)

            if is_maintenance:
                power_state = 'OFF'
            elif not is_active:
                power_state = 'OFF'
            else:
                random_val = random.random()
                if random_val < 0.1:
                    power_state = 'OFF'
                elif random_val < 0.25:
                    power_state = 'IDLE'
                else:
                    power_state = 'WORKING'

            # Publish from each facility location
            for site_id, site_data in self.facilities['sites'].items():
                # Production lines and machines
                for line_id, line_data in site_data.get('production_lines', {}).items():
                    for machine_id, machine_data in line_data.get('machines', {}).items():
                        # Clamp sensors
                        if 'clamp' in machine_data['sensors']:
                            sensor_id = f'osm_pulse_{machine_id.lower()}'
                            topic = f"smdh/{tenant_id}/{machine_id}/current"

                            payload = self._generate_clamp_sensor_data(
                                sensor_id, machine_id, site_id, current_timestamp, power_state
                            )

                            if self.publish_sensor_reading(topic, payload):
                                message_count += 1
                            else:
                                logger.warning(f"Failed to publish from {machine_id}")

                        # Vibration sensors
                        if 'vibration' in machine_data['sensors']:
                            sensor_id = f'osm_sentinel_{machine_id.lower()}'
                            topic = f"smdh/{tenant_id}/{machine_id}/vibration"

                            payload = self._generate_vibration_sensor_data(
                                sensor_id, machine_id, site_id, current_timestamp, power_state
                            )

                            if self.publish_sensor_reading(topic, payload):
                                message_count += 1

                # Environmental zones
                for zone_id, zone_data in site_data.get('environmental_zones', {}).items():
                    if 'environmental' in zone_data['sensors']:
                        sensor_id = f'osm_haven_{zone_id.lower()}'
                        topic = f"smdh/{tenant_id}/{site_id}/environment"

                        payload = self._generate_environmental_sensor_data(
                            sensor_id, zone_id, site_id, current_timestamp
                        )

                        if self.publish_sensor_reading(topic, payload):
                            message_count += 1

            # Progress update
            elapsed = time.time() - start_time
            progress = (elapsed / duration_seconds) * 100
            logger.info(f"📊 Progress: {progress:.1f}% ({message_count} messages)")

            # Wait for next interval
            time.sleep(interval_seconds)
            current_timestamp += timedelta(seconds=interval_seconds)

        logger.info(f"✅ Simulation complete! Sent {message_count} messages")
        return message_count


def main():
    parser = argparse.ArgumentParser(description='Realistic Manufacturing Facility Simulator')
    parser.add_argument('--endpoint', required=True, help='AWS IoT endpoint')
    parser.add_argument('--cert', required=True, help='Path to device certificate')
    parser.add_argument('--key', required=True, help='Path to private key')
    parser.add_argument('--ca', required=True, help='Path to CA certificate')
    parser.add_argument('--client-id', required=True, help='MQTT client ID')
    parser.add_argument('--tenant-id', required=True, help='Tenant ID')
    parser.add_argument('--duration', type=int, default=3600, help='Simulation duration in seconds')
    parser.add_argument('--interval', type=int, default=60, help='Interval between readings in seconds')

    args = parser.parse_args()

    simulator = RealisticFacilitySimulator(
        args.endpoint,
        args.client_id,
        args.cert,
        args.key,
        args.ca
    )

    # Connect and simulate
    if not simulator.connect():
        return 1

    try:
        simulator.simulate_facility(
            args.tenant_id,
            args.duration,
            args.interval
        )
    except KeyboardInterrupt:
        logger.info("\n⚠️  Simulation interrupted by user")
    finally:
        simulator.disconnect()

    return 0


if __name__ == "__main__":
    exit(main())
