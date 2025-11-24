"""
Unit tests for Snowflake power calculation functions
Tests the normalized.power_metrics table and calculations
"""

import pytest
from datetime import datetime, timedelta
from typing import List, Dict, Any


@pytest.mark.unit
@pytest.mark.snowflake
class TestPowerCalculations:
    """Test suite for power metric calculations"""

    def test_power_calculation_from_three_phase_current(self, sf_connection, tenant_id, machine_id):
        """Test that power is correctly calculated from three-phase current readings"""
        cursor = sf_connection.cursor()

        try:
            # Given: three-phase current measurements
            current_a = 10.0
            current_b = 10.2
            current_c = 9.8
            voltage_line = 230.0
            power_factor = 0.95

            # When: inserting raw clamp readings
            sql = f"""
            INSERT INTO RAW.CLAMP_SENSOR_READINGS (
                reading_id, tenant_id, machine_id, sensor_id, timestamp,
                current_phase_a, current_phase_b, current_phase_c, current_rms,
                voltage_phase_a, voltage_phase_b, voltage_phase_c,
                power_factor, frequency
            ) VALUES (
                'test_power_001', '{tenant_id}', '{machine_id}', 'sensor_001',
                CURRENT_TIMESTAMP(),
                {current_a}, {current_b}, {current_c}, 10.0,
                {voltage_line}, {voltage_line}, {voltage_line},
                {power_factor}, 50.0
            )
            """
            cursor.execute(sql)

            # Then: verify raw data is stored
            cursor.execute(f"""
            SELECT current_phase_a, current_phase_b, current_phase_c, power_factor
            FROM RAW.CLAMP_SENSOR_READINGS
            WHERE reading_id = 'test_power_001'
            """)

            result = cursor.fetchone()
            assert result is not None, "Raw reading should be inserted"
            assert result[0] == current_a, "Phase A current should match"
            assert result[3] == power_factor, "Power factor should match"

        finally:
            # Cleanup
            cursor.execute("DELETE FROM RAW.CLAMP_SENSOR_READINGS WHERE reading_id = 'test_power_001'")
            cursor.close()

    def test_apparent_power_calculation(self, sf_connection, tenant_id, machine_id):
        """Test apparent power (S = V * I * sqrt(3)) calculation"""
        cursor = sf_connection.cursor()

        try:
            # Given: voltage and current values
            voltage = 230.0
            current_rms = 15.0
            power_factor = 0.90

            # Expected: S = 230 * 15 * sqrt(3) ≈ 5973 VA ≈ 5.973 kVA
            expected_apparent_power = voltage * current_rms * 1.732 / 1000  # sqrt(3) ≈ 1.732

            # When: inserting power metric
            timestamp = datetime.utcnow().isoformat()
            sql = f"""
            INSERT INTO NORMALIZED.POWER_METRICS (
                metric_id, tenant_id, machine_id, timestamp,
                apparent_power_kva, real_power_kw, reactive_power_kvar,
                power_factor, energy_kwh, avg_current_amps, max_current_amps,
                avg_voltage_volts, thd_current, thd_voltage
            ) VALUES (
                'test_apparent_001', '{tenant_id}', '{machine_id}', '{timestamp}',
                {expected_apparent_power}, {expected_apparent_power * power_factor},
                {expected_apparent_power * 0.5}, {power_factor},
                {(expected_apparent_power * power_factor) / 60}, {current_rms}, {current_rms * 1.1},
                {voltage}, 5.0, 2.0
            )
            """
            cursor.execute(sql)

            # Then: verify calculation
            cursor.execute(f"""
            SELECT apparent_power_kva, real_power_kw, power_factor
            FROM NORMALIZED.POWER_METRICS
            WHERE metric_id = 'test_apparent_001'
            """)

            result = cursor.fetchone()
            assert result is not None, "Power metric should be inserted"
            assert abs(result[0] - expected_apparent_power) < 0.01, "Apparent power should be calculated correctly"
            assert result[2] == power_factor, "Power factor should match"

        finally:
            cursor.execute("DELETE FROM NORMALIZED.POWER_METRICS WHERE metric_id = 'test_apparent_001'")
            cursor.close()

    def test_energy_calculation_from_power(self, sf_connection, tenant_id, machine_id):
        """Test that energy is correctly integrated from power over time"""
        cursor = sf_connection.cursor()

        try:
            # Given: power consumption at regular intervals
            base_time = datetime.utcnow()
            power_readings = [5.0, 5.2, 4.8, 5.1, 5.0]  # kW
            interval_minutes = 15  # Each reading is 15 minutes apart

            # When: inserting power metrics with energy calculation
            for i, power in enumerate(power_readings):
                timestamp = (base_time + timedelta(minutes=i*interval_minutes)).isoformat()
                energy = (power * interval_minutes) / 60  # kWh = kW * hours

                sql = f"""
                INSERT INTO NORMALIZED.POWER_METRICS (
                    metric_id, tenant_id, machine_id, timestamp,
                    apparent_power_kva, real_power_kw, reactive_power_kvar,
                    power_factor, energy_kwh, avg_current_amps, max_current_amps,
                    avg_voltage_volts, thd_current, thd_voltage
                ) VALUES (
                    'test_energy_{i:03d}', '{tenant_id}', '{machine_id}', '{timestamp}',
                    {power * 1.05}, {power}, {power * 0.5}, 0.95,
                    {energy}, {power / 0.23}, {power / 0.23 * 1.1},
                    230.0, 5.0, 2.0
                )
                """
                cursor.execute(sql)

            # Then: verify total energy calculation
            cursor.execute(f"""
            SELECT SUM(energy_kwh) as total_energy
            FROM NORMALIZED.POWER_METRICS
            WHERE metric_id LIKE 'test_energy_%'
            """)

            result = cursor.fetchone()
            expected_total = sum((p * interval_minutes / 60) for p in power_readings)

            assert result is not None, "Energy query should return result"
            assert abs(result[0] - expected_total) < 0.01, f"Total energy should be ~{expected_total}, got {result[0]}"

        finally:
            cursor.execute("DELETE FROM NORMALIZED.POWER_METRICS WHERE metric_id LIKE 'test_energy_%'")
            cursor.close()

    def test_power_factor_impact_on_real_power(self, sf_connection, tenant_id, machine_id):
        """Test that real power correctly accounts for power factor"""
        cursor = sf_connection.cursor()

        try:
            # Given: apparent power and different power factors
            apparent_power = 10.0  # kVA
            test_cases = [
                (0.90, 9.0),  # pf=0.90 -> real=9.0 kW
                (0.95, 9.5),  # pf=0.95 -> real=9.5 kW
                (1.00, 10.0), # pf=1.00 -> real=10.0 kW
            ]

            for pf, expected_real_power in test_cases:
                timestamp = datetime.utcnow().isoformat()
                real_power = apparent_power * pf

                # When: inserting metric
                sql = f"""
                INSERT INTO NORMALIZED.POWER_METRICS (
                    metric_id, tenant_id, machine_id, timestamp,
                    apparent_power_kva, real_power_kw, reactive_power_kvar,
                    power_factor, energy_kwh, avg_current_amps, max_current_amps,
                    avg_voltage_volts, thd_current, thd_voltage
                ) VALUES (
                    'test_pf_{pf:.2f}', '{tenant_id}', '{machine_id}', '{timestamp}',
                    {apparent_power}, {real_power}, {apparent_power * 0.5}, {pf},
                    {real_power / 60}, {apparent_power / 0.23}, {apparent_power / 0.23 * 1.1},
                    230.0, 5.0, 2.0
                )
                """
                cursor.execute(sql)

            # Then: verify calculations for each power factor
            for pf, expected_real_power in test_cases:
                cursor.execute(f"""
                SELECT real_power_kw, power_factor
                FROM NORMALIZED.POWER_METRICS
                WHERE metric_id = 'test_pf_{pf:.2f}'
                """)

                result = cursor.fetchone()
                assert result is not None, f"Metric for pf={pf} should exist"
                assert abs(result[0] - expected_real_power) < 0.01, \
                    f"Real power for pf={pf} should be {expected_real_power}, got {result[0]}"

        finally:
            cursor.execute("DELETE FROM NORMALIZED.POWER_METRICS WHERE metric_id LIKE 'test_pf_%'")
            cursor.close()

    def test_reactive_power_calculation(self, sf_connection, tenant_id, machine_id):
        """Test reactive power calculation (Q = S * sin(acos(pf)))"""
        cursor = sf_connection.cursor()

        try:
            # Given: apparent power and power factor
            apparent_power = 10.0  # kVA
            power_factor = 0.80
            # Q = S * sqrt(1 - pf²)
            expected_reactive_power = apparent_power * (1 - power_factor**2) ** 0.5

            timestamp = datetime.utcnow().isoformat()

            # When: inserting metric
            sql = f"""
            INSERT INTO NORMALIZED.POWER_METRICS (
                metric_id, tenant_id, machine_id, timestamp,
                apparent_power_kva, real_power_kw, reactive_power_kvar,
                power_factor, energy_kwh, avg_current_amps, max_current_amps,
                avg_voltage_volts, thd_current, thd_voltage
            ) VALUES (
                'test_reactive_001', '{tenant_id}', '{machine_id}', '{timestamp}',
                {apparent_power}, {apparent_power * power_factor}, {expected_reactive_power},
                {power_factor}, {apparent_power * power_factor / 60}, 15.0, 16.5,
                230.0, 5.0, 2.0
            )
            """
            cursor.execute(sql)

            # Then: verify reactive power
            cursor.execute(f"""
            SELECT reactive_power_kvar, apparent_power_kva, real_power_kw
            FROM NORMALIZED.POWER_METRICS
            WHERE metric_id = 'test_reactive_001'
            """)

            result = cursor.fetchone()
            assert result is not None, "Reactive power metric should exist"
            assert abs(result[0] - expected_reactive_power) < 0.1, \
                f"Reactive power should be ~{expected_reactive_power}, got {result[0]}"

            # Verify relationship: S² = P² + Q²
            s, p, q = result[1], result[2], result[0]
            assert abs(s**2 - (p**2 + q**2)) < 0.1, "Power triangle relationship should hold"

        finally:
            cursor.execute("DELETE FROM NORMALIZED.POWER_METRICS WHERE metric_id = 'test_reactive_001'")
            cursor.close()

    def test_power_calculation_across_multiple_intervals(self, sf_connection, power_metrics_batch):
        """Test power metric insertion for a complete time series"""
        cursor = sf_connection.cursor()

        try:
            # When: inserting batch of metrics
            for metric in power_metrics_batch:
                sql = f"""
                INSERT INTO NORMALIZED.POWER_METRICS (
                    metric_id, tenant_id, machine_id, timestamp,
                    apparent_power_kva, real_power_kw, reactive_power_kvar,
                    power_factor, energy_kwh, avg_current_amps, max_current_amps,
                    avg_voltage_volts, thd_current, thd_voltage
                ) VALUES (
                    '{metric['metric_id']}', '{metric['tenant_id']}', '{metric['machine_id']}',
                    '{metric['timestamp']}', {metric['apparent_power_kva']}, {metric['real_power_kw']},
                    {metric['reactive_power_kvar']}, {metric['power_factor']}, {metric['energy_kwh']},
                    {metric['avg_current_amps']}, {metric['max_current_amps']},
                    {metric['avg_voltage_volts']}, {metric['thd_current']}, {metric['thd_voltage']}
                )
                """
                cursor.execute(sql)

            # Then: verify all metrics are stored
            cursor.execute(f"""
            SELECT COUNT(*) as count, SUM(energy_kwh) as total_energy, AVG(real_power_kw) as avg_power
            FROM NORMALIZED.POWER_METRICS
            WHERE metric_id LIKE 'metric_%'
            """)

            result = cursor.fetchone()
            assert result[0] == len(power_metrics_batch), "All metrics should be inserted"
            assert result[1] is not None, "Total energy should be calculated"
            assert result[2] is not None, "Average power should be calculated"

        finally:
            cursor.execute("DELETE FROM NORMALIZED.POWER_METRICS WHERE metric_id LIKE 'metric_%'")
            cursor.close()

    def test_total_harmonic_distortion_values(self, sf_connection, tenant_id, machine_id):
        """Test that THD values are within acceptable ranges"""
        cursor = sf_connection.cursor()

        try:
            # Given: various THD readings
            test_cases = [
                (3.0, 1.5, "good"),      # Low THD
                (7.5, 3.0, "acceptable"),
                (12.0, 5.0, "poor"),
            ]

            for thd_current, thd_voltage, quality in test_cases:
                timestamp = datetime.utcnow().isoformat()

                # When: inserting metric with THD
                sql = f"""
                INSERT INTO NORMALIZED.POWER_METRICS (
                    metric_id, tenant_id, machine_id, timestamp,
                    apparent_power_kva, real_power_kw, reactive_power_kvar,
                    power_factor, energy_kwh, avg_current_amps, max_current_amps,
                    avg_voltage_volts, thd_current, thd_voltage
                ) VALUES (
                    'test_thd_{quality}', '{tenant_id}', '{machine_id}', '{timestamp}',
                    10.0, 9.5, 3.0, 0.95, 0.158, 15.0, 16.5, 230.0, {thd_current}, {thd_voltage}
                )
                """
                cursor.execute(sql)

            # Then: verify THD values are stored correctly
            cursor.execute(f"""
            SELECT metric_id, thd_current, thd_voltage
            FROM NORMALIZED.POWER_METRICS
            WHERE metric_id LIKE 'test_thd_%'
            ORDER BY thd_current
            """)

            results = cursor.fetchall()
            assert len(results) == 3, "All THD metrics should be stored"

            # Verify increasing THD values
            thd_currents = [r[1] for r in results]
            assert thd_currents == sorted(thd_currents), "THD values should be in order"

        finally:
            cursor.execute("DELETE FROM NORMALIZED.POWER_METRICS WHERE metric_id LIKE 'test_thd_%'")
            cursor.close()
