"""
Pytest configuration and fixtures for SMDH testing
Provides database connections, test data, and helper utilities

This module includes:
- Basic Snowflake connection fixtures
- Test data generators for IoT pipeline testing
"""

import pytest
import os
import json
from datetime import datetime, timedelta
from typing import Dict, List, Any, Generator
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class SnowflakeTestConnection:
    """Helper class to manage Snowflake test connections"""

    def __init__(self, account: str, user: str, password: str, database: str, warehouse: str):
        """Initialize Snowflake connection parameters"""
        self.account = account
        self.user = user
        self.password = password
        self.database = database
        self.warehouse = warehouse
        self.connection = None

    def connect(self):
        """Establish connection to Snowflake"""
        try:
            import snowflake.connector
            self.connection = snowflake.connector.connect(
                account=self.account,
                user=self.user,
                password=self.password,
                database=self.database,
                warehouse=self.warehouse,
                session_parameters={
                    'TIMEZONE': 'UTC',
                    'JDBC_QUERY_RESULT_FORMAT': 'JSON'
                }
            )
            logger.info(f"✅ Connected to Snowflake: {self.account}/{self.database}")
            return self.connection
        except Exception as e:
            logger.error(f"❌ Failed to connect to Snowflake: {e}")
            raise

    def execute(self, query: str) -> List[Dict]:
        """Execute a query and return results"""
        if not self.connection:
            self.connect()

        cursor = self.connection.cursor()
        try:
            cursor.execute(query)
            results = cursor.fetchall()
            return results
        finally:
            cursor.close()

    def close(self):
        """Close the connection"""
        if self.connection:
            self.connection.close()
            logger.info("Connection closed")


# ============================================================================
# FIXTURES - Database Connection
# ============================================================================

@pytest.fixture(scope="session")
def snowflake_config() -> Dict[str, str]:
    """Load Snowflake configuration from environment variables"""
    config = {
        'account': os.getenv('SNOWFLAKE_ACCOUNT', 'test_account'),
        'user': os.getenv('SNOWFLAKE_USER', 'test_user'),
        'password': os.getenv('SNOWFLAKE_PASSWORD', 'test_password'),
        'database': os.getenv('SNOWFLAKE_DATABASE', 'SMDH_TENANT_TEST_TENANT'),
        'warehouse': os.getenv('SNOWFLAKE_WAREHOUSE', 'COMPUTE_WH'),
        'region': os.getenv('SNOWFLAKE_REGION', 'us-east-1')
    }
    return config


@pytest.fixture(scope="session")
def sf_connection(snowflake_config: Dict[str, str]) -> Generator:
    """Provide Snowflake database connection for the test session"""
    try:
        import snowflake.connector

        conn = snowflake.connector.connect(
            account=snowflake_config['account'],
            user=snowflake_config['user'],
            password=snowflake_config['password'],
            database=snowflake_config['database'],
            warehouse=snowflake_config['warehouse']
        )

        yield conn

        # Cleanup
        conn.close()

    except ImportError:
        pytest.skip("snowflake-connector-python not installed")
    except Exception as e:
        logger.warning(f"⚠️ Snowflake connection failed: {e}. Tests will be skipped.")
        pytest.skip(f"Snowflake connection failed: {e}")


# ============================================================================
# FIXTURES - Test Data Generators
# ============================================================================

@pytest.fixture
def tenant_id() -> str:
    """Provide a test tenant ID"""
    return "test_tenant_001"


@pytest.fixture
def machine_id() -> str:
    """Provide a test machine ID"""
    return "machine_001"


@pytest.fixture
def site_id() -> str:
    """Provide a test site ID"""
    return "site_001"


@pytest.fixture
def sensor_id() -> str:
    """Provide a test sensor ID"""
    return "sensor_001"


@pytest.fixture
def raw_clamp_reading(tenant_id: str, machine_id: str, sensor_id: str) -> Dict[str, Any]:
    """Generate a sample clamp sensor reading"""
    return {
        'reading_id': 'test_reading_001',
        'tenant_id': tenant_id,
        'machine_id': machine_id,
        'sensor_id': sensor_id,
        'timestamp': datetime.utcnow().isoformat(),
        'current_phase_a': 12.5,
        'current_phase_b': 13.2,
        'current_phase_c': 12.8,
        'current_rms': 12.8,
        'voltage_phase_a': 230.0,
        'voltage_phase_b': 230.5,
        'voltage_phase_c': 229.8,
        'power_factor': 0.95,
        'frequency': 50.0,
        'raw_payload': {
            'device_type': 'clamp_sensor',
            'model': 'OpenSmartMonitor_PULSE'
        }
    }


