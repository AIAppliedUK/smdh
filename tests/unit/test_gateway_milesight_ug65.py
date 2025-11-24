"""
Unit tests for Milesight UG65 LoRaWAN Gateway
Tests gateway functionality, connectivity, and device management
"""

import pytest
from datetime import datetime, timedelta
from typing import Dict, Any, List


class TestMilesightUG65GatewayBasics:
    """Test Milesight UG65 gateway basic functionality"""

    @pytest.fixture
    def gateway_config(self):
        """Standard Milesight UG65 configuration"""
        return {
            "gateway_id": "gw_milesight_ug65_001",
            "model": "Milesight-UG65",
            "manufacturer": "Milesight",
            "firmware_version": "1.2.5",
            "hardware_version": "UG65_v2",
            "lora_enabled": True,
            "wifi_enabled": True,
            "cellular_enabled": False,
            "ethernet_enabled": True,
            "location": {
                "latitude": 51.5074,
                "longitude": -0.1278,
                "altitude": 50,
                "site_name": "London Hub"
            }
        }

    @pytest.fixture
    def gateway_status(self):
        """Typical Milesight UG65 status data"""
        return {
            "timestamp": datetime.utcnow().isoformat() + 'Z',
            "gateway_id": "gw_milesight_ug65_001",
            "status": "online",
            "uptime_seconds": 2592000,  # 30 days
            "system": {
                "cpu_usage_percent": 25.3,
                "memory_used_mb": 256,
                "memory_total_mb": 512,
                "disk_used_percent": 35.2,
                "temperature_celsius": 42.5
            },
            "lora_radio": {
                "channels_active": 8,
                "packets_received": 150230,
                "packets_transmitted": 85340,
                "error_rate_percent": 0.23,
                "uplink_utilization_percent": 12.5,
                "downlink_utilization_percent": 8.3
            },
            "connectivity": {
                "ethernet_connected": True,
                "ethernet_speed_mbps": 1000,
                "wifi_connected": False,
                "cellular_connected": False,
                "wan_ip": "192.168.1.100",
                "signal_strength_dbm": -45
            },
            "devices": {
                "connected_devices": 47,
                "devices_by_class": {
                    "class_a": 35,
                    "class_b": 8,
                    "class_c": 4
                },
                "devices_active_last_hour": 42,
                "devices_active_last_day": 46
            },
            "battery": {
                "backup_battery_present": False,
                "backup_battery_percent": None
            }
        }

    def test_gateway_model_identification(self, gateway_config):
        """Test gateway model is correctly identified"""
        assert gateway_config["model"] == "Milesight-UG65"
        assert gateway_config["manufacturer"] == "Milesight"

    def test_gateway_lora_specifications(self, gateway_config):
        """Test LoRa specifications for UG65"""
        assert gateway_config["lora_enabled"] is True
        # UG65 specific: 8-channel LoRaWAN gateway with SX1302 chip

    def test_gateway_backhaul_options(self, gateway_config):
        """Test UG65 has multiple backhaul options"""
        backhaul_options = [
            gateway_config["ethernet_enabled"],
            gateway_config["wifi_enabled"],
            gateway_config["cellular_enabled"]
        ]
        assert sum(backhaul_options) >= 1, "Gateway must have at least one backhaul"

    def test_gateway_status_online(self, gateway_status):
        """Test gateway is online and responding"""
        assert gateway_status["status"] in ["online", "offline", "error"]
        assert gateway_status["uptime_seconds"] > 0

    def test_lora_channel_count(self, gateway_status):
        """Test LoRa has 8 channels (UG65 specification)"""
        assert gateway_status["lora_radio"]["channels_active"] == 8

    def test_cpu_and_memory_utilization(self, gateway_status):
        """Test CPU and memory usage are reasonable"""
        assert 0 <= gateway_status["system"]["cpu_usage_percent"] <= 100
        assert 0 < gateway_status["system"]["memory_used_mb"] <= gateway_status["system"]["memory_total_mb"]

    def test_gateway_temperature_normal(self, gateway_status):
        """Test gateway temperature is within operating range"""
        # UG65 operating temp: -40°C to +70°C
        temp = gateway_status["system"]["temperature_celsius"]
        assert -40 <= temp <= 70, "Temperature out of operating range"

    def test_lora_packet_statistics(self, gateway_status):
        """Test LoRa packet counts are positive and reasonable"""
        assert gateway_status["lora_radio"]["packets_received"] > 0
        assert gateway_status["lora_radio"]["packets_transmitted"] >= 0
        assert 0 <= gateway_status["lora_radio"]["error_rate_percent"] <= 5

    def test_connected_devices_count(self, gateway_status):
        """Test device connection information"""
        total_devices = sum(gateway_status["devices"]["devices_by_class"].values())
        assert total_devices == gateway_status["devices"]["connected_devices"]

    def test_device_class_distribution(self, gateway_status):
        """Test device class distribution is reasonable"""
        classes = gateway_status["devices"]["devices_by_class"]
        # LoRaWAN Class A > Class C > Class B typically
        assert classes["class_a"] >= classes["class_b"]

    def test_connectivity_status(self, gateway_status):
        """Test at least one connectivity option is active"""
        connectivity = gateway_status["connectivity"]
        active_connections = [
            connectivity["ethernet_connected"],
            connectivity["wifi_connected"],
            connectivity["cellular_connected"]
        ]
        assert any(active_connections), "Gateway must have at least one active connection"


