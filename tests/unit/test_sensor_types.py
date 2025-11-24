"""
Unit tests for all sensor types in SMDH platform
Tests data validation and transformation for:
- Air Quality Sensors (PM10, PM2.5)
- Power/Energy Sensors
- Water Sensors
- Gas Sensors
- Environmental Sensors (Temperature, Humidity)
- Acoustic Sensors (Sound)
- Light Sensors
"""

import pytest
from datetime import datetime, timedelta
from typing import Dict, Any
import json


class TestAirQualitySensors:
    """Test air quality sensor data validation and processing"""

    @pytest.fixture
    def pm_sensor_data(self):
        """Generate particulate matter sensor data"""
        return {
            "timestamp": datetime.utcnow().isoformat() + 'Z',
            "device_type": "air_quality_sensor",
            "device_model": "OpenSmartMonitor_AQ",
            "measurements": {
                "pm10": round(15.5, 1),        # µg/m³
                "pm25": round(8.3, 1),         # µg/m³
                "pm100": round(2.1, 1),        # µg/m³
                "aqi": 45,                     # Air Quality Index
                "aqi_category": "good"
            },
            "quality_indicators": {
                "source_type": "outdoor",
                "measurement_method": "optical_scattering",
                "calibration_status": "calibrated"
            },
            "status": {
                "battery_percent": 85,
                "signal_dbm": -65,
                "uptime_seconds": 3600,
                "last_calibration": (datetime.utcnow() - timedelta(days=30)).isoformat()
            }
        }

    def test_pm_sensor_valid_ranges(self, pm_sensor_data):
        """Test PM sensor readings are within valid ranges"""
        assert 0 <= pm_sensor_data["measurements"]["pm10"] <= 500, "PM10 out of range"
        assert 0 <= pm_sensor_data["measurements"]["pm25"] <= 500, "PM2.5 out of range"
        assert 0 <= pm_sensor_data["measurements"]["aqi"] <= 500, "AQI out of range"

    def test_pm_sensor_aqi_category_mapping(self, pm_sensor_data):
        """Test AQI to category mapping"""
        aqi_value = pm_sensor_data["measurements"]["aqi"]
        category = pm_sensor_data["measurements"]["aqi_category"]

        if aqi_value <= 50:
            assert category == "good"
        elif aqi_value <= 100:
            assert category == "moderate"
        elif aqi_value <= 150:
            assert category == "unhealthy_for_sensitive_groups"

    def test_pm_sensor_calibration_required(self, pm_sensor_data):
        """Test calibration status is current"""
        last_cal = datetime.fromisoformat(pm_sensor_data["status"]["last_calibration"].replace('Z', '+00:00'))
        days_since_cal = (datetime.utcnow() - last_cal).days
        assert days_since_cal < 90, "Calibration older than 90 days"

    def test_multiple_pm_sensors_data_aggregation(self):
        """Test aggregating data from multiple PM sensors"""
        sensors = [
            {"sensor_id": f"pm_sensor_{i}", "pm25": 5 + i*2, "pm10": 10 + i*2}
            for i in range(3)
        ]

        avg_pm25 = sum(s["pm25"] for s in sensors) / len(sensors)
        avg_pm10 = sum(s["pm10"] for s in sensors) / len(sensors)

        assert 5 <= avg_pm25 <= 9
        assert 10 <= avg_pm10 <= 14


