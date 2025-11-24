#!/usr/bin/env python3
"""
SMDH IoT Device Simulator
Tests data transmission from devices to AWS IoT Core infrastructure
"""

import json
import time
import random
import argparse
import ssl
from datetime import datetime
from AWSIoTPythonSDK.MQTTLib import AWSIoTMQTTClient
import logging

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

class IoTDeviceSimulator:
    def __init__(self, endpoint, client_id, cert_path, key_path, ca_path):
        """Initialize the IoT device simulator"""
        self.client_id = client_id
        self.mqtt_client = AWSIoTMQTTClient(client_id)
        self.mqtt_client.configureEndpoint(endpoint, 8883)
        self.mqtt_client.configureCredentials(ca_path, key_path, cert_path)

        # Configure connection parameters
        self.mqtt_client.configureAutoReconnectBackoffTime(1, 32, 20)
        self.mqtt_client.configureOfflinePublishQueueing(-1)  # Infinite offline queue
        self.mqtt_client.configureDrainingFrequency(2)  # Hz
        self.mqtt_client.configureConnectDisconnectTimeout(10)
        self.mqtt_client.configureMQTTOperationTimeout(5)

    def connect(self):
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

    def generate_sensor_data(self, device_type="water_level"):
        """Generate realistic sensor data based on device type"""
        timestamp = datetime.utcnow().isoformat() + 'Z'

        if device_type == "water_level":
            return {
                "timestamp": timestamp,
                "deviceType": "water_level_sensor",
                "measurements": {
                    "waterLevel": round(random.uniform(0.5, 3.5), 2),  # meters
                    "flowRate": round(random.uniform(0, 100), 1),      # L/min
                    "pressure": round(random.uniform(1.0, 2.5), 2),    # bar
                    "temperature": round(random.uniform(15, 25), 1)    # Celsius
                },
                "quality": {
                    "ph": round(random.uniform(6.5, 8.5), 1),
                    "turbidity": round(random.uniform(0, 5), 2),       # NTU
                    "conductivity": round(random.uniform(200, 800), 0) # μS/cm
                },
                "status": {
                    "batteryLevel": round(random.uniform(70, 100), 0),
                    "signalStrength": round(random.uniform(-80, -40), 0),  # dBm
                    "uptime": random.randint(1000, 100000)  # seconds
                }
            }
        elif device_type == "pump_station":
            return {
                "timestamp": timestamp,
                "deviceType": "pump_station",
                "measurements": {
                    "pumpStatus": random.choice(["running", "idle", "maintenance"]),
                    "flowRate": round(random.uniform(0, 500), 1),      # L/min
                    "powerConsumption": round(random.uniform(5, 50), 1), # kW
                    "motorRPM": random.randint(1000, 3000),
                    "vibration": round(random.uniform(0, 10), 2)       # mm/s
                },
                "alarms": {
                    "highPressure": random.choice([True, False]),
                    "lowFlow": random.choice([True, False]),
                    "overTemperature": random.choice([True, False])
                }
            }
        elif device_type == "gateway_status":
            return {
                "timestamp": timestamp,
                "deviceType": "gateway",
                "systemInfo": {
                    "uptime": random.randint(1000, 1000000),
                    "cpuUsage": round(random.uniform(10, 60), 1),
                    "memoryUsage": round(random.uniform(20, 70), 1),
                    "diskUsage": round(random.uniform(10, 50), 1),
                    "temperature": round(random.uniform(30, 50), 1)
                },
                "network": {
                    "connectedDevices": random.randint(5, 20),
                    "packetsReceived": random.randint(1000, 10000),
                    "packetsTransmitted": random.randint(1000, 10000),
                    "errorRate": round(random.uniform(0, 0.1), 3)
                }
            }
        elif device_type == "air_quality":
            aqi = random.randint(0, 500)
            if aqi <= 50:
                aqi_category = "good"
            elif aqi <= 100:
                aqi_category = "moderate"
            elif aqi <= 150:
                aqi_category = "unhealthy_for_sensitive_groups"
            elif aqi <= 200:
                aqi_category = "unhealthy"
            elif aqi <= 300:
                aqi_category = "very_unhealthy"
            else:
                aqi_category = "hazardous"

            return {
                "timestamp": timestamp,
                "device_type": "air_quality_sensor",
                "device_model": "OpenSmartMonitor_AQ",
                "measurements": {
                    "pm10": round(random.uniform(0, 500), 1),
                    "pm25": round(random.uniform(0, 500), 1),
                    "pm100": round(random.uniform(0, 100), 1),
                    "aqi": aqi,
                    "aqi_category": aqi_category
                },
                "status": {
                    "batteryLevel": round(random.uniform(60, 100), 0),
                    "signalStrength": round(random.uniform(-80, -40), 0),
                    "uptime": random.randint(1000, 100000)
                }
            }
        elif device_type == "power_sensor":
            return {
                "timestamp": timestamp,
                "device_type": "power_energy_sensor",
                "device_model": "OpenSmartMonitor_Power",
                "measurements": {
                    "voltage_v": round(random.uniform(220, 240), 1),
                    "current_a": round(random.uniform(0, 63), 2),
                    "power_w": round(random.uniform(0, 15000), 1),
                    "power_factor": round(random.uniform(0.85, 1.0), 2),
                    "energy_kwh": round(random.uniform(0, 1000), 2),
                    "frequency_hz": round(random.uniform(49.5, 50.5), 2)
                },
                "status": {
                    "phase_a": "active",
                    "phase_b": random.choice(["active", "inactive"]),
                    "phase_c": random.choice(["active", "inactive"]),
                    "uptime": random.randint(1000, 100000)
                }
            }
        elif device_type == "water_sensor":
            return {
                "timestamp": timestamp,
                "device_type": "water_sensor",
                "device_model": "OpenSmartMonitor_Water",
                "measurements": {
                    "flow_rate_lpm": round(random.uniform(0, 100), 2),
                    "pressure_bar": round(random.uniform(0, 5), 2),
                    "ph": round(random.uniform(6.0, 8.5), 1),
                    "turbidity_ntu": round(random.uniform(0, 10), 2),
                    "conductivity_us_cm": round(random.uniform(100, 2000), 0),
                    "temperature_c": round(random.uniform(5, 35), 1)
                },
                "status": {
                    "batteryLevel": round(random.uniform(60, 100), 0),
                    "signalStrength": round(random.uniform(-80, -40), 0),
                    "uptime": random.randint(1000, 100000)
                }
            }
        elif device_type == "gas_sensor":
            return {
                "timestamp": timestamp,
                "device_type": "gas_sensor",
                "device_model": "OpenSmartMonitor_Gas",
                "measurements": {
                    "co2_ppm": round(random.uniform(300, 2000), 0),
                    "tvoc_ppb": round(random.uniform(0, 500), 1),
                    "o2_percent": round(random.uniform(15, 21), 1),
                    "no2_ppb": round(random.uniform(0, 100), 1),
                    "iaq": random.randint(0, 500)
                },
                "status": {
                    "batteryLevel": round(random.uniform(60, 100), 0),
                    "signalStrength": round(random.uniform(-80, -40), 0),
                    "uptime": random.randint(1000, 100000)
                }
            }
        elif device_type == "environmental":
            temp = round(random.uniform(-40, 70), 1)
            humidity = round(random.uniform(0, 100), 1)
            # Calculate dew point using Magnus approximation
            a = 17.27
            b = 237.7
            alpha = ((a * temp) / (b + temp)) + (humidity / 100.0)
            dew_point = round((b * alpha) / (a - alpha), 1)

            return {
                "timestamp": timestamp,
                "device_type": "environmental_sensor",
                "device_model": "OpenSmartMonitor_Environmental",
                "measurements": {
                    "temperature_c": temp,
                    "humidity_percent": humidity,
                    "dew_point_c": dew_point,
                    "pressure_hpa": round(random.uniform(900, 1100), 1)
                },
                "status": {
                    "batteryLevel": round(random.uniform(60, 100), 0),
                    "signalStrength": round(random.uniform(-80, -40), 0),
                    "uptime": random.randint(1000, 100000)
                }
            }
        elif device_type == "acoustic_sensor":
            return {
                "timestamp": timestamp,
                "device_type": "acoustic_sensor",
                "device_model": "OpenSmartMonitor_Acoustic",
                "measurements": {
                    "sound_level_db": round(random.uniform(30, 130), 1),
                    "sound_level_dba": round(random.uniform(30, 130), 1),
                    "frequency_hz": round(random.uniform(20, 20000), 0),
                    "peak_frequency_hz": round(random.uniform(100, 5000), 0)
                },
                "status": {
                    "batteryLevel": round(random.uniform(60, 100), 0),
                    "signalStrength": round(random.uniform(-80, -40), 0),
                    "uptime": random.randint(1000, 100000)
                }
            }
        elif device_type == "light_sensor":
            return {
                "timestamp": timestamp,
                "device_type": "light_sensor",
                "device_model": "OpenSmartMonitor_Light",
                "measurements": {
                    "illuminance_lux": round(random.uniform(0, 100000), 1),
                    "color_temperature_k": round(random.uniform(2700, 6500), 0),
                    "cri_index": round(random.uniform(60, 100), 0),
                    "uv_index": round(random.uniform(0, 11), 1)
                },
                "status": {
                    "batteryLevel": round(random.uniform(60, 100), 0),
                    "signalStrength": round(random.uniform(-80, -40), 0),
                    "uptime": random.randint(1000, 100000)
                }
            }
        elif device_type == "milesight_gateway":
            return {
                "timestamp": timestamp,
                "gateway_id": f"gw_milesight_ug65_{random.randint(1, 100):03d}",
                "model": "Milesight-UG65",
                "manufacturer": "Milesight",
                "firmware_version": "1.2.5",
                "status": "online",
                "uptime_seconds": random.randint(86400, 86400 * 30),  # 1-30 days
                "system": {
                    "cpu_usage_percent": round(random.uniform(10, 60), 1),
                    "memory_used_mb": random.randint(128, 400),
                    "memory_total_mb": 512,
                    "disk_used_percent": round(random.uniform(10, 80), 1),
                    "temperature_celsius": round(random.uniform(25, 50), 1)
                },
                "lora_radio": {
                    "channels_active": 8,
                    "packets_received": random.randint(10000, 500000),
                    "packets_transmitted": random.randint(5000, 300000),
                    "error_rate_percent": round(random.uniform(0, 1), 3),
                    "uplink_utilization_percent": round(random.uniform(1, 30), 1),
                    "downlink_utilization_percent": round(random.uniform(1, 20), 1)
                },
                "connectivity": {
                    "ethernet_connected": True,
                    "ethernet_speed_mbps": 1000,
                    "wifi_connected": False,
                    "cellular_connected": False,
                    "wan_ip": f"192.168.1.{random.randint(1, 254)}",
                    "signal_strength_dbm": round(random.uniform(-80, -40), 0)
                },
                "devices": {
                    "connected_devices": random.randint(10, 100),
                    "devices_by_class": {
                        "class_a": random.randint(20, 70),
                        "class_b": random.randint(5, 20),
                        "class_c": random.randint(2, 10)
                    },
                    "devices_active_last_hour": random.randint(5, 80),
                    "devices_active_last_day": random.randint(50, 100)
                }
            }
        else:
            # Generic sensor data
            return {
                "timestamp": timestamp,
                "deviceType": "generic_sensor",
                "value": round(random.uniform(0, 100), 2),
                "unit": "units",
                "status": "active"
            }

    def publish_message(self, topic, payload, qos=1):
        """Publish a message to the specified topic"""
        try:
            message_json = json.dumps(payload)
            self.mqtt_client.publish(topic, message_json, qos)
            logger.info(f"📤 Published to {topic}: {message_json[:100]}...")
            return True
        except Exception as e:
            logger.error(f"❌ Failed to publish: {e}")
            return False

    def subscribe_to_topic(self, topic, callback, qos=1):
        """Subscribe to a topic for receiving commands"""
        try:
            self.mqtt_client.subscribe(topic, qos, callback)
            logger.info(f"📥 Subscribed to {topic}")
            return True
        except Exception as e:
            logger.error(f"❌ Failed to subscribe: {e}")
            return False

    def simulate_continuous_data(self, tenant_id, site_id, device_type="water_level",
                                interval=10, duration=60):
        """Simulate continuous data transmission"""
        topic = f"smdh/{tenant_id}/{site_id}/sensor-data"
        start_time = time.time()
        message_count = 0

        logger.info(f"🚀 Starting continuous simulation for {duration} seconds...")
        logger.info(f"📍 Publishing to topic: {topic}")
        logger.info(f"⏱️  Interval: {interval} seconds")

        while time.time() - start_time < duration:
            data = self.generate_sensor_data(device_type)
            data["messageId"] = f"msg_{message_count:06d}"
            data["tenantId"] = tenant_id
            data["siteId"] = site_id

            if self.publish_message(topic, data):
                message_count += 1

            time.sleep(interval)

        logger.info(f"✅ Simulation complete! Sent {message_count} messages")
        return message_count