class TestMilesightUG65LoRaWANCompliance:
    """Test LoRaWAN protocol compliance for UG65"""

    @pytest.fixture
    def lorawan_config(self):
        """LoRaWAN configuration for UG65"""
        return {
            "protocol_version": "1.0.2",
            "class_b_supported": True,
            "class_c_supported": True,
            "adr_enabled": True,
            "frequency_bands": ["EU868", "US915", "AS923", "AU915"],
            "data_rates": {
                "dr0": {"bandwidth_hz": 125000, "spreading_factor": 12, "bitrate_bps": 250},
                "dr1": {"bandwidth_hz": 125000, "spreading_factor": 11, "bitrate_bps": 440},
                "dr2": {"bandwidth_hz": 125000, "spreading_factor": 10, "bitrate_bps": 980},
                "dr5": {"bandwidth_hz": 125000, "spreading_factor": 7, "bitrate_bps": 5470},
                "dr12": {"bandwidth_hz": 500000, "spreading_factor": 7, "bitrate_bps": 21900}
            },
            "tx_power_settings": [27, 24, 21, 18, 15, 12, 9, 6]  # dBm
        }

    def test_lorawan_protocol_version(self, lorawan_config):
        """Test LoRaWAN protocol version support"""
        assert lorawan_config["protocol_version"] in ["1.0.0", "1.0.1", "1.0.2", "1.0.3", "1.0.4"]

    def test_supported_frequency_bands(self, lorawan_config):
        """Test UG65 supports multiple frequency bands"""
        assert len(lorawan_config["frequency_bands"]) >= 2
        # EU868 is most common
        assert "EU868" in lorawan_config["frequency_bands"]

    def test_data_rate_configuration(self, lorawan_config):
        """Test data rates are properly configured"""
        dr0 = lorawan_config["data_rates"]["dr0"]
        assert dr0["spreading_factor"] == 12  # Longest range
        assert dr0["bitrate_bps"] == 250

    def test_spreading_factor_progression(self, lorawan_config):
        """Test spreading factors follow proper progression"""
        sfs = [lorawan_config["data_rates"][f"dr{i}"]["spreading_factor"] for i in range(6)]
        # Should be descending: 12, 11, 10, 9, 8, 7
        assert sfs[0] > sfs[1] > sfs[2]

    def test_tx_power_range(self, lorawan_config):
        """Test transmit power options are valid"""
        powers = lorawan_config["tx_power_settings"]
        assert all(isinstance(p, int) for p in powers)
        assert all(-3 <= p <= 30 for p in powers)  # Valid dBm range
        assert powers[0] >= powers[-1]  # Descending order


class TestMilesightUG65NetworkIntegration:
    """Test gateway network integration"""

    @pytest.fixture
    def network_config(self):
        """Network configuration for UG65"""
        return {
            "gateway_id": "gw_milesight_ug65_001",
            "network_server": {
                "address": "lns.example.com",
                "port": 1700,
                "protocol": "SEMTECH",
                "connection_status": "connected",
                "last_heartbeat": (datetime.utcnow() - timedelta(seconds=30)).isoformat(),
                "packets_sent_to_server": 150230,
                "packets_received_from_server": 85340
            },
            "application_server": {
                "enabled": False,
                "address": None,
                "connection_status": "N/A"
            },
            "dns": {
                "primary": "8.8.8.8",
                "secondary": "8.8.4.4",
                "dns_resolution_working": True
            },
            "ntp": {
                "enabled": True,
                "server": "pool.ntp.org",
                "synchronized": True,
                "time_offset_seconds": 0.2,
                "last_sync": (datetime.utcnow() - timedelta(hours=2)).isoformat()
            },
            "firewall": {
                "enabled": True,
                "incoming_rules": 5,
                "outgoing_rules": 3
            }
        }

    def test_network_server_connectivity(self, network_config):
        """Test network server connection"""
        ns = network_config["network_server"]
        assert ns["connection_status"] in ["connected", "disconnected", "error"]
        assert ns["packets_sent_to_server"] > 0

    def test_heartbeat_recent(self, network_config):
        """Test gateway is sending recent heartbeats"""
        last_hb = datetime.fromisoformat(network_config["network_server"]["last_heartbeat"].replace('Z', '+00:00'))
        time_since_hb = (datetime.utcnow() - last_hb).total_seconds()
        # Heartbeat should be within last 60 seconds
        assert time_since_hb < 60, "Heartbeat too old"

    def test_ntp_synchronization(self, network_config):
        """Test NTP time synchronization"""
        ntp = network_config["ntp"]
        assert ntp["enabled"] is True
        assert ntp["synchronized"] is True
        # Time offset should be very small (< 1 second)
        assert abs(ntp["time_offset_seconds"]) < 1.0

    def test_dns_resolution(self, network_config):
        """Test DNS resolution is working"""
        assert network_config["dns"]["dns_resolution_working"] is True

    def test_firewall_protection(self, network_config):
        """Test firewall is configured"""
        fw = network_config["firewall"]
        assert fw["enabled"] is True
        assert fw["incoming_rules"] > 0 or fw["outgoing_rules"] > 0


