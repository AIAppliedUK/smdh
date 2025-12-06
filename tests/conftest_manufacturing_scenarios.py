"""
Extended conftest with realistic manufacturing scenarios
Provides fixtures for simulating actual factory environments with multiple sites, machines, and sensor types
"""

import pytest
from datetime import datetime, timedelta
from typing import Dict, List, Any, Generator
import random
import json
import logging

logger = logging.getLogger(__name__)


# ============================================================================
# MANUFACTURING FACILITY DEFINITIONS
# ============================================================================

class ManufacturingFacility:
    """Represents a realistic manufacturing facility with multiple sites and equipment"""

    def __init__(self, tenant_id: str, tenant_name: str):
        self.tenant_id = tenant_id
        self.tenant_name = tenant_name
        self.sites: Dict[str, 'ManufactoringSite'] = {}

    def add_site(self, site_id: str, site: 'ManufactoringSite'):
        """Add a manufacturing site to the facility"""
        self.sites[site_id] = site

    def to_dict(self) -> Dict[str, Any]:
        return {
            'tenant_id': self.tenant_id,
            'tenant_name': self.tenant_name,
            'sites': {sid: site.to_dict() for sid, site in self.sites.items()}
        }


class ManufactoringSite:
    """Represents a single manufacturing site with production lines and equipment"""

    def __init__(self, site_id: str, site_name: str, location: str = "UK"):
        self.site_id = site_id
        self.site_name = site_name
        self.location = location
        self.production_lines: Dict[str, 'ProductionLine'] = {}
        self.zones: Dict[str, 'EnvironmentalZone'] = {}

    def add_production_line(self, line_id: str, line: 'ProductionLine'):
        """Add a production line to the site"""
        self.production_lines[line_id] = line

    def add_environmental_zone(self, zone_id: str, zone: 'EnvironmentalZone'):
        """Add an environmental monitoring zone"""
        self.zones[zone_id] = zone

    def to_dict(self) -> Dict[str, Any]:
        return {
            'site_id': self.site_id,
            'site_name': self.site_name,
            'location': self.location,
            'production_lines': {lid: line.to_dict() for lid, line in self.production_lines.items()},
            'environmental_zones': {zid: zone.to_dict() for zid, zone in self.zones.items()}
        }


class ProductionLine:
    """Represents a production line with multiple machines"""

    def __init__(self, line_id: str, line_name: str, shift_schedule: List[str] = None):
        self.line_id = line_id
        self.line_name = line_name
        self.shift_schedule = shift_schedule or ['morning', 'afternoon', 'night']  # Shift patterns
        self.machines: Dict[str, 'Machine'] = {}

    def add_machine(self, machine_id: str, machine: 'Machine'):
        """Add a machine to the production line"""
        self.machines[machine_id] = machine

    def to_dict(self) -> Dict[str, Any]:
        return {
            'line_id': self.line_id,
            'line_name': self.line_name,
            'shift_schedule': self.shift_schedule,
            'machines': {mid: m.to_dict() for mid, m in self.machines.items()}
        }


class Machine:
    """Represents industrial equipment with sensors"""

    def __init__(self, machine_id: str, machine_name: str, machine_type: str = "CNC"):
        self.machine_id = machine_id
        self.machine_name = machine_name
        self.machine_type = machine_type
        self.sensors: Dict[str, 'Sensor'] = {}
        self.power_thresholds = {
            'off_max': 0.5,      # Max power when OFF
            'idle_min': 0.5,
            'idle_max': 5.0,     # Idle range
            'working_min': 5.0   # Min power when WORKING
        }

    def add_sensor(self, sensor_id: str, sensor: 'Sensor'):
        """Add a sensor to the machine"""
        self.sensors[sensor_id] = sensor

    def to_dict(self) -> Dict[str, Any]:
        return {
            'machine_id': self.machine_id,
            'machine_name': self.machine_name,
            'machine_type': self.machine_type,
            'sensors': {sid: s.to_dict() for sid, s in self.sensors.items()},
            'power_thresholds': self.power_thresholds
        }