@pytest.fixture
def power_metrics_batch(tenant_id: str, machine_id: str) -> List[Dict[str, Any]]:
    """Generate a batch of power metrics for testing"""
    base_time = datetime.utcnow()
    metrics = []

    for i in range(60):  # 60 minutes of data
        timestamp = base_time - timedelta(minutes=60-i)
        # Simulate power consumption pattern: OFF -> IDLE -> WORKING -> OFF
        if i < 20:
            power = 0.1  # OFF state
        elif i < 30:
            power = 2.5  # IDLE state
        elif i < 50:
            power = 8.5  # WORKING state
        else:
            power = 0.1  # OFF state

        metrics.append({
            'metric_id': f'metric_{i:04d}',
            'tenant_id': tenant_id,
            'machine_id': machine_id,
            'timestamp': timestamp.isoformat(),
            'apparent_power_kva': power * 1.05,
            'real_power_kw': power,
            'reactive_power_kvar': power * 0.5,
            'power_factor': 0.95,
            'energy_kwh': power / 60,  # Per minute
            'avg_current_amps': power / 0.23,
            'max_current_amps': power / 0.23 * 1.1,
            'avg_voltage_volts': 230.0,
            'thd_current': 5.0,
            'thd_voltage': 2.0
        })

    return metrics


@pytest.fixture
def machine_state_batch(tenant_id: str, machine_id: str) -> List[Dict[str, Any]]:
    """Generate a batch of machine states"""
    base_time = datetime.utcnow()
    states = []

    # Create state timeline
    state_sequence = ['OFF'] * 20 + ['IDLE'] * 10 + ['WORKING'] * 20 + ['OFF'] * 10

    for i, state in enumerate(state_sequence):
        timestamp = base_time - timedelta(minutes=60-i)

        # Power varies by state
        if state == 'OFF':
            power = 0.1
            confidence = 0.98
        elif state == 'IDLE':
            power = 2.5
            confidence = 0.92
        else:  # WORKING
            power = 8.5
            confidence = 0.95

        states.append({
            'state_id': f'state_{i:04d}',
            'tenant_id': tenant_id,
            'machine_id': machine_id,
            'timestamp_utc': timestamp.isoformat(),
            'date_key': timestamp.date().isoformat(),
            'hour_of_day': timestamp.hour,
            'state': state,
            'state_confidence': confidence,
            'power_kw': power,
            'current_amps': power / 0.23,
            'power_factor': 0.95,
            'interval_minutes': 1,
            'energy_kwh': power / 60,
            'tariff_band': 'peak' if 9 <= timestamp.hour <= 17 else 'offpeak',
            'rate_per_kwh': 0.28 if 9 <= timestamp.hour <= 17 else 0.15,
            'cost_gbp': (power / 60) * (0.28 if 9 <= timestamp.hour <= 17 else 0.15),
            'data_quality': 'good'
        })

    return states


@pytest.fixture
def production_event(tenant_id: str, machine_id: str) -> Dict[str, Any]:
    """Generate a sample production event"""
    start_time = datetime.utcnow() - timedelta(minutes=45)
    end_time = start_time + timedelta(minutes=30)

    return {
        'event_id': 'event_001',
        'tenant_id': tenant_id,
        'machine_id': machine_id,
        'start_timestamp': start_time.isoformat(),
        'end_timestamp': end_time.isoformat(),
        'duration_minutes': 30.0,
        'date_key': start_time.date().isoformat(),
        'shift_id': 'shift_001',
        'operator_id': 'operator_001',
        'avg_power_kw': 8.5,
        'max_power_kw': 9.2,
        'total_energy_kwh': 4.25,
        'working_time_minutes': 28.5,
        'idle_time_minutes': 1.5,
        'state_transitions': 2,
        'cluster_id': 'cluster_001',
        'is_outlier': False,
        'outlier_score': 0.15,
        'inferred_product_id': 'product_001',
        'confidence_score': 0.88,
        'is_complete': True,
        'has_anomaly': False,
        'anomaly_type': None
    }


@pytest.fixture
def energy_cost_daily(tenant_id: str, machine_id: str) -> Dict[str, Any]:
    """Generate a sample daily energy cost record"""
    date_key = datetime.utcnow().date().isoformat()

    return {
        'tenant_id': tenant_id,
        'machine_id': machine_id,
        'date_key': date_key,
        'total_hours': 24.0,
        'off_hours': 8.0,
        'idle_hours': 6.0,
        'working_hours': 10.0,
        'total_energy_kwh': 85.5,
        'off_energy_kwh': 0.8,
        'idle_energy_kwh': 15.0,
        'working_energy_kwh': 69.7,
        'total_cost_gbp': 22.45,
        'off_cost_gbp': 0.12,
        'idle_cost_gbp': 3.75,
        'working_cost_gbp': 18.58,
        'peak_energy_kwh': 34.0,
        'peak_cost_gbp': 9.52,
        'shoulder_energy_kwh': 25.5,
        'shoulder_cost_gbp': 6.12,
        'offpeak_energy_kwh': 26.0,
        'offpeak_cost_gbp': 3.90,
        'idle_percentage': 25.0,
        'working_percentage': 41.7,
        'cost_per_working_hour': 1.86
    }