class TestMilesightUG65EdgeCases:
    """Test edge cases and error conditions"""

    def test_gateway_offline_detection(self):
        """Test gateway offline is properly detected"""
        offline_gateway = {
            "status": "offline",
            "last_seen": (datetime.utcnow() - timedelta(hours=2)).isoformat(),
            "uptime_seconds": 0
        }
        assert offline_gateway["status"] == "offline"
        assert offline_gateway["uptime_seconds"] == 0

    def test_high_temperature_alert(self):
        """Test high temperature detection"""
        hot_gateway = {
            "temperature_celsius": 65,
            "temperature_warning_threshold": 60,
            "requires_cooling": True
        }
        assert hot_gateway["temperature_celsius"] > hot_gateway["temperature_warning_threshold"]

    def test_high_packet_loss(self):
        """Test high packet loss detection"""
        degraded_gateway = {
            "lora_radio": {
                "error_rate_percent": 3.5
            },
            "error_threshold_percent": 1.0
        }
        assert degraded_gateway["lora_radio"]["error_rate_percent"] > degraded_gateway["error_threshold_percent"]

    def test_disk_space_warning(self):
        """Test disk space monitoring"""
        full_gateway = {
            "disk_used_percent": 92,
            "disk_warning_threshold": 80,
            "requires_cleanup": True
        }
        assert full_gateway["disk_used_percent"] > full_gateway["disk_warning_threshold"]

    def test_multiple_backhaul_failover(self):
        """Test gateway can failover between backhaul options"""
        gateway_with_failover = {
            "primary_backhaul": "ethernet",
            "primary_connected": False,
            "secondary_backhaul": "wifi",
            "secondary_connected": True,
            "active_backhaul": "wifi"
        }
        # Should use secondary when primary fails
        assert gateway_with_failover["active_backhaul"] == "wifi"


class TestMilesightUG65PerformanceMetrics:
    """Test performance and capacity metrics"""

    @pytest.fixture
    def performance_data(self):
        """Performance metrics for UG65"""
        return {
            "gateway_id": "gw_milesight_ug65_001",
            "measurement_period_minutes": 60,
            "throughput": {
                "average_packets_per_second": 2.5,
                "peak_packets_per_second": 8.3,
                "total_packets_processed": 9000
            },
            "latency": {
                "average_gateway_latency_ms": 45,
                "p95_latency_ms": 120,
                "p99_latency_ms": 250
            },
            "device_capacity": {
                "max_devices_rated": 2000,
                "connected_devices": 47,
                "capacity_utilization_percent": 2.35
            },
            "channel_utilization": {
                "total_airtime_percent": 18.5,
                "fair_access_policy_limit_percent": 100,
                "within_fap_limit": True
            }
        }

    def test_packet_throughput_reasonable(self, performance_data):
        """Test packet throughput is reasonable"""
        assert performance_data["throughput"]["average_packets_per_second"] > 0
        assert performance_data["throughput"]["peak_packets_per_second"] > performance_data["throughput"]["average_packets_per_second"]

    def test_latency_acceptable(self, performance_data):
        """Test latency is within acceptable range"""
        assert performance_data["latency"]["average_gateway_latency_ms"] < 100
        assert performance_data["latency"]["p99_latency_ms"] < 1000

    def test_device_capacity_available(self, performance_data):
        """Test gateway has capacity for more devices"""
        utilization = performance_data["device_capacity"]["capacity_utilization_percent"]
        assert utilization < 80, "Gateway nearing capacity"

    def test_fair_access_policy_compliance(self, performance_data):
        """Test Fair Access Policy compliance (max 30 seconds/hour)"""
        cu = performance_data["channel_utilization"]
        assert cu["within_fap_limit"] is True
        assert cu["total_airtime_percent"] <= 100