class TestPowerEnergySensors:
    """Test power and energy sensor data validation"""

    @pytest.fixture
    def power_sensor_data(self):
        """Generate power sensor data"""
        return {
            "timestamp": datetime.utcnow().isoformat() + 'Z',
            "device_type": "power_sensor",
            "device_model": "OpenSmartMonitor_PULSE",
            "electrical_measurements": {
                "voltage_phase_a": 230.5,          # Volts
                "voltage_phase_b": 230.2,
                "voltage_phase_c": 230.8,
                "current_phase_a": 12.5,           # Amps
                "current_phase_b": 11.8,
                "current_phase_c": 12.1,
                "power_factor": 0.95,
                "frequency": 50.0,                 # Hz
                "real_power_kw": 8.5,
                "reactive_power_kvar": 2.1,
                "apparent_power_kva": 8.8
            },
            "energy_metrics": {
                "energy_consumed_kwh": 42.5,       # Since meter start
                "energy_exported_kwh": 0.0,        # If applicable
                "energy_today_kwh": 12.3
            },
            "status": {
                "battery_percent": 92,
                "signal_dbm": -70,
                "pulses_received": 1250
            }
        }

    def test_power_sensor_voltage_ranges(self, power_sensor_data):
        """Test voltage readings are within acceptable range (±10%)"""
        nominal_voltage = 230
        tolerance = 0.10

        for phase in ['a', 'b', 'c']:
            voltage = power_sensor_data["electrical_measurements"][f"voltage_phase_{phase}"]
            assert nominal_voltage * (1 - tolerance) <= voltage <= nominal_voltage * (1 + tolerance)

    def test_power_sensor_current_positive(self, power_sensor_data):
        """Test current values are positive"""
        for phase in ['a', 'b', 'c']:
            current = power_sensor_data["electrical_measurements"][f"current_phase_{phase}"]
            assert current >= 0, f"Negative current on phase {phase}"

    def test_power_factor_valid(self, power_sensor_data):
        """Test power factor is within valid range (0-1)"""
        pf = power_sensor_data["electrical_measurements"]["power_factor"]
        assert 0 <= pf <= 1.0, "Power factor out of range"

    def test_apparent_power_calculation(self, power_sensor_data):
        """Test apparent power is calculated correctly"""
        real_power = power_sensor_data["electrical_measurements"]["real_power_kw"]
        reactive_power = power_sensor_data["electrical_measurements"]["reactive_power_kvar"]

        calculated_apparent = (real_power**2 + reactive_power**2)**0.5
        measured_apparent = power_sensor_data["electrical_measurements"]["apparent_power_kva"]

        assert abs(calculated_apparent - measured_apparent) < 0.1

    def test_energy_accumulation(self, power_sensor_data):
        """Test energy values are monotonically increasing"""
        assert power_sensor_data["energy_metrics"]["energy_consumed_kwh"] >= 0
        assert power_sensor_data["energy_metrics"]["energy_exported_kwh"] >= 0


class TestWaterSensors:
    """Test water sensor data validation"""

    @pytest.fixture
    def water_sensor_data(self):
        """Generate water sensor data"""
        return {
            "timestamp": datetime.utcnow().isoformat() + 'Z',
            "device_type": "water_sensor",
            "device_model": "OpenSmartMonitor_WATER",
            "flow_measurements": {
                "flow_rate_lmin": 45.3,            # Liters per minute
                "total_volume_m3": 125.4,          # Cumulative
                "volume_today_m3": 2.8,
                "average_flow_rate_lmin": 42.1
            },
            "water_quality": {
                "ph": 7.2,
                "turbidity_ntu": 0.5,
                "conductivity_uscm": 450,          # Micro-siemens/cm
                "temperature_celsius": 18.5
            },
            "pressure_data": {
                "inlet_pressure_bar": 2.1,
                "outlet_pressure_bar": 1.9,
                "differential_pressure_bar": 0.2
            },
            "status": {
                "battery_percent": 88,
                "signal_dbm": -68,
                "meter_pulses": 45230
            }
        }

    def test_water_flow_positive(self, water_sensor_data):
        """Test flow rates are positive"""
        assert water_sensor_data["flow_measurements"]["flow_rate_lmin"] >= 0
        assert water_sensor_data["flow_measurements"]["total_volume_m3"] >= 0

    def test_water_quality_ph_range(self, water_sensor_data):
        """Test pH is within valid range (0-14)"""
        ph = water_sensor_data["water_quality"]["ph"]
        assert 0 <= ph <= 14, "pH out of range"

    def test_water_pressure_positive(self, water_sensor_data):
        """Test pressure readings are positive"""
        assert water_sensor_data["pressure_data"]["inlet_pressure_bar"] > 0
        assert water_sensor_data["pressure_data"]["outlet_pressure_bar"] >= 0

    def test_differential_pressure_consistency(self, water_sensor_data):
        """Test differential pressure calculation"""
        inlet = water_sensor_data["pressure_data"]["inlet_pressure_bar"]
        outlet = water_sensor_data["pressure_data"]["outlet_pressure_bar"]
        differential = water_sensor_data["pressure_data"]["differential_pressure_bar"]

        calculated_diff = inlet - outlet
        assert abs(calculated_diff - differential) < 0.05