class Sensor:
    """Represents a physical sensor on equipment"""

    def __init__(self, sensor_id: str, sensor_type: str, model: str = "OpenSmartMonitor"):
        self.sensor_id = sensor_id
        self.sensor_type = sensor_type  # 'clamp_current', 'vibration', 'environmental', etc.
        self.model = model
        self.last_reading: Dict[str, Any] = None
        self.health_status = 'online'  # online, offline, degraded

    def to_dict(self) -> Dict[str, Any]:
        return {
            'sensor_id': self.sensor_id,
            'sensor_type': self.sensor_type,
            'model': self.model,
            'health_status': self.health_status
        }


class EnvironmentalZone:
    """Represents a zone for environmental monitoring (e.g., production floor)"""

    def __init__(self, zone_id: str, zone_name: str):
        self.zone_id = zone_id
        self.zone_name = zone_name
        self.sensors: Dict[str, 'Sensor'] = {}

    def add_sensor(self, sensor_id: str, sensor: 'Sensor'):
        """Add a sensor to the zone"""
        self.sensors[sensor_id] = sensor

    def to_dict(self) -> Dict[str, Any]:
        return {
            'zone_id': self.zone_id,
            'zone_name': self.zone_name,
            'sensors': {sid: s.to_dict() for sid, s in self.sensors.items()}
        }


# ============================================================================
# REALISTIC SCENARIO GENERATORS
# ============================================================================

