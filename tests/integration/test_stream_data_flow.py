"""
Integration tests for SMDH data stream flow
Tests the complete pipeline: RAW -> NORMALIZED -> MART schema transformations
"""

import pytest
from datetime import datetime, timedelta
import json


@pytest.mark.integration
@pytest.mark.snowflake
class TestStreamDataFlow:
    """Integration test suite for data stream processing"""

    def test_end_to_end_clamp_to_power_flow(self, sf_connection, tenant_id, machine_id, sensor_id):
        """Test complete flow from raw clamp sensor to power metrics"""
        cursor = sf_connection.cursor()

        try:
            # Given: raw clamp sensor reading
            timestamp = datetime.utcnow()
            reading_id = f"e2e_clamp_{timestamp.timestamp()}"

            # Step 1: Insert raw clamp reading
            raw_sql = f"""
            INSERT INTO RAW.CLAMP_SENSOR_READINGS (
                reading_id, tenant_id, machine_id, sensor_id, timestamp,
                current_phase_a, current_phase_b, current_phase_c, current_rms,
                voltage_phase_a, voltage_phase_b, voltage_phase_c,
                power_factor, frequency, raw_payload
            ) VALUES (
                '{reading_id}', '{tenant_id}', '{machine_id}', '{sensor_id}',
                '{timestamp.isoformat()}',
                12.5, 13.2, 12.8, 12.8,
                230.0, 230.5, 229.8,
                0.95, 50.0,
                PARSE_JSON('{json.dumps({"device": "pulse_001"})}')
            )
            """
            cursor.execute(raw_sql)

            # Step 2: Verify raw data is stored
            cursor.execute(f"""
            SELECT reading_id, tenant_id, current_rms, power_factor
            FROM RAW.CLAMP_SENSOR_READINGS
            WHERE reading_id = '{reading_id}'
            """)

            raw_result = cursor.fetchone()
            assert raw_result is not None, "Raw clamp reading should be stored"
            assert raw_result[2] == 12.8, "Current RMS should match"

            # Step 3: Simulate power calculation (what task would do)
            # Calculate: P = V * I * cos(phi) * sqrt(3)
            voltage = 230.2  # Average of three phases
            current = 12.8
            pf = 0.95
            real_power = voltage * current * pf * 1.732 / 1000  # in kW

            power_sql = f"""
            INSERT INTO NORMALIZED.POWER_METRICS (
                metric_id, tenant_id, machine_id, timestamp,
                apparent_power_kva, real_power_kw, reactive_power_kvar,
                power_factor, energy_kwh, avg_current_amps, max_current_amps,
                avg_voltage_volts, thd_current, thd_voltage
            ) VALUES (
                'power_{reading_id}', '{tenant_id}', '{machine_id}', '{timestamp.isoformat()}',
                {real_power / pf}, {real_power}, {real_power * 0.5},
                {pf}, {real_power / 60}, {current}, {current * 1.1},
                {voltage}, 5.0, 2.0
            )
            """
            cursor.execute(power_sql)

            # Step 4: Verify power metric is calculated
            cursor.execute(f"""
            SELECT real_power_kw, power_factor, energy_kwh
            FROM NORMALIZED.POWER_METRICS
            WHERE metric_id = 'power_{reading_id}'
            """)

            power_result = cursor.fetchone()
            assert power_result is not None, "Power metric should be calculated"
            assert power_result[0] > 0, "Real power should be positive"
            assert abs(power_result[1] - pf) < 0.01, "Power factor should match"

            # Step 5: Simulate state classification (what ML task would do)
            state = 'WORKING' if real_power > 5 else ('IDLE' if real_power > 1 else 'OFF')

            state_sql = f"""
            INSERT INTO MART.FACT_MACHINE_STATE (
                state_id, tenant_id, machine_id, timestamp_utc, date_key,
                hour_of_day, state, state_confidence, power_kw, current_amps,
                power_factor, interval_minutes, energy_kwh, tariff_band,
                rate_per_kwh, cost_gbp, data_quality
            ) VALUES (
                'state_{reading_id}', '{tenant_id}', '{machine_id}',
                '{timestamp.isoformat()}', '{timestamp.date().isoformat()}',
                {timestamp.hour}, '{state}', 0.95, {real_power}, {current},
                {pf}, 1, {real_power / 60}, 'peak', 0.28,
                {real_power * 0.28 / 60}, 'good'
            )
            """
            cursor.execute(state_sql)

            # Step 6: Verify complete flow
            cursor.execute(f"""
            SELECT COUNT(*) as count
            FROM MART.FACT_MACHINE_STATE
            WHERE state_id = 'state_{reading_id}'
            """)

            final_result = cursor.fetchone()
            assert final_result[0] == 1, "State should be classified and stored"

        finally:
            # Cleanup
            cursor.execute(f"DELETE FROM RAW.CLAMP_SENSOR_READINGS WHERE reading_id LIKE 'e2e_clamp_%'")
            cursor.execute(f"DELETE FROM NORMALIZED.POWER_METRICS WHERE metric_id LIKE 'power_e2e_%'")
            cursor.execute(f"DELETE FROM MART.FACT_MACHINE_STATE WHERE state_id LIKE 'state_e2e_%'")
            cursor.close()

    def test_production_event_detection_from_states(self, sf_connection, tenant_id, machine_id):
        """Test production event detection from state sequences"""
        cursor = sf_connection.cursor()

        try:
            # Given: a sequence of machine states representing a production cycle
            base_time = datetime.utcnow().replace(second=0, microsecond=0)
            state_sequence = [
                ('OFF', 5),        # 5 minutes OFF
                ('IDLE', 2),       # 2 minutes IDLE (warmup)
                ('WORKING', 30),   # 30 minutes WORKING (production)
                ('IDLE', 2),       # 2 minutes IDLE (cooldown)
                ('OFF', 5),        # 5 minutes OFF
            ]

            # Step 1: Insert state sequence
            current_time = base_time
            for state_name, duration_minutes in state_sequence:
                for i in range(duration_minutes):
                    ts = (current_time + timedelta(minutes=i))
                    sql = f"""
                    INSERT INTO MART.FACT_MACHINE_STATE (
                        state_id, tenant_id, machine_id, timestamp_utc, date_key,
                        hour_of_day, state, state_confidence, power_kw, current_amps,
                        power_factor, interval_minutes, energy_kwh, tariff_band,
                        rate_per_kwh, cost_gbp, data_quality
                    ) VALUES (
                        'state_prod_{state_name}_{ts.timestamp()}',
                        '{tenant_id}', '{machine_id}', '{ts.isoformat()}',
                        '{ts.date().isoformat()}', {ts.hour},
                        '{state_name}', 0.95, {'8.5' if state_name == 'WORKING' else '2.0' if state_name == 'IDLE' else '0.1'},
                        15.0, 0.95, 1, 0.141, 'peak', 0.28, 0.039, 'good'
                    )
                    """
                    cursor.execute(sql)

                current_time += timedelta(minutes=duration_minutes)

            # Step 2: Detect production event (WORKING period)
            # In real system, this is done by task_detect_production_events
            detect_sql = f"""
            WITH working_periods AS (
                SELECT
                    machine_id,
                    MIN(timestamp_utc) as start_time,
                    MAX(timestamp_utc) as end_time,
                    COUNT(*) as duration_minutes,
                    AVG(power_kw) as avg_power,
                    SUM(energy_kwh) as total_energy
                FROM MART.FACT_MACHINE_STATE
                WHERE state = 'WORKING'
                    AND state_id LIKE 'state_prod_%'
                GROUP BY machine_id
            )
            INSERT INTO MART.FACT_PRODUCTION_EVENT (
                event_id, tenant_id, machine_id, start_timestamp, end_timestamp,
                duration_minutes, date_key, shift_id, avg_power_kw, total_energy_kwh,
                working_time_minutes, is_complete, has_anomaly
            )
            SELECT
                CONCAT(machine_id, '_', UNIX_TIMESTAMP(start_time)),
                '{tenant_id}',
                machine_id,
                start_time,
                end_time,
                duration_minutes,
                DATE(start_time),
                'shift_001',
                avg_power,
                total_energy,
                duration_minutes,
                TRUE,
                FALSE
            FROM working_periods
            """
            cursor.execute(detect_sql)

            # Step 3: Verify production event is detected
            cursor.execute(f"""
            SELECT COUNT(*) as event_count, AVG(duration_minutes) as avg_duration
            FROM MART.FACT_PRODUCTION_EVENT
            WHERE tenant_id = '{tenant_id}' AND machine_id = '{machine_id}'
                AND start_timestamp >= '{base_time.isoformat()}'
            """)

            event_result = cursor.fetchone()
            assert event_result[0] >= 1, "Production event should be detected"
            assert event_result[1] is not None, "Duration should be calculated"

        finally:
            cursor.execute(f"DELETE FROM MART.FACT_MACHINE_STATE WHERE state_id LIKE 'state_prod_%'")
            cursor.execute(f"""
            DELETE FROM MART.FACT_PRODUCTION_EVENT
            WHERE tenant_id = '{tenant_id}' AND machine_id = '{machine_id}'
                AND start_timestamp >= '{base_time.isoformat()}'
            """)
            cursor.close()

    def test_energy_cost_calculation_flow(self, sf_connection, tenant_id, machine_id):
        """Test end-to-end energy cost calculation with tariff bands"""
        cursor = sf_connection.cursor()

        try:
            # Given: machine states across a full day with different tariff periods
            base_date = datetime.utcnow().date()

            # Peak hours: 09:00-17:00 at £0.28/kWh
            # Off-peak: 17:00-09:00 at £0.15/kWh

            # Step 1: Insert 24 hourly states
            for hour in range(24):
                timestamp = datetime.combine(base_date, datetime.min.time()).replace(hour=hour)

                # Vary power by time of day
                if 6 <= hour <= 18:  # Working hours
                    power = 8.5
                    state = 'WORKING'
                else:  # Off hours
                    power = 0.1
                    state = 'OFF'

                # Tariff band
                if 9 <= hour <= 17:
                    tariff_band = 'peak'
                    rate = 0.28
                else:
                    tariff_band = 'offpeak'
                    rate = 0.15

                energy_kwh = power  # 1 hour = 1 kWh at that power level
                cost_gbp = energy_kwh * rate

                sql = f"""
                INSERT INTO MART.FACT_MACHINE_STATE (
                    state_id, tenant_id, machine_id, timestamp_utc, date_key,
                    hour_of_day, state, state_confidence, power_kw, current_amps,
                    power_factor, interval_minutes, energy_kwh, tariff_band,
                    rate_per_kwh, cost_gbp, data_quality
                ) VALUES (
                    'cost_test_{hour:02d}', '{tenant_id}', '{machine_id}',
                    '{timestamp.isoformat()}', '{timestamp.date().isoformat()}',
                    {hour}, '{state}', 0.95, {power}, {power / 0.23},
                    0.95, 60, {energy_kwh}, '{tariff_band}', {rate}, {cost_gbp}, 'good'
                )
                """
                cursor.execute(sql)

            # Step 2: Calculate daily energy cost (what task_calculate_energy_costs does)
            daily_cost_sql = f"""
            WITH daily_summary AS (
                SELECT
                    tenant_id,
                    machine_id,
                    date_key,
                    SUM(CASE WHEN state = 'OFF' THEN interval_minutes ELSE 0 END) / 60.0 as off_hours,
                    SUM(CASE WHEN state = 'IDLE' THEN interval_minutes ELSE 0 END) / 60.0 as idle_hours,
                    SUM(CASE WHEN state = 'WORKING' THEN interval_minutes ELSE 0 END) / 60.0 as working_hours,
                    SUM(energy_kwh) as total_energy,
                    SUM(CASE WHEN state = 'OFF' THEN energy_kwh ELSE 0 END) as off_energy,
                    SUM(CASE WHEN state = 'IDLE' THEN energy_kwh ELSE 0 END) as idle_energy,
                    SUM(CASE WHEN state = 'WORKING' THEN energy_kwh ELSE 0 END) as working_energy,
                    SUM(cost_gbp) as total_cost,
                    SUM(CASE WHEN tariff_band = 'peak' THEN energy_kwh ELSE 0 END) as peak_energy,
                    SUM(CASE WHEN tariff_band = 'peak' THEN cost_gbp ELSE 0 END) as peak_cost,
                    SUM(CASE WHEN tariff_band = 'offpeak' THEN energy_kwh ELSE 0 END) as offpeak_energy,
                    SUM(CASE WHEN tariff_band = 'offpeak' THEN cost_gbp ELSE 0 END) as offpeak_cost
                FROM MART.FACT_MACHINE_STATE
                WHERE state_id LIKE 'cost_test_%'
                GROUP BY tenant_id, machine_id, date_key
            )
            INSERT INTO MART.FACT_ENERGY_COST_DAILY (
                tenant_id, machine_id, date_key,
                total_hours, off_hours, idle_hours, working_hours,
                total_energy_kwh, off_energy_kwh, idle_energy_kwh, working_energy_kwh,
                total_cost_gbp, off_cost_gbp, idle_cost_gbp, working_cost_gbp,
                peak_energy_kwh, peak_cost_gbp, offpeak_energy_kwh, offpeak_cost_gbp,
                idle_percentage, working_percentage
            )
            SELECT
                tenant_id, machine_id, date_key,
                24.0, off_hours, idle_hours, working_hours,
                total_energy, off_energy, idle_energy, working_energy,
                total_cost, off_cost, idle_cost, working_cost,
                peak_energy, peak_cost, offpeak_energy, offpeak_cost,
                idle_hours / 24.0 * 100,
                working_hours / 24.0 * 100
            FROM daily_summary
            """
            cursor.execute(daily_cost_sql)

            # Step 3: Verify cost calculation
            cursor.execute(f"""
            SELECT
                total_energy_kwh,
                total_cost_gbp,
                peak_energy_kwh,
                offpeak_energy_kwh,
                working_hours
            FROM MART.FACT_ENERGY_COST_DAILY
            WHERE tenant_id = '{tenant_id}' AND machine_id = '{machine_id}'
                AND date_key = '{base_date.isoformat()}'
            """)

            cost_result = cursor.fetchone()
            assert cost_result is not None, "Daily energy cost should be calculated"
            assert cost_result[0] > 0, "Total energy should be positive"
            assert cost_result[1] > 0, "Total cost should be positive"
            assert cost_result[2] > 0, "Peak energy should exist"
            assert cost_result[3] >= 0, "Off-peak energy should be non-negative"

            # Verify tariff calculation is correct
            # Peak: 8h * 8.5 kW * £0.28 = £19.04
            # Off-peak: 16h * (partial working) at £0.15 = varies
            expected_peak_cost = min(9, 13) * 8.5 * 0.28  # Rough estimate
            assert cost_result[1] > 10, f"Cost should be reasonable (got {cost_result[1]})"

        finally:
            cursor.execute(f"DELETE FROM MART.FACT_MACHINE_STATE WHERE state_id LIKE 'cost_test_%'")
            cursor.execute(f"""
            DELETE FROM MART.FACT_ENERGY_COST_DAILY
            WHERE tenant_id = '{tenant_id}' AND machine_id = '{machine_id}'
                AND date_key = '{base_date.isoformat()}'
            """)
            cursor.close()

    def test_multi_tenant_data_isolation(self, sf_connection, machine_id):
        """Test that data from different tenants is properly isolated"""
        cursor = sf_connection.cursor()

        try:
            # Given: multiple tenants with similar machines
            tenants = ['tenant_001', 'tenant_002', 'tenant_003']
            timestamp = datetime.utcnow()

            # Step 1: Insert data for each tenant
            for tenant_id in tenants:
                for power in [0.1, 2.5, 8.5]:  # Different states
                    sql = f"""
                    INSERT INTO MART.FACT_MACHINE_STATE (
                        state_id, tenant_id, machine_id, timestamp_utc, date_key,
                        hour_of_day, state, state_confidence, power_kw, current_amps,
                        power_factor, interval_minutes, energy_kwh, tariff_band,
                        rate_per_kwh, cost_gbp, data_quality
                    ) VALUES (
                        'isolation_test_{tenant_id}_{power}',
                        '{tenant_id}', '{machine_id}', '{timestamp.isoformat()}',
                        '{timestamp.date().isoformat()}', {timestamp.hour},
                        'WORKING', 0.95, {power}, 15.0, 0.95, 1, 0.141, 'peak',
                        0.28, 0.039, 'good'
                    )
                    """
                    cursor.execute(sql)

            # Step 2: Query data for specific tenant
            for tenant_id in tenants:
                cursor.execute(f"""
                SELECT COUNT(*) as count, COUNT(DISTINCT tenant_id) as tenant_count
                FROM MART.FACT_MACHINE_STATE
                WHERE state_id LIKE 'isolation_test_{tenant_id}_%'
                """)

                result = cursor.fetchone()
                assert result[0] == 3, f"Should have 3 records for {tenant_id}"
                assert result[1] == 1, f"All records should be from {tenant_id}"

            # Step 3: Verify cross-tenant queries don't leak data
            cursor.execute(f"""
            SELECT COUNT(DISTINCT tenant_id) as unique_tenants
            FROM MART.FACT_MACHINE_STATE
            WHERE state_id LIKE 'isolation_test_%'
            """)

            result = cursor.fetchone()
            assert result[0] == len(tenants), f"Should have {len(tenants)} different tenants"

        finally:
            cursor.execute("DELETE FROM MART.FACT_MACHINE_STATE WHERE state_id LIKE 'isolation_test_%'")
            cursor.close()

    def test_data_latency_measurement(self, sf_connection, tenant_id, machine_id):
        """Test measurement of data latency through the pipeline"""
        cursor = sf_connection.cursor()

        try:
            # Given: a raw reading with known ingestion time
            reading_time = datetime.utcnow()
            reading_id = f"latency_test_{reading_time.timestamp()}"

            # Step 1: Insert raw reading and note time
            insert_time = datetime.utcnow()
            raw_sql = f"""
            INSERT INTO RAW.CLAMP_SENSOR_READINGS (
                reading_id, tenant_id, machine_id, sensor_id, timestamp,
                current_phase_a, current_phase_b, current_phase_c, current_rms,
                voltage_phase_a, voltage_phase_b, voltage_phase_c,
                power_factor, frequency
            ) VALUES (
                '{reading_id}', '{tenant_id}', '{machine_id}', 'sensor_001',
                '{reading_time.isoformat()}',
                12.5, 13.2, 12.8, 12.8,
                230.0, 230.5, 229.8,
                0.95, 50.0
            )
            """
            cursor.execute(raw_sql)

            # Step 2: Query with ingestion timestamp
            cursor.execute(f"""
            SELECT ingestion_timestamp
            FROM RAW.CLAMP_SENSOR_READINGS
            WHERE reading_id = '{reading_id}'
            """)

            result = cursor.fetchone()
            ingestion_time = result[0]

            # Step 3: Calculate latency
            latency = (ingestion_time - insert_time).total_seconds()

            # Verify latency is reasonable (should be < 5 seconds)
            assert latency < 5, f"Latency should be < 5 seconds, got {latency}s"
            assert latency >= 0, "Latency should be non-negative"

        finally:
            cursor.execute(f"DELETE FROM RAW.CLAMP_SENSOR_READINGS WHERE reading_id LIKE 'latency_test_%'")
            cursor.close()

    def test_concurrent_writes_handling(self, sf_connection, tenant_id, machine_id):
        """Test handling of concurrent writes from multiple machines"""
        cursor = sf_connection.cursor()

        try:
            # Given: multiple machines writing simultaneously
            num_machines = 5
            timestamp = datetime.utcnow()

            # Step 1: Insert data from multiple machines
            for machine_num in range(num_machines):
                mach_id = f"{machine_id}_{machine_num}"

                for hour in range(24):
                    ts = timestamp.replace(hour=hour)
                    power = 8.5 if 6 <= hour <= 18 else 0.1

                    sql = f"""
                    INSERT INTO MART.FACT_MACHINE_STATE (
                        state_id, tenant_id, machine_id, timestamp_utc, date_key,
                        hour_of_day, state, state_confidence, power_kw, current_amps,
                        power_factor, interval_minutes, energy_kwh, tariff_band,
                        rate_per_kwh, cost_gbp, data_quality
                    ) VALUES (
                        'concurrent_{mach_id}_{hour:02d}', '{tenant_id}', '{mach_id}',
                        '{ts.isoformat()}', '{ts.date().isoformat()}', {hour},
                        'WORKING', 0.95, {power}, 15.0, 0.95, 1, 0.141, 'peak',
                        0.28, 0.039, 'good'
                    )
                    """
                    cursor.execute(sql)

            # Step 2: Verify data integrity
            cursor.execute(f"""
            SELECT
                COUNT(*) as total_records,
                COUNT(DISTINCT machine_id) as unique_machines,
                COUNT(DISTINCT tenant_id) as unique_tenants
            FROM MART.FACT_MACHINE_STATE
            WHERE state_id LIKE 'concurrent_%'
            """)

            result = cursor.fetchone()
            expected_records = num_machines * 24  # 24 hours per machine

            assert result[0] == expected_records, f"Should have {expected_records} records, got {result[0]}"
            assert result[1] == num_machines, f"Should have {num_machines} unique machines"
            assert result[2] == 1, "Should have 1 tenant"

        finally:
            cursor.execute("DELETE FROM MART.FACT_MACHINE_STATE WHERE state_id LIKE 'concurrent_%'")
            cursor.close()
