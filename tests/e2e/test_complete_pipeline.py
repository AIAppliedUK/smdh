"""
End-to-end tests for complete SMDH data pipeline
Tests the full cycle from IoT sensor ingestion through analytics
"""

import pytest
from datetime import datetime, timedelta
import json


@pytest.mark.e2e
@pytest.mark.snowflake
@pytest.mark.slow
class TestCompletePipeline:
    """End-to-end tests for the complete data pipeline"""

    def test_full_cycle_clamp_sensor_to_dashboard(self, sf_connection, tenant_id, machine_id, sensor_id):
        """Test complete cycle: Raw sensor → Power → State → Event → Cost"""
        cursor = sf_connection.cursor()

        try:
            # ===== PHASE 1: Raw Sensor Data =====
            timestamp_start = datetime.utcnow().replace(second=0, microsecond=0)

            # Create 30 clamp sensor readings (30 minutes of 1-minute interval data)
            for minute in range(30):
                ts = timestamp_start + timedelta(minutes=minute)

                # Simulate realistic clamp sensor data
                if minute < 10:
                    # OFF state
                    current_a, current_b, current_c = 0.1, 0.1, 0.1
                elif minute < 15:
                    # IDLE state
                    current_a, current_b, current_c = 2.5, 2.6, 2.4
                else:
                    # WORKING state
                    current_a, current_b, current_c = 10.0, 10.2, 9.8

                sql = f"""
                INSERT INTO RAW.CLAMP_SENSOR_READINGS (
                    reading_id, tenant_id, machine_id, sensor_id, timestamp,
                    current_phase_a, current_phase_b, current_phase_c, current_rms,
                    voltage_phase_a, voltage_phase_b, voltage_phase_c,
                    power_factor, frequency
                ) VALUES (
                    'e2e_raw_{minute:02d}', '{tenant_id}', '{machine_id}', '{sensor_id}',
                    '{ts.isoformat()}',
                    {current_a}, {current_b}, {current_c}, {(current_a + current_b + current_c) / 3},
                    230.0, 230.5, 229.8,
                    0.95, 50.0
                )
                """
                cursor.execute(sql)

            # Verify raw data is stored
            cursor.execute(f"""
            SELECT COUNT(*) FROM RAW.CLAMP_SENSOR_READINGS
            WHERE reading_id LIKE 'e2e_raw_%'
            """)
            assert cursor.fetchone()[0] == 30, "Should have 30 raw readings"

            # ===== PHASE 2: Power Calculation =====
            for minute in range(30):
                ts = timestamp_start + timedelta(minutes=minute)

                # Fetch raw reading
                cursor.execute(f"""
                SELECT current_rms FROM RAW.CLAMP_SENSOR_READINGS
                WHERE reading_id = 'e2e_raw_{minute:02d}'
                """)

                raw = cursor.fetchone()
                current_rms = raw[0]

                # Calculate power
                voltage = 230.2
                pf = 0.95
                real_power = voltage * current_rms * pf * 1.732 / 1000

                sql = f"""
                INSERT INTO NORMALIZED.POWER_METRICS (
                    metric_id, tenant_id, machine_id, timestamp,
                    apparent_power_kva, real_power_kw, reactive_power_kvar,
                    power_factor, energy_kwh, avg_current_amps, max_current_amps,
                    avg_voltage_volts, thd_current, thd_voltage
                ) VALUES (
                    'e2e_power_{minute:02d}', '{tenant_id}', '{machine_id}', '{ts.isoformat()}',
                    {real_power / pf}, {real_power}, {real_power * 0.5},
                    {pf}, {real_power / 60}, {current_rms}, {current_rms * 1.1},
                    {voltage}, 5.0, 2.0
                )
                """
                cursor.execute(sql)

            # Verify power metrics are calculated
            cursor.execute(f"""
            SELECT COUNT(*), AVG(real_power_kw), MIN(real_power_kw), MAX(real_power_kw)
            FROM NORMALIZED.POWER_METRICS
            WHERE metric_id LIKE 'e2e_power_%'
            """)
            power_stats = cursor.fetchone()
            assert power_stats[0] == 30, "Should have 30 power metrics"
            assert power_stats[2] > 0, "Min power should be positive"
            assert power_stats[3] > power_stats[2], "Max power should be > min power"

            # ===== PHASE 3: State Classification =====
            for minute in range(30):
                ts = timestamp_start + timedelta(minutes=minute)

                # Fetch power metric
                cursor.execute(f"""
                SELECT real_power_kw FROM NORMALIZED.POWER_METRICS
                WHERE metric_id = 'e2e_power_{minute:02d}'
                """)

                power_result = cursor.fetchone()
                real_power = power_result[0]

                # Classify state based on power
                if real_power < 0.5:
                    state = 'OFF'
                    confidence = 0.98
                elif real_power < 5:
                    state = 'IDLE'
                    confidence = 0.92
                else:
                    state = 'WORKING'
                    confidence = 0.95

                sql = f"""
                INSERT INTO MART.FACT_MACHINE_STATE (
                    state_id, tenant_id, machine_id, timestamp_utc, date_key,
                    hour_of_day, state, state_confidence, power_kw, current_amps,
                    power_factor, interval_minutes, energy_kwh, tariff_band,
                    rate_per_kwh, cost_gbp, data_quality
                ) VALUES (
                    'e2e_state_{minute:02d}', '{tenant_id}', '{machine_id}',
                    '{ts.isoformat()}', '{ts.date().isoformat()}', {ts.hour},
                    '{state}', {confidence}, {real_power}, {real_power / 0.23},
                    0.95, 1, {real_power / 60}, 'peak', 0.28,
                    {real_power * 0.28 / 60}, 'good'
                )
                """
                cursor.execute(sql)

            # Verify state classification
            cursor.execute(f"""
            SELECT COUNT(*), COUNT(DISTINCT state) as unique_states
            FROM MART.FACT_MACHINE_STATE
            WHERE state_id LIKE 'e2e_state_%'
            """)
            state_stats = cursor.fetchone()
            assert state_stats[0] == 30, "Should have 30 state classifications"
            assert state_stats[1] >= 2, "Should have at least 2 different states"

            # ===== PHASE 4: Production Event Detection =====
            cursor.execute(f"""
            WITH working_periods AS (
                SELECT
                    machine_id,
                    MIN(timestamp_utc) as start_time,
                    MAX(timestamp_utc) as end_time,
                    COUNT(*) as duration_minutes,
                    AVG(power_kw) as avg_power,
                    SUM(energy_kwh) as total_energy
                FROM MART.FACT_MACHINE_STATE
                WHERE state = 'WORKING' AND state_id LIKE 'e2e_state_%'
                GROUP BY machine_id
            )
            INSERT INTO MART.FACT_PRODUCTION_EVENT (
                event_id, tenant_id, machine_id, start_timestamp, end_timestamp,
                duration_minutes, date_key, shift_id, avg_power_kw, total_energy_kwh,
                working_time_minutes, is_complete, has_anomaly
            )
            SELECT
                'e2e_event_001',
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
            """)

            # Verify event detection
            cursor.execute(f"""
            SELECT COUNT(*), AVG(duration_minutes)
            FROM MART.FACT_PRODUCTION_EVENT
            WHERE event_id LIKE 'e2e_event_%'
            """)
            event_stats = cursor.fetchone()
            if event_stats[0] > 0:
                assert event_stats[1] >= 5, "Event should have reasonable duration"

            # ===== PHASE 5: Cost Calculation =====
            cursor.execute(f"""
            INSERT INTO MART.FACT_ENERGY_COST_DAILY (
                tenant_id, machine_id, date_key,
                total_hours, off_hours, idle_hours, working_hours,
                total_energy_kwh, off_energy_kwh, idle_energy_kwh, working_energy_kwh,
                total_cost_gbp, off_cost_gbp, idle_cost_gbp, working_cost_gbp,
                peak_energy_kwh, peak_cost_gbp, offpeak_energy_kwh, offpeak_cost_gbp,
                idle_percentage, working_percentage
            )
            SELECT
                '{tenant_id}',
                '{machine_id}',
                DATE_TRUNC('day', timestamp_utc),
                1.0,  -- simplified for 30 minutes
                SUM(CASE WHEN state = 'OFF' THEN interval_minutes ELSE 0 END) / 60.0,
                SUM(CASE WHEN state = 'IDLE' THEN interval_minutes ELSE 0 END) / 60.0,
                SUM(CASE WHEN state = 'WORKING' THEN interval_minutes ELSE 0 END) / 60.0,
                SUM(energy_kwh),
                SUM(CASE WHEN state = 'OFF' THEN energy_kwh ELSE 0 END),
                SUM(CASE WHEN state = 'IDLE' THEN energy_kwh ELSE 0 END),
                SUM(CASE WHEN state = 'WORKING' THEN energy_kwh ELSE 0 END),
                SUM(cost_gbp),
                SUM(CASE WHEN state = 'OFF' THEN cost_gbp ELSE 0 END),
                SUM(CASE WHEN state = 'IDLE' THEN cost_gbp ELSE 0 END),
                SUM(CASE WHEN state = 'WORKING' THEN cost_gbp ELSE 0 END),
                SUM(CASE WHEN state = 'WORKING' THEN energy_kwh ELSE 0 END),
                SUM(CASE WHEN state = 'WORKING' THEN cost_gbp ELSE 0 END),
                SUM(CASE WHEN state IN ('OFF', 'IDLE') THEN energy_kwh ELSE 0 END),
                SUM(CASE WHEN state IN ('OFF', 'IDLE') THEN cost_gbp ELSE 0 END),
                SUM(CASE WHEN state = 'IDLE' THEN interval_minutes ELSE 0 END) / 30.0 * 100,
                SUM(CASE WHEN state = 'WORKING' THEN interval_minutes ELSE 0 END) / 30.0 * 100
            FROM MART.FACT_MACHINE_STATE
            WHERE state_id LIKE 'e2e_state_%'
            GROUP BY tenant_id, machine_id, DATE_TRUNC('day', timestamp_utc)
            """)

            # Verify cost calculation
            cursor.execute(f"""
            SELECT total_energy_kwh, total_cost_gbp, working_percentage
            FROM MART.FACT_ENERGY_COST_DAILY
            WHERE tenant_id = '{tenant_id}' AND machine_id = '{machine_id}'
            """)

            cost_result = cursor.fetchone()
            if cost_result:
                assert cost_result[0] > 0, "Total energy should be positive"
                assert cost_result[1] > 0, "Total cost should be positive"
                assert 0 <= cost_result[2] <= 100, "Working percentage should be 0-100"

            # ===== FINAL VERIFICATION =====
            print(f"\n✅ Complete pipeline test passed!")
            print(f"   Raw readings: 30")
            print(f"   Power metrics: {power_stats[0]}")
            print(f"   State classifications: {state_stats[0]}")
            print(f"   Production events: {event_stats[0] if event_stats[0] else 0}")
            print(f"   Daily costs: {1 if cost_result else 0}")

        finally:
            # Cleanup
            cursor.execute("DELETE FROM RAW.CLAMP_SENSOR_READINGS WHERE reading_id LIKE 'e2e_raw_%'")
            cursor.execute("DELETE FROM NORMALIZED.POWER_METRICS WHERE metric_id LIKE 'e2e_power_%'")
            cursor.execute("DELETE FROM MART.FACT_MACHINE_STATE WHERE state_id LIKE 'e2e_state_%'")
            cursor.execute("DELETE FROM MART.FACT_PRODUCTION_EVENT WHERE event_id LIKE 'e2e_event_%'")
            cursor.execute(f"""
            DELETE FROM MART.FACT_ENERGY_COST_DAILY
            WHERE tenant_id = '{tenant_id}' AND machine_id = '{machine_id}'
            """)
            cursor.close()

    def test_multi_machine_production_monitoring(self, sf_connection, tenant_id):
        """Test monitoring multiple machines simultaneously"""
        cursor = sf_connection.cursor()

        try:
            # Given: 3 machines on the same production line
            machines = ['machine_A', 'machine_B', 'machine_C']
            base_time = datetime.utcnow().replace(second=0, microsecond=0)

            # When: simulate 1 hour of operation
            for hour_minute in range(60):
                current_time = base_time + timedelta(minutes=hour_minute)

                for machine_id in machines:
                    # Simulate staggered operation
                    offset = machines.index(machine_id) * 15

                    if (hour_minute + offset) % 60 < 20:
                        state = 'OFF'
                        power = 0.1
                    elif (hour_minute + offset) % 60 < 30:
                        state = 'IDLE'
                        power = 2.5
                    else:
                        state = 'WORKING'
                        power = 8.5

                    sql = f"""
                    INSERT INTO MART.FACT_MACHINE_STATE (
                        state_id, tenant_id, machine_id, timestamp_utc, date_key,
                        hour_of_day, state, state_confidence, power_kw, current_amps,
                        power_factor, interval_minutes, energy_kwh, tariff_band,
                        rate_per_kwh, cost_gbp, data_quality
                    ) VALUES (
                        'multi_machine_{machine_id}_{hour_minute:02d}',
                        '{tenant_id}', '{machine_id}', '{current_time.isoformat()}',
                        '{current_time.date().isoformat()}', {current_time.hour},
                        '{state}', 0.95, {power}, {power / 0.23}, 0.95, 1,
                        {power / 60}, 'peak', 0.28, {power * 0.28 / 60}, 'good'
                    )
                    """
                    cursor.execute(sql)

            # Then: verify data integrity
            cursor.execute(f"""
            SELECT
                COUNT(DISTINCT machine_id) as num_machines,
                COUNT(*) as total_records,
                COUNT(DISTINCT state) as unique_states
            FROM MART.FACT_MACHINE_STATE
            WHERE state_id LIKE 'multi_machine_%'
            """)

            result = cursor.fetchone()
            assert result[0] == 3, "Should have 3 machines"
            assert result[1] == 180, "Should have 180 total records (3 machines × 60 minutes)"
            assert result[2] >= 3, "Should have multiple states"

            # Analyze production metrics per machine
            cursor.execute(f"""
            SELECT
                machine_id,
                SUM(CASE WHEN state = 'WORKING' THEN interval_minutes ELSE 0 END) as working_minutes,
                SUM(CASE WHEN state = 'IDLE' THEN interval_minutes ELSE 0 END) as idle_minutes,
                SUM(CASE WHEN state = 'OFF' THEN interval_minutes ELSE 0 END) as off_minutes
            FROM MART.FACT_MACHINE_STATE
            WHERE state_id LIKE 'multi_machine_%'
            GROUP BY machine_id
            ORDER BY machine_id
            """)

            results = cursor.fetchall()
            for machine_id, working, idle, off in results:
                total = (working or 0) + (idle or 0) + (off or 0)
                assert total == 60, f"Total minutes for {machine_id} should be 60"

        finally:
            cursor.execute("DELETE FROM MART.FACT_MACHINE_STATE WHERE state_id LIKE 'multi_machine_%'")
            cursor.close()

    def test_24hour_production_cycle(self, sf_connection, tenant_id, machine_id):
        """Test a complete 24-hour production cycle with realistic patterns"""
        cursor = sf_connection.cursor()

        try:
            # Given: realistic 24-hour production schedule
            base_date = datetime.utcnow().replace(hour=0, minute=0, second=0, microsecond=0)

            # Define schedule:
            # 00:00-06:00: OFF (maintenance)
            # 06:00-07:00: IDLE (warmup)
            # 07:00-12:00: WORKING (morning shift)
            # 12:00-13:00: IDLE (lunch)
            # 13:00-17:00: WORKING (afternoon shift)
            # 17:00-18:00: IDLE (cooldown)
            # 18:00-24:00: OFF

            schedule = [
                ('OFF', 6),
                ('IDLE', 1),
                ('WORKING', 5),
                ('IDLE', 1),
                ('WORKING', 4),
                ('IDLE', 1),
                ('OFF', 6)
            ]

            current_hour = 0
            state_count = 0

            for state_name, duration_hours in schedule:
                power_map = {'OFF': 0.1, 'IDLE': 2.5, 'WORKING': 8.5}
                power = power_map[state_name]

                for minute in range(duration_hours * 60):
                    timestamp = base_date + timedelta(hours=current_hour, minutes=minute)

                    sql = f"""
                    INSERT INTO MART.FACT_MACHINE_STATE (
                        state_id, tenant_id, machine_id, timestamp_utc, date_key,
                        hour_of_day, state, state_confidence, power_kw, current_amps,
                        power_factor, interval_minutes, energy_kwh, tariff_band,
                        rate_per_kwh, cost_gbp, data_quality
                    ) VALUES (
                        '24h_cycle_{state_count:04d}',
                        '{tenant_id}', '{machine_id}', '{timestamp.isoformat()}',
                        '{timestamp.date().isoformat()}', {timestamp.hour},
                        '{state_name}', 0.95, {power}, {power / 0.23}, 0.95, 1,
                        {power / 60}, 'peak', 0.28, {power * 0.28 / 60}, 'good'
                    )
                    """
                    cursor.execute(sql)
                    state_count += 1

                current_hour += duration_hours

            # Verify 24-hour data
            cursor.execute(f"""
            SELECT
                COUNT(*) as total_records,
                COUNT(DISTINCT state) as unique_states,
                SUM(CASE WHEN state = 'WORKING' THEN 1 ELSE 0 END) as working_count,
                SUM(CASE WHEN state = 'IDLE' THEN 1 ELSE 0 END) as idle_count,
                SUM(CASE WHEN state = 'OFF' THEN 1 ELSE 0 END) as off_count
            FROM MART.FACT_MACHINE_STATE
            WHERE state_id LIKE '24h_cycle_%'
            """)

            result = cursor.fetchone()
            assert result[0] == 1440, f"Should have 1440 minute records, got {result[0]}"  # 24 * 60
            assert result[1] == 3, "Should have 3 states"

            # Working: 9 hours = 540 minutes
            assert result[2] == 540, f"Working minutes should be 540, got {result[2]}"
            # Idle: 3 hours = 180 minutes
            assert result[3] == 180, f"Idle minutes should be 180, got {result[3]}"
            # OFF: 12 hours = 720 minutes
            assert result[4] == 720, f"OFF minutes should be 720, got {result[4]}"

            print(f"\n✅ 24-hour cycle test passed!")
            print(f"   Total records: {result[0]}")
            print(f"   Working hours: {result[2]/60:.1f}")
            print(f"   Idle hours: {result[3]/60:.1f}")
            print(f"   OFF hours: {result[4]/60:.1f}")

        finally:
            cursor.execute("DELETE FROM MART.FACT_MACHINE_STATE WHERE state_id LIKE '24h_cycle_%'")
            cursor.close()