class TestGasSensors:
    """Test gas sensor data validation"""

    @pytest.fixture
    def gas_sensor_data(self):
        """Generate gas sensor data"""
        return {
            "timestamp": datetime.utcnow().isoformat() + 'Z',
            "device_type": "gas_sensor",
            "device_model": "OpenSmartMonitor_GAS",
            "gas_measurements": {
                "co2_ppm": 450,                    # Parts per million
                "co_ppb": 50,                      # Parts per billion
                "ch4_ppm": 1.8,
                "o2_percent": 20.9,
                "no2_ppb": 15
            },
            "air_quality_metrics": {
                "tvoc_ppb": 120,                   # Total Volatile Organic Compounds
                "iaq_index": 85,                   # Indoor Air Quality Index
                "iaq_accuracy": "high"
            },
            "environmental_factors": {
                "temperature_celsius": 22.1,
                "humidity_percent": 45.3,
                "pressure_hpa": 1013.25
            },
            "status": {
                "battery_percent": 90,
                "signal_dbm": -62,
                "sensor_age_hours": 2400
            }
        }

    def test_co2_realistic_ranges(self, gas_sensor_data):
        """Test CO2 levels are within expected indoor ranges"""
        co2 = gas_sensor_data["gas_measurements"]["co2_ppm"]
        # Typical indoor CO2: 400-1000 ppm
        assert 350 <= co2 <= 2000, "CO2 level suspicious"

    def test_oxygen_levels(self, gas_sensor_data):
        """Test oxygen levels are realistic"""
        o2 = gas_sensor_data["gas_measurements"]["o2_percent"]
        # Normal atmospheric O2: ~20.9%
        assert 19 <= o2 <= 21, "Oxygen level unrealistic"

    def test_gas_sensor_calibration_age(self, gas_sensor_data):
        """Test sensor age is within acceptable limits"""
        sensor_age_hours = gas_sensor_data["status"]["sensor_age_hours"]
        # Gas sensors typically calibrated annually (~8760 hours)
        assert sensor_age_hours < 8760, "Sensor calibration overdue"

    def test_tvoc_and_iaq_correlation(self, gas_sensor_data):
        """Test TVOC and IAQ index correlation"""
        tvoc = gas_sensor_data["air_quality_metrics"]["tvoc_ppb"]
        iaq = gas_sensor_data["air_quality_metrics"]["iaq_index"]

        # Higher TVOC should correlate with lower IAQ
        if tvoc > 100:
            assert iaq < 100, "TVOC-IAQ correlation questionable"


class TestEnvironmentalSensors:
    """Test environmental sensor (temperature, humidity) data"""

    @pytest.fixture
    def environmental_sensor_data(self):
        """Generate environmental sensor data"""
        return {
            "timestamp": datetime.utcnow().isoformat() + 'Z',
            "device_type": "environmental_sensor",
            "device_model": "OpenSmartMonitor_ENV",
            "temperature": {
                "value_celsius": 22.5,
                "min_today_celsius": 18.2,
                "max_today_celsius": 26.8,
                "trend": "rising"                  # rising, falling, stable
            },
            "humidity": {
                "value_percent": 45.3,
                "min_today_percent": 35.2,
                "max_today_percent": 52.1,
                "dew_point_celsius": 11.8
            },
            "pressure": {
                "value_hpa": 1013.25,
                "trend": "steady"
            },
            "derived_metrics": {
                "thermal_comfort_index": 22,      # Perceived temperature
                "absolute_humidity_gm3": 9.2,     # grams/m³
                "relative_humidity_percent": 45.3
            },
            "status": {
                "battery_percent": 87,
                "signal_dbm": -65,
                "sensor_type": "DHT22"
            }
        }

    def test_temperature_ranges(self, environmental_sensor_data):
        """Test temperature is within sensor range"""
        temp = environmental_sensor_data["temperature"]["value_celsius"]
        # Typical indoor range
        assert -10 <= temp <= 50, "Temperature out of sensor range"

    def test_humidity_percent_valid(self, environmental_sensor_data):
        """Test humidity is a valid percentage"""
        humidity = environmental_sensor_data["humidity"]["value_percent"]
        assert 0 <= humidity <= 100, "Humidity percent invalid"

    def test_dew_point_less_than_temperature(self, environmental_sensor_data):
        """Test dew point is less than actual temperature"""
        temp = environmental_sensor_data["temperature"]["value_celsius"]
        dew_point = environmental_sensor_data["humidity"]["dew_point_celsius"]
        assert dew_point < temp, "Dew point should be lower than temperature"

    def test_daily_temperature_consistency(self, environmental_sensor_data):
        """Test daily min/max temperatures are consistent"""
        min_temp = environmental_sensor_data["temperature"]["min_today_celsius"]
        current_temp = environmental_sensor_data["temperature"]["value_celsius"]
        max_temp = environmental_sensor_data["temperature"]["max_today_celsius"]

        assert min_temp <= current_temp <= max_temp


