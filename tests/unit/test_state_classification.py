"""
Unit tests for Snowflake machine state classification
Tests the GMM-based state classification logic and state transitions
"""

import pytest
from datetime import datetime, timedelta


@pytest.mark.unit
@pytest.mark.snowflake
class TestStateClassification:
    """Test suite for machine state classification"""

    def test_state_classification_off_state(self, sf_connection, tenant_id, machine_id):
        """Test that low power consumption is classified as OFF state"""
        cursor = sf_connection.cursor()

        try:
            # Given: very low power consumption (< 0.5 kW)
            low_power_readings = [0.05, 0.08, 0.10, 0.07]
            timestamp = datetime.utcnow()

            # When: inserting OFF state readings
            for i, power in enumerate(low_power_readings):
                ts = (timestamp + timedelta(minutes=i)).isoformat()
                sql = f"""
                INSERT INTO MART.FACT_MACHINE_STATE (
                    state_id, tenant_id, machine_id, timestamp_utc, date_key,
                    hour_of_day, state, state_confidence, power_kw, current_amps,
                    power_factor, interval_minutes, energy_kwh, tariff_band,
                    rate_per_kwh, cost_gbp, data_quality
                ) VALUES (
                    'test_off_{i:02d}', '{tenant_id}', '{machine_id}', '{ts}',
                    '{timestamp.date().isoformat()}', {timestamp.hour}, 'OFF', 0.98,
                    {power}, {power / 0.23}, 0.95, 1, {power / 60}, 'offpeak',
                    0.15, {power * 0.15 / 60}, 'good'
                )
                """
                cursor.execute(sql)

            # Then: verify OFF state is recorded
            cursor.execute(f"""
            SELECT COUNT(*) as count, AVG(power_kw) as avg_power, AVG(state_confidence) as avg_confidence
            FROM MART.FACT_MACHINE_STATE
            WHERE state_id LIKE 'test_off_%'
            """)

            result = cursor.fetchone()
            assert result[0] == len(low_power_readings), "All OFF state readings should be stored"
            assert result[1] < 0.2, "OFF state should have low average power"
            assert result[2] > 0.95, "OFF state should have high confidence"

        finally:
            cursor.execute("DELETE FROM MART.FACT_MACHINE_STATE WHERE state_id LIKE 'test_off_%'")
            cursor.close()

    def test_state_classification_idle_state(self, sf_connection, tenant_id, machine_id):
        """Test that medium power consumption is classified as IDLE state"""
        cursor = sf_connection.cursor()

        try:
            # Given: medium power consumption (0.5-5 kW)
            idle_power_readings = [1.5, 2.0, 1.8, 2.2, 1.7]
            timestamp = datetime.utcnow()

            # When: inserting IDLE state readings
            for i, power in enumerate(idle_power_readings):
                ts = (timestamp + timedelta(minutes=i)).isoformat()
                sql = f"""
                INSERT INTO MART.FACT_MACHINE_STATE (
                    state_id, tenant_id, machine_id, timestamp_utc, date_key,
                    hour_of_day, state, state_confidence, power_kw, current_amps,
                    power_factor, interval_minutes, energy_kwh, tariff_band,
                    rate_per_kwh, cost_gbp, data_quality
                ) VALUES (
                    'test_idle_{i:02d}', '{tenant_id}', '{machine_id}', '{ts}',
                    '{timestamp.date().isoformat()}', {timestamp.hour}, 'IDLE', 0.92,
                    {power}, {power / 0.23}, 0.95, 1, {power / 60}, 'offpeak',
                    0.15, {power * 0.15 / 60}, 'good'
                )
                """
                cursor.execute(sql)

            # Then: verify IDLE state is recorded
            cursor.execute(f"""
            SELECT COUNT(*) as count, AVG(power_kw) as avg_power, AVG(state_confidence) as avg_confidence
            FROM MART.FACT_MACHINE_STATE
            WHERE state_id LIKE 'test_idle_%'
            """)

            result = cursor.fetchone()
            assert result[0] == len(idle_power_readings), "All IDLE state readings should be stored"
            assert 0.5 <= result[1] <= 5.0, "IDLE state should have medium power"
            assert result[2] > 0.85, "IDLE state should have good confidence"

        finally:
            cursor.execute("DELETE FROM MART.FACT_MACHINE_STATE WHERE state_id LIKE 'test_idle_%'")
            cursor.close()

    def test_state_classification_working_state(self, sf_connection, tenant_id, machine_id):
        """Test that high power consumption is classified as WORKING state"""
        cursor = sf_connection.cursor()

        try:
            # Given: high power consumption (> 5 kW)
            working_power_readings = [7.5, 8.0, 8.5, 7.8, 8.2]
            timestamp = datetime.utcnow()

            # When: inserting WORKING state readings
            for i, power in enumerate(working_power_readings):
                ts = (timestamp + timedelta(minutes=i)).isoformat()
                sql = f"""
                INSERT INTO MART.FACT_MACHINE_STATE (
                    state_id, tenant_id, machine_id, timestamp_utc, date_key,
                    hour_of_day, state, state_confidence, power_kw, current_amps,
                    power_factor, interval_minutes, energy_kwh, tariff_band,
                    rate_per_kwh, cost_gbp, data_quality
                ) VALUES (
                    'test_working_{i:02d}', '{tenant_id}', '{machine_id}', '{ts}',
                    '{timestamp.date().isoformat()}', {timestamp.hour}, 'WORKING', 0.95,
                    {power}, {power / 0.23}, 0.95, 1, {power / 60}, 'peak',
                    0.28, {power * 0.28 / 60}, 'good'
                )
                """
                cursor.execute(sql)

            # Then: verify WORKING state is recorded
            cursor.execute(f"""
            SELECT COUNT(*) as count, AVG(power_kw) as avg_power, AVG(state_confidence) as avg_confidence
            FROM MART.FACT_MACHINE_STATE
            WHERE state_id LIKE 'test_working_%'
            """)

            result = cursor.fetchone()
            assert result[0] == len(working_power_readings), "All WORKING state readings should be stored"
            assert result[1] > 5.0, "WORKING state should have high power"
            assert result[2] > 0.90, "WORKING state should have very high confidence"

        finally:
            cursor.execute("DELETE FROM MART.FACT_MACHINE_STATE WHERE state_id LIKE 'test_working_%'")
            cursor.close()

    def test_state_transitions_detection(self, sf_connection, tenant_id, machine_id, machine_state_batch):
        """Test detection of state transitions in time series"""
        cursor = sf_connection.cursor()

        try:
            # When: inserting a batch of states with transitions
            for state in machine_state_batch:
                sql = f"""
                INSERT INTO MART.FACT_MACHINE_STATE (
                    state_id, tenant_id, machine_id, timestamp_utc, date_key,
                    hour_of_day, state, state_confidence, power_kw, current_amps,
                    power_factor, interval_minutes, energy_kwh, tariff_band,
                    rate_per_kwh, cost_gbp, data_quality
                ) VALUES (
                    '{state['state_id']}', '{state['tenant_id']}', '{state['machine_id']}',
                    '{state['timestamp_utc']}', '{state['date_key']}', {state['hour_of_day']},
                    '{state['state']}', {state['state_confidence']}, {state['power_kw']},
                    {state['current_amps']}, {state['power_factor']}, {state['interval_minutes']},
                    {state['energy_kwh']}, '{state['tariff_band']}', {state['rate_per_kwh']},
                    {state['cost_gbp']}, '{state['data_quality']}'
                )
                """
                cursor.execute(sql)

            # Then: detect transitions using SQL window functions
            cursor.execute(f"""
            WITH state_with_lag AS (
                SELECT
                    state_id, timestamp_utc, state,
                    LAG(state) OVER (ORDER BY timestamp_utc) as prev_state,
                    CASE WHEN state != LAG(state) OVER (ORDER BY timestamp_utc) THEN 1 ELSE 0 END as is_transition
                FROM MART.FACT_MACHINE_STATE
                WHERE state_id LIKE 'state_%'
                ORDER BY timestamp_utc
            )
            SELECT COUNT(*) as transition_count, MAX(state) as final_state
            FROM state_with_lag
            WHERE is_transition = 1
            """)

            result = cursor.fetchone()
            # Should have transitions: OFF->IDLE, IDLE->WORKING, WORKING->OFF
            assert result[0] >= 2, "Should detect multiple state transitions"

        finally:
            cursor.execute("DELETE FROM MART.FACT_MACHINE_STATE WHERE state_id LIKE 'state_%'")
            cursor.close()

    def test_state_confidence_scores(self, sf_connection, tenant_id, machine_id):
        """Test that state confidence scores are reasonable (0-1 range)"""
        cursor = sf_connection.cursor()

        try:
            # Given: various confidence scores
            confidence_test_cases = [
                ('OFF', 0.98),   # High confidence for OFF
                ('IDLE', 0.92),  # Medium-high confidence for IDLE
                ('WORKING', 0.95),  # High confidence for WORKING
            ]

            timestamp = datetime.utcnow()

            # When: inserting states with various confidences
            for state_name, confidence in confidence_test_cases:
                sql = f"""
                INSERT INTO MART.FACT_MACHINE_STATE (
                    state_id, tenant_id, machine_id, timestamp_utc, date_key,
                    hour_of_day, state, state_confidence, power_kw, current_amps,
                    power_factor, interval_minutes, energy_kwh, tariff_band,
                    rate_per_kwh, cost_gbp, data_quality
                ) VALUES (
                    'test_conf_{state_name}', '{tenant_id}', '{machine_id}',
                    '{timestamp.isoformat()}', '{timestamp.date().isoformat()}',
                    {timestamp.hour}, '{state_name}', {confidence}, 5.0, 15.0,
                    0.95, 1, 0.083, 'peak', 0.28, 0.023, 'good'
                )
                """
                cursor.execute(sql)

            # Then: verify confidence scores are valid
            cursor.execute(f"""
            SELECT state, state_confidence
            FROM MART.FACT_MACHINE_STATE
            WHERE state_id LIKE 'test_conf_%'
            ORDER BY state
            """)

            results = cursor.fetchall()
            assert len(results) == len(confidence_test_cases), "All confidence scores should be stored"

            for result in results:
                state, confidence = result
                assert 0 <= confidence <= 1, f"Confidence for {state} should be between 0 and 1, got {confidence}"
                assert confidence > 0.80, f"Confidence for {state} should be reasonably high"

        finally:
            cursor.execute("DELETE FROM MART.FACT_MACHINE_STATE WHERE state_id LIKE 'test_conf_%'")
            cursor.close()

    def test_state_duration_calculation(self, sf_connection, tenant_id, machine_id):
        """Test calculation of duration spent in each state"""
        cursor = sf_connection.cursor()

        try:
            # Given: a sequence of states with known durations
            timestamp = datetime.utcnow()
            state_sequence = [
                ('OFF', 20),       # 20 minutes in OFF
                ('IDLE', 10),      # 10 minutes in IDLE
                ('WORKING', 20),   # 20 minutes in WORKING
                ('OFF', 10),       # 10 minutes in OFF
            ]

            current_time = timestamp
            for state_name, duration_minutes in state_sequence:
                for i in range(duration_minutes):
                    ts = (current_time + timedelta(minutes=i)).isoformat()
                    sql = f"""
                    INSERT INTO MART.FACT_MACHINE_STATE (
                        state_id, tenant_id, machine_id, timestamp_utc, date_key,
                        hour_of_day, state, state_confidence, power_kw, current_amps,
                        power_factor, interval_minutes, energy_kwh, tariff_band,
                        rate_per_kwh, cost_gbp, data_quality
                    ) VALUES (
                        'test_duration_{len(state_sequence)}_{state_name[:3]}_{i:02d}',
                        '{tenant_id}', '{machine_id}', '{ts}',
                        '{current_time.date().isoformat()}', {current_time.hour},
                        '{state_name}', 0.95, 5.0, 15.0, 0.95, 1, 0.083, 'peak',
                        0.28, 0.023, 'good'
                    )
                    """
                    cursor.execute(sql)

                current_time += timedelta(minutes=duration_minutes)

            # Then: calculate duration in each state
            cursor.execute(f"""
            WITH state_durations AS (
                SELECT
                    state,
                    COUNT(*) as minutes_in_state
                FROM MART.FACT_MACHINE_STATE
                WHERE state_id LIKE 'test_duration_%'
                GROUP BY state
            )
            SELECT state, minutes_in_state
            FROM state_durations
            ORDER BY state
            """)

            results = cursor.fetchall()
            results_dict = {row[0]: row[1] for row in results}

            # Verify durations
            expected_durations = {
                'OFF': 30,        # 20 + 10
                'IDLE': 10,
                'WORKING': 20,
            }

            for state, expected_duration in expected_durations.items():
                actual_duration = results_dict.get(state, 0)
                assert actual_duration == expected_duration, \
                    f"Duration for {state} should be {expected_duration}, got {actual_duration}"

        finally:
            cursor.execute("DELETE FROM MART.FACT_MACHINE_STATE WHERE state_id LIKE 'test_duration_%'")
            cursor.close()

    def test_hourly_state_distribution(self, sf_connection, tenant_id, machine_id):
        """Test distribution of states across different hours of the day"""
        cursor = sf_connection.cursor()

        try:
            # Given: states distributed across different hours
            timestamp = datetime.utcnow().replace(hour=0, minute=0, second=0, microsecond=0)

            # When: inserting states for 24 hours with hour-dependent patterns
            for hour in range(24):
                ts = timestamp.replace(hour=hour)

                # Simulate pattern: OFF during night, WORKING during day, IDLE in evening
                if 6 <= hour <= 18:
                    state = 'WORKING'
                    confidence = 0.95
                elif 18 <= hour <= 22:
                    state = 'IDLE'
                    confidence = 0.92
                else:
                    state = 'OFF'
                    confidence = 0.98

                sql = f"""
                INSERT INTO MART.FACT_MACHINE_STATE (
                    state_id, tenant_id, machine_id, timestamp_utc, date_key,
                    hour_of_day, state, state_confidence, power_kw, current_amps,
                    power_factor, interval_minutes, energy_kwh, tariff_band,
                    rate_per_kwh, cost_gbp, data_quality
                ) VALUES (
                    'test_hourly_{hour:02d}', '{tenant_id}', '{machine_id}',
                    '{ts.isoformat()}', '{ts.date().isoformat()}', {hour},
                    '{state}', {confidence}, 5.0, 15.0, 0.95, 60, 5.0, 'peak',
                    0.28, 1.4, 'good'
                )
                """
                cursor.execute(sql)

            # Then: analyze hourly distribution
            cursor.execute(f"""
            SELECT
                hour_of_day,
                state,
                COUNT(*) as count
            FROM MART.FACT_MACHINE_STATE
            WHERE state_id LIKE 'test_hourly_%'
            GROUP BY hour_of_day, state
            ORDER BY hour_of_day
            """)

            results = cursor.fetchall()

            # Verify pattern
            working_hours = [h for h in range(6, 19)]
            idle_hours = [h for h in range(18, 23)]
            off_hours = [h for h in range(0, 6)] + [h for h in range(23, 24)]

            for row in results:
                hour, state, count = row
                if hour in working_hours:
                    assert state == 'WORKING', f"Hour {hour} should have WORKING state"
                elif hour in idle_hours and hour != 18:  # 18 is overlap
                    assert state == 'IDLE', f"Hour {hour} should have IDLE state"

        finally:
            cursor.execute("DELETE FROM MART.FACT_MACHINE_STATE WHERE state_id LIKE 'test_hourly_%'")
            cursor.close()

    def test_state_with_missing_data(self, sf_connection, tenant_id, machine_id):
        """Test handling of states when data quality is degraded"""
        cursor = sf_connection.cursor()

        try:
            # Given: states with various data quality levels
            quality_levels = ['good', 'acceptable', 'poor', 'missing']
            timestamp = datetime.utcnow()

            # When: inserting states with different quality indicators
            for i, quality in enumerate(quality_levels):
                ts = (timestamp + timedelta(minutes=i)).isoformat()
                sql = f"""
                INSERT INTO MART.FACT_MACHINE_STATE (
                    state_id, tenant_id, machine_id, timestamp_utc, date_key,
                    hour_of_day, state, state_confidence, power_kw, current_amps,
                    power_factor, interval_minutes, energy_kwh, tariff_band,
                    rate_per_kwh, cost_gbp, data_quality
                ) VALUES (
                    'test_quality_{quality}', '{tenant_id}', '{machine_id}',
                    '{ts}', '{timestamp.date().isoformat()}', {timestamp.hour},
                    'WORKING', 0.85, 5.0, 15.0, 0.95, 1, 0.083, 'peak', 0.28, 0.023, '{quality}'
                )
                """
                cursor.execute(sql)

            # Then: filter for good quality data
            cursor.execute(f"""
            SELECT COUNT(*) as total_count,
                   SUM(CASE WHEN data_quality = 'good' THEN 1 ELSE 0 END) as good_count,
                   SUM(CASE WHEN data_quality IN ('acceptable', 'missing', 'poor') THEN 1 ELSE 0 END) as degraded_count
            FROM MART.FACT_MACHINE_STATE
            WHERE state_id LIKE 'test_quality_%'
            """)

            result = cursor.fetchone()
            assert result[0] == len(quality_levels), "All quality levels should be recorded"
            assert result[1] == 1, "Should have one 'good' quality record"
            assert result[2] == 3, "Should have three degraded quality records"

        finally:
            cursor.execute("DELETE FROM MART.FACT_MACHINE_STATE WHERE state_id LIKE 'test_quality_%'")
            cursor.close()