# ============================================================================
# FIXTURES - SQL Query Helpers
# ============================================================================

@pytest.fixture
def sql_insert_clamp_reading(sf_connection) -> callable:
    """Provide a function to insert clamp sensor readings"""
    def _insert(reading: Dict[str, Any]) -> bool:
        try:
            cursor = sf_connection.cursor()

            # Note: PARSE_JSON cannot be used in VALUES clause - use INSERT...SELECT
            sql = f"""
            INSERT INTO RAW.CLAMP_SENSOR_READINGS (
                reading_id, tenant_id, machine_id, sensor_id, timestamp,
                current_phase_a, current_phase_b, current_phase_c, current_rms,
                voltage_phase_a, voltage_phase_b, voltage_phase_c,
                power_factor, frequency, raw_payload
            )
            SELECT
                '{reading['reading_id']}',
                '{reading['tenant_id']}',
                '{reading['machine_id']}',
                '{reading['sensor_id']}',
                '{reading['timestamp']}',
                {reading['current_phase_a']},
                {reading['current_phase_b']},
                {reading['current_phase_c']},
                {reading['current_rms']},
                {reading['voltage_phase_a']},
                {reading['voltage_phase_b']},
                {reading['voltage_phase_c']},
                {reading['power_factor']},
                {reading['frequency']},
                PARSE_JSON('{json.dumps(reading["raw_payload"])}')
            """

            cursor.execute(sql)
            cursor.close()
            return True
        except Exception as e:
            logger.error(f"Failed to insert clamp reading: {e}")
            return False

    return _insert


@pytest.fixture
def sql_insert_power_metrics(sf_connection) -> callable:
    """Provide a function to insert power metrics"""
    def _insert(metrics: List[Dict[str, Any]]) -> bool:
        try:
            cursor = sf_connection.cursor()

            for metric in metrics:
                sql = f"""
                INSERT INTO NORMALIZED.POWER_METRICS (
                    metric_id, tenant_id, machine_id, timestamp,
                    apparent_power_kva, real_power_kw, reactive_power_kvar,
                    power_factor, energy_kwh, avg_current_amps, max_current_amps,
                    avg_voltage_volts, thd_current, thd_voltage
                ) VALUES (
                    '{metric['metric_id']}',
                    '{metric['tenant_id']}',
                    '{metric['machine_id']}',
                    '{metric['timestamp']}',
                    {metric['apparent_power_kva']},
                    {metric['real_power_kw']},
                    {metric['reactive_power_kvar']},
                    {metric['power_factor']},
                    {metric['energy_kwh']},
                    {metric['avg_current_amps']},
                    {metric['max_current_amps']},
                    {metric['avg_voltage_volts']},
                    {metric['thd_current']},
                    {metric['thd_voltage']}
                )
                """
                cursor.execute(sql)

            cursor.close()
            return True
        except Exception as e:
            logger.error(f"Failed to insert power metrics: {e}")
            return False

    return _insert


# ============================================================================
# FIXTURES - Data Cleanup
# ============================================================================

@pytest.fixture
def cleanup_test_data(sf_connection):
    """Cleanup test data after each test"""
    yield

    # Cleanup logic
    try:
        cursor = sf_connection.cursor()
        cursor.execute("DELETE FROM RAW.CLAMP_SENSOR_READINGS WHERE TENANT_ID = 'test_tenant_001'")
        cursor.execute("DELETE FROM NORMALIZED.POWER_METRICS WHERE TENANT_ID = 'test_tenant_001'")
        cursor.execute("DELETE FROM MART.FACT_MACHINE_STATE WHERE TENANT_ID = 'test_tenant_001'")
        cursor.execute("DELETE FROM MART.FACT_PRODUCTION_EVENT WHERE TENANT_ID = 'test_tenant_001'")
        cursor.close()
        logger.info("✅ Test data cleaned up")
    except Exception as e:
        logger.warning(f"⚠️ Cleanup failed: {e}")


# ============================================================================
# MARKERS
# ============================================================================

def pytest_configure(config):
    """Register custom pytest markers"""
    config.addinivalue_line(
        "markers", "snowflake: tests that require Snowflake connection"
    )
    config.addinivalue_line(
        "markers", "unit: unit tests"
    )
    config.addinivalue_line(
        "markers", "integration: integration tests"
    )
    config.addinivalue_line(
        "markers", "e2e: end-to-end tests"
    )
    config.addinivalue_line(
        "markers", "slow: tests that take a long time"
    )