def command_callback(client, userdata, message):
    """Callback for handling received commands"""
    logger.info(f"📨 Received command on {message.topic}: {message.payload.decode('utf-8')}")

def main():
    parser = argparse.ArgumentParser(description='SMDH IoT Device Simulator')
    parser.add_argument('--endpoint', required=True, help='AWS IoT endpoint')
    parser.add_argument('--cert', required=True, help='Path to device certificate')
    parser.add_argument('--key', required=True, help='Path to private key')
    parser.add_argument('--ca', required=True, help='Path to CA certificate')
    parser.add_argument('--client-id', required=True, help='MQTT client ID')
    parser.add_argument('--tenant-id', required=True, help='Tenant ID')
    parser.add_argument('--site-id', default='site_001', help='Site ID')
    parser.add_argument('--device-type', default='water_level',
                       choices=['water_level', 'pump_station', 'gateway_status', 'air_quality',
                                'power_sensor', 'water_sensor', 'gas_sensor', 'environmental',
                                'acoustic_sensor', 'light_sensor', 'milesight_gateway', 'generic'],
                       help='Type of device to simulate')
    parser.add_argument('--mode', default='continuous',
                       choices=['single', 'continuous', 'burst'],
                       help='Simulation mode')
    parser.add_argument('--interval', type=int, default=10,
                       help='Interval between messages (seconds)')
    parser.add_argument('--duration', type=int, default=60,
                       help='Duration of simulation (seconds)')
    parser.add_argument('--burst-count', type=int, default=10,
                       help='Number of messages in burst mode')

    args = parser.parse_args()

    # Create simulator
    simulator = IoTDeviceSimulator(
        args.endpoint,
        args.client_id,
        args.cert,
        args.key,
        args.ca
    )

    # Connect to IoT Core
    if not simulator.connect():
        return 1

    # Subscribe to command topic
    command_topic = f"smdh/{args.tenant_id}/commands/+"
    simulator.subscribe_to_topic(command_topic, command_callback)

    try:
        if args.mode == 'single':
            # Send a single message
            topic = f"smdh/{args.tenant_id}/{args.site_id}/sensor-data"
            data = simulator.generate_sensor_data(args.device_type)
            data["tenantId"] = args.tenant_id
            data["siteId"] = args.site_id
            simulator.publish_message(topic, data)

        elif args.mode == 'continuous':
            # Continuous simulation
            simulator.simulate_continuous_data(
                args.tenant_id,
                args.site_id,
                args.device_type,
                args.interval,
                args.duration
            )

        elif args.mode == 'burst':
            # Burst mode - send multiple messages quickly
            topic = f"smdh/{args.tenant_id}/{args.site_id}/sensor-data"
            logger.info(f"🚀 Sending burst of {args.burst_count} messages...")
            for i in range(args.burst_count):
                data = simulator.generate_sensor_data(args.device_type)
                data["messageId"] = f"burst_{i:04d}"
                data["tenantId"] = args.tenant_id
                data["siteId"] = args.site_id
                simulator.publish_message(topic, data)
                time.sleep(0.1)  # Small delay to avoid overwhelming
            logger.info(f"✅ Burst complete!")

    except KeyboardInterrupt:
        logger.info("\n⚠️  Simulation interrupted by user")
    finally:
        simulator.disconnect()

    return 0

if __name__ == "__main__":
    exit(main())