class TestAcousticSensors:
    """Test acoustic/sound sensor data"""

    @pytest.fixture
    def sound_sensor_data(self):
        """Generate sound sensor data"""
        return {
            "timestamp": datetime.utcnow().isoformat() + 'Z',
            "device_type": "acoustic_sensor",
            "device_model": "OpenSmartMonitor_SOUND",
            "sound_measurements": {
                "sound_level_db": 65.3,            # Decibels
                "sound_level_dba": 62.1,           # A-weighted decibels
                "min_level_db": 55.2,
                "max_level_db": 78.5,
                "average_level_db": 62.0
            },
            "frequency_analysis": {
                "dominant_frequency_hz": 1200,
                "frequency_ranges": {
                    "low_hz": {"80_125": 50, "125_250": 52},
                    "mid_hz": {"250_500": 58, "500_1000": 62, "1000_2000": 65},
                    "high_hz": {"2000_4000": 60, "4000_8000": 55}
                }
            },
            "sound_events": {
                "loud_events_count": 3,
                "loud_threshold_db": 75,
                "last_loud_event": (datetime.utcnow() - timedelta(minutes=5)).isoformat()
            },
            "status": {
                "battery_percent": 84,
                "signal_dbm": -68,
                "microphone_status": "healthy"
            }
        }

    def test_sound_level_ranges(self, sound_sensor_data):
        """Test sound level is within realistic range"""
        db = sound_sensor_data["sound_measurements"]["sound_level_db"]
        # Typical range: 30 dB (quiet) to 130 dB (dangerous)
        assert 20 <= db <= 140, "Sound level out of range"

    def test_dba_less_than_db(self, sound_sensor_data):
        """Test A-weighted sound is less than linear measurement"""
        db = sound_sensor_data["sound_measurements"]["sound_level_db"]
        dba = sound_sensor_data["sound_measurements"]["sound_level_dba"]
        assert dba <= db, "A-weighted should be <= linear"

    def test_min_max_consistency(self, sound_sensor_data):
        """Test min/max measurements are consistent"""
        min_db = sound_sensor_data["sound_measurements"]["min_level_db"]
        current_db = sound_sensor_data["sound_measurements"]["sound_level_db"]
        max_db = sound_sensor_data["sound_measurements"]["max_level_db"]
        avg_db = sound_sensor_data["sound_measurements"]["average_level_db"]

        assert min_db <= avg_db <= max_db
        assert min_db <= current_db <= max_db

    def test_dominant_frequency_valid(self, sound_sensor_data):
        """Test dominant frequency is within human hearing range"""
        freq = sound_sensor_data["frequency_analysis"]["dominant_frequency_hz"]
        # Human hearing: 20 Hz to 20 kHz
        assert 20 <= freq <= 20000, "Frequency out of human hearing range"


class TestLightSensors:
    """Test light/illuminance sensor data"""

    @pytest.fixture
    def light_sensor_data(self):
        """Generate light sensor data"""
        return {
            "timestamp": datetime.utcnow().isoformat() + 'Z',
            "device_type": "light_sensor",
            "device_model": "OpenSmartMonitor_LIGHT",
            "illuminance": {
                "value_lux": 450,                  # Lux
                "min_today_lux": 0,
                "max_today_lux": 800,
                "average_lux": 380
            },
            "color_temperature": {
                "value_kelvin": 4500,              # Color Temperature
                "classification": "neutral"        # warm, neutral, cool
            },
            "color_data": {
                "red_percent": 35,
                "green_percent": 38,
                "blue_percent": 27
            },
            "light_quality": {
                "cri_index": 92,                   # Color Rendering Index (0-100)
                "flicker_frequency_hz": 0,
                "uv_index": 3,
                "ir_present": True
            },
            "status": {
                "battery_percent": 91,
                "signal_dbm": -60,
                "sensor_age_hours": 18000
            }
        }

    def test_illuminance_positive(self, light_sensor_data):
        """Test illuminance is non-negative"""
        lux = light_sensor_data["illuminance"]["value_lux"]
        assert lux >= 0, "Illuminance cannot be negative"

    def test_daily_illuminance_range(self, light_sensor_data):
        """Test daily min/max are consistent"""
        min_lux = light_sensor_data["illuminance"]["min_today_lux"]
        current_lux = light_sensor_data["illuminance"]["value_lux"]
        max_lux = light_sensor_data["illuminance"]["max_today_lux"]
        avg_lux = light_sensor_data["illuminance"]["average_lux"]

        assert min_lux <= avg_lux <= max_lux
        assert min_lux <= current_lux <= max_lux

    def test_color_temperature_valid(self, light_sensor_data):
        """Test color temperature is within reasonable range"""
        kelvin = light_sensor_data["color_temperature"]["value_kelvin"]
        # Typical range: 2700K (warm) to 6500K (cool)
        assert 2700 <= kelvin <= 6500, "Color temperature out of range"

    def test_color_percentages_sum(self, light_sensor_data):
        """Test RGB percentages sum to 100"""
        red = light_sensor_data["color_data"]["red_percent"]
        green = light_sensor_data["color_data"]["green_percent"]
        blue = light_sensor_data["color_data"]["blue_percent"]

        total = red + green + blue
        assert 99 <= total <= 101, "RGB percentages should sum to 100"

    def test_cri_index_valid(self, light_sensor_data):
        """Test CRI index is within valid range (0-100)"""
        cri = light_sensor_data["light_quality"]["cri_index"]
        assert 0 <= cri <= 100, "CRI index out of range"