class RealisticManufacturingSimulator:
    """Generates realistic manufacturing data including sensor readings, machine states, and events"""

    def __init__(self, facility: ManufacturingFacility, base_date: datetime = None):
        self.facility = facility
        self.base_date = base_date or datetime.utcnow().replace(hour=0, minute=0, second=0, microsecond=0)

    def get_shift_for_hour(self, hour: int) -> str:
        """Return the shift name for a given hour of day"""
        if 6 <= hour < 14:
            return 'morning'
        elif 14 <= hour < 22:
            return 'afternoon'
        else:
            return 'night'

    def is_maintenance_window(self, timestamp: datetime) -> bool:
        """Check if timestamp falls in a maintenance window"""
        # Maintenance: Sundays 00:00-06:00
        if timestamp.weekday() == 6 and 0 <= timestamp.hour < 6:
            return True
        return False

    def is_production_active(self, timestamp: datetime) -> bool:
        """Check if production is active at this time"""
        # Production active: Monday-Friday 06:00-22:00, Saturday 08:00-18:00
        weekday = timestamp.weekday()
        hour = timestamp.hour

        if weekday < 5:  # Monday-Friday
            return 6 <= hour < 22
        elif weekday == 5:  # Saturday
            return 8 <= hour < 18
        else:  # Sunday
            return False

    def generate_clamp_sensor_reading(
        self,
        sensor_id: str,
        machine_id: str,
        site_id: str,
        timestamp: datetime,
        power_state: str = 'WORKING'
    ) -> Dict[str, Any]:
        """Generate a realistic clamp current sensor reading"""

        # Vary current based on power state
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
            # Add slight variation between phases
            phase_a = base_current + random.uniform(-1.0, 1.0)
            phase_b = base_current + random.uniform(-1.0, 1.0)
            phase_c = base_current + random.uniform(-1.0, 1.0)

        current_rms = (phase_a + phase_b + phase_c) / 3

        # 3-phase voltage (400V industrial standard)
        voltage_a = random.uniform(395, 405)
        voltage_b = random.uniform(395, 405)
        voltage_c = random.uniform(395, 405)
        voltage_nominal = (voltage_a + voltage_b + voltage_c) / 3

        # Power factor typically 0.85-0.95 for industrial equipment
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
                'voltage_phase_a': round(voltage_a, 1),
                'voltage_phase_b': round(voltage_b, 1),
                'voltage_phase_c': round(voltage_c, 1),
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

    def generate_vibration_sensor_reading(
        self,
        sensor_id: str,
        machine_id: str,
        site_id: str,
        timestamp: datetime,
        power_state: str = 'WORKING'
    ) -> Dict[str, Any]:
        """Generate a realistic vibration and temperature sensor reading"""

        if power_state == 'OFF':
            # No vibration when off
            vibration_x = random.uniform(0.01, 0.05)
            vibration_y = random.uniform(0.01, 0.05)
            vibration_z = random.uniform(0.01, 0.05)
            temperature = random.uniform(18, 22)  # Ambient temperature
        elif power_state == 'IDLE':
            # Low vibration at idle
            vibration_x = random.uniform(0.1, 0.3)
            vibration_y = random.uniform(0.1, 0.3)
            vibration_z = random.uniform(0.1, 0.3)
            temperature = random.uniform(22, 30)
        else:  # WORKING
            # Higher, more variable vibration when running
            vibration_x = random.uniform(0.3, 0.8)
            vibration_y = random.uniform(0.3, 0.8)
            vibration_z = random.uniform(0.3, 0.8)
            temperature = random.uniform(35, 55)  # Can get hot

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

    def generate_environmental_sensor_reading(
        self,
        sensor_id: str,
        zone_id: str,
        site_id: str,
        timestamp: datetime
    ) -> Dict[str, Any]:
        """Generate a realistic environmental sensor reading (temperature, humidity, air quality)"""

        # Vary temperature by time of day
        hour = timestamp.hour
        base_temp = 15 + 8 * (1 + (0 if 6 <= hour <= 18 else -0.3))
        temperature = base_temp + random.uniform(-2, 2)

        # Humidity inversely related to temperature
        base_humidity = 65 - (temperature - 15) * 2
        humidity = max(30, min(80, base_humidity + random.uniform(-5, 5)))

        # CO2 varies with activity (higher during production hours)
        if 6 <= hour < 22:
            co2_ppm = random.uniform(450, 650)
        else:
            co2_ppm = random.uniform(350, 450)

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

    def generate_sensor_readings_for_period(
        self,
        start_time: datetime,
        end_time: datetime,
        interval_minutes: int = 1
    ) -> List[Dict[str, Any]]:
        """Generate sensor readings for a time period, simulating real manufacturing"""

        readings = []
        current_time = start_time

        while current_time <= end_time:
            # Check if production is active
            is_active = self.is_production_active(current_time)
            is_maintenance = self.is_maintenance_window(current_time)

            if is_maintenance:
                power_state = 'OFF'
            elif not is_active:
                power_state = 'OFF'
            else:
                # Simulate production patterns
                # More complex: machines don't run continuously
                random_val = random.random()
                if random_val < 0.1:
                    power_state = 'OFF'  # 10% idle/shutdown
                elif random_val < 0.25:
                    power_state = 'IDLE'  # 15% idle
                else:
                    power_state = 'WORKING'  # 75% working

            # Generate readings from each site
            for site_id, site in self.facility.sites.items():
                # Production lines and machines
                for line_id, line in site.production_lines.items():
                    for machine_id, machine in line.machines.items():
                        for sensor_id, sensor in machine.sensors.items():
                            if sensor.sensor_type == 'clamp_current':
                                reading = self.generate_clamp_sensor_reading(
                                    sensor_id, machine_id, site_id, current_time, power_state
                                )
                            elif sensor.sensor_type == 'vibration':
                                reading = self.generate_vibration_sensor_reading(
                                    sensor_id, machine_id, site_id, current_time, power_state
                                )
                            else:
                                continue

                            readings.append(reading)

                # Environmental zones
                for zone_id, zone in site.zones.items():
                    for sensor_id, sensor in zone.sensors.items():
                        if sensor.sensor_type == 'environmental':
                            reading = self.generate_environmental_sensor_reading(
                                sensor_id, zone_id, site_id, current_time
                            )
                            readings.append(reading)

            current_time += timedelta(minutes=interval_minutes)

        return readings


# ============================================================================
# PYTEST FIXTURES - Realistic Facility Setup
# ============================================================================

@pytest.fixture
def realistic_facility() -> ManufacturingFacility:
    """
    Create a realistic multi-site manufacturing facility with equipment and sensors

    Facility: ABC Manufacturing Ltd
    - Site 1: Manufacturing Floor (3 production lines, 12 machines, environmental monitoring)
    - Site 2: Assembly Line (2 production lines, 8 machines)
    - Site 3: Warehouse (Environmental monitoring only)
    """

    facility = ManufacturingFacility('abc_mfg', 'ABC Manufacturing Ltd')

    # ===== SITE 1: Manufacturing Floor =====
    site1 = ManufactoringSite('SITE_001', 'Manufacturing Floor - Main', 'Leeds, UK')

    # Production Line 1: CNC Machines
    line1 = ProductionLine('LINE_001', 'CNC Machining Line', ['morning', 'afternoon', 'night'])

    for machine_num in range(1, 5):  # 4 CNC machines
        machine_id = f'CNC_MACHINE_{machine_num:03d}'
        machine = Machine(machine_id, f'CNC Lathe {machine_num}', 'CNC')

        # Each CNC has a current sensor and vibration sensor
        clamp_sensor = Sensor(f'osm_pulse_{machine_num:03d}', 'clamp_current', 'OpenSmartMonitor_PULSE')
        vibration_sensor = Sensor(f'osm_sentinel_{machine_num:03d}', 'vibration', 'OpenSmartMonitor_SENTINEL')

        machine.add_sensor(clamp_sensor.sensor_id, clamp_sensor)
        machine.add_sensor(vibration_sensor.sensor_id, vibration_sensor)

        line1.add_machine(machine_id, machine)

    site1.add_production_line('LINE_001', line1)

    # Production Line 2: Milling Machines
    line2 = ProductionLine('LINE_002', 'Precision Milling Line', ['morning', 'afternoon'])

    for machine_num in range(1, 4):  # 3 milling machines
        machine_id = f'MILL_MACHINE_{machine_num:03d}'
        machine = Machine(machine_id, f'Precision Mill {machine_num}', 'MILL')

        clamp_sensor = Sensor(f'osm_pulse_mill_{machine_num:03d}', 'clamp_current')
        vibration_sensor = Sensor(f'osm_sentinel_mill_{machine_num:03d}', 'vibration')

        machine.add_sensor(clamp_sensor.sensor_id, clamp_sensor)
        machine.add_sensor(vibration_sensor.sensor_id, vibration_sensor)

        line2.add_machine(machine_id, machine)

    site1.add_production_line('LINE_002', line2)

    # Environmental Zone: Production Floor
    env_zone1 = EnvironmentalZone('ZONE_FLOOR_001', 'Manufacturing Floor A')
    env_sensor1 = Sensor('osm_haven_floor_001', 'environmental', 'OpenSmartMonitor_HAVEN')
    env_zone1.add_sensor(env_sensor1.sensor_id, env_sensor1)
    site1.add_environmental_zone('ZONE_FLOOR_001', env_zone1)

    facility.add_site('SITE_001', site1)

    # ===== SITE 2: Assembly Line =====
    site2 = ManufactoringSite('SITE_002', 'Assembly Line - Sub-Assembly', 'Manchester, UK')

    line3 = ProductionLine('LINE_003', 'Manual Assembly Line', ['morning', 'afternoon'])

    for machine_num in range(1, 5):  # 4 assembly stations (with power tools)
        machine_id = f'ASSEMBLY_STATION_{machine_num:03d}'
        machine = Machine(machine_id, f'Assembly Station {machine_num}', 'ASSEMBLY')

        clamp_sensor = Sensor(f'osm_pulse_assy_{machine_num:03d}', 'clamp_current')
        machine.add_sensor(clamp_sensor.sensor_id, clamp_sensor)
        machine.power_thresholds['working_min'] = 3.0  # Power tools use less power

        line3.add_machine(machine_id, machine)

    site2.add_production_line('LINE_003', line3)

    # Environmental Zone: Assembly Area
    env_zone2 = EnvironmentalZone('ZONE_ASSEMBLY_001', 'Assembly Area A')
    env_sensor2 = Sensor('osm_haven_assy_001', 'environmental')
    env_zone2.add_sensor(env_sensor2.sensor_id, env_sensor2)
    site2.add_environmental_zone('ZONE_ASSEMBLY_001', env_zone2)

    facility.add_site('SITE_002', site2)

    # ===== SITE 3: Warehouse =====
    site3 = ManufactoringSite('SITE_003', 'Warehouse & Storage', 'Bristol, UK')

    # Environmental Zone: Warehouse
    env_zone3 = EnvironmentalZone('ZONE_WAREHOUSE_001', 'Climate Controlled Storage')
    env_sensor3 = Sensor('osm_haven_warehouse_001', 'environmental')
    env_zone3.add_sensor(env_sensor3.sensor_id, env_sensor3)
    site3.add_environmental_zone('ZONE_WAREHOUSE_001', env_zone3)

    facility.add_site('SITE_003', site3)

    return facility


@pytest.fixture
def manufacturing_simulator(realistic_facility: ManufacturingFacility) -> RealisticManufacturingSimulator:
    """Provide a simulator for generating realistic manufacturing data"""
    return RealisticManufacturingSimulator(realistic_facility)


@pytest.fixture
def multi_day_sensor_data(manufacturing_simulator: RealisticManufacturingSimulator) -> List[Dict[str, Any]]:
    """
    Generate 3 days of realistic sensor data
    This simulates actual manufacturing operations with shift patterns, maintenance, etc.
    """
    # Generate data for 3 days ending yesterday
    end_date = datetime.utcnow().replace(hour=23, minute=59, second=0, microsecond=0)
    start_date = end_date - timedelta(days=3)

    readings = manufacturing_simulator.generate_sensor_readings_for_period(
        start_date, end_date, interval_minutes=1
    )

    return readings


@pytest.fixture
def realistic_site_config() -> Dict[str, Any]:
    """Provide a realistic site configuration"""
    return {
        'tenant_id': 'abc_mfg',
        'tenant_name': 'ABC Manufacturing Ltd',
        'sites': [
            {
                'site_id': 'SITE_001',
                'site_name': 'Manufacturing Floor',
                'location': 'Leeds, UK',
                'production_lines': [
                    {
                        'line_id': 'LINE_001',
                        'line_name': 'CNC Machining',
                        'machines': ['CNC_MACHINE_001', 'CNC_MACHINE_002', 'CNC_MACHINE_003']
                    },
                    {
                        'line_id': 'LINE_002',
                        'line_name': 'Milling',
                        'machines': ['MILL_MACHINE_001', 'MILL_MACHINE_002']
                    }
                ],
                'zones': ['ZONE_FLOOR_001']
            },
            {
                'site_id': 'SITE_002',
                'site_name': 'Assembly Line',
                'location': 'Manchester, UK',
                'production_lines': [
                    {
                        'line_id': 'LINE_003',
                        'line_name': 'Assembly',
                        'machines': ['ASSEMBLY_STATION_001', 'ASSEMBLY_STATION_002', 'ASSEMBLY_STATION_003']
                    }
                ],
                'zones': ['ZONE_ASSEMBLY_001']
            }
        ],
        'shifts': ['morning', 'afternoon', 'night'],
        'working_hours': {
            'monday_friday': {'start': 6, 'end': 22},
            'saturday': {'start': 8, 'end': 18},
            'sunday': 'closed'
        },
        'maintenance_windows': [
            {'day': 'sunday', 'start_hour': 0, 'end_hour': 6}
        ]
    }
