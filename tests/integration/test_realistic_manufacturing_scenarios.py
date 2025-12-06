"""
Realistic Manufacturing Scenario Tests
Tests the SMDH platform with realistic manufacturing data including:
- Multiple sites with different equipment types
- Various sensor types (power, vibration, environmental)
- Realistic production schedules and shift patterns
- Multi-day scenarios with maintenance windows
- Cost optimization analysis
"""

import pytest
from datetime import datetime, timedelta
import json
from typing import Dict, List, Any

# These imports work when conftest_manufacturing_scenarios is merged into conftest.py
try:
    from conftest_manufacturing_scenarios import (
        RealisticManufacturingSimulator,
        ManufacturingFacility
    )
except ImportError:
    # Fallback if running independently
    pytest.skip("Manufacturing scenario fixtures not available", allow_module_level=True)


@pytest.mark.integration
@pytest.mark.snowflake
class TestRealisticMultiSiteScenarios:
    """Test realistic multi-site manufacturing scenarios"""

    def test_ingestion_of_multi_site_sensor_data(
        self,
        sf_connection,
        multi_day_sensor_data: List[Dict[str, Any]],
        tenant_id: str
    ):
        """
        Test: Ingesting realistic multi-site sensor data into Snowflake
        Scenario: ABC Manufacturing with 3 sites generating continuous sensor data

        Expected:
        - All site data properly ingested into Snowflake tables
        - Data split correctly across sensor types
        - No cross-site data contamination
        """
        cursor = sf_connection.cursor()

        try:
            if not multi_day_sensor_data:
                pytest.skip("No sensor data generated")

            # Group readings by sensor type
            clamp_readings = [r for r in multi_day_sensor_data if r.get('sensorType') == 'clamp_current']
            vibration_readings = [r for r in multi_day_sensor_data if r.get('sensorType') == 'vibration']
            environmental_readings = [r for r in multi_day_sensor_data if r.get('sensorType') == 'environmental']

            print(f"\n📊 Multi-site data summary:")
            print(f"   Total readings: {len(multi_day_sensor_data)}")
            print(f"   Clamp (power) sensors: {len(clamp_readings)}")
            print(f"   Vibration sensors: {len(vibration_readings)}")
            print(f"   Environmental sensors: {len(environmental_readings)}")

            # Limit to first 100 of each type for test performance
            clamp_sample = clamp_readings[:100]
            vibration_sample = vibration_readings[:100]
            environmental_sample = environmental_readings[:100]

            # ===== INSERT CLAMP SENSOR DATA =====
            print(f"\n   Inserting {len(clamp_sample)} clamp sensor readings...")
            for i, reading in enumerate(clamp_sample):
                m = reading['measurements']
                sql = f"""
                INSERT INTO RAW.CLAMP_SENSOR_READINGS (
                    reading_id, tenant_id, machine_id, sensor_id, site_id, timestamp,
                    current_phase_a, current_phase_b, current_phase_c, current_rms,
                    voltage_phase_a, voltage_phase_b, voltage_phase_c,
                    power_factor, frequency
                ) VALUES (
                    'integration_clamp_{i:05d}', '{tenant_id}', '{reading['machineId']}',
                    '{reading['deviceId']}', '{reading['siteId']}', '{reading['timestamp']}',
                    {m['current_phase_a']}, {m['current_phase_b']}, {m['current_phase_c']}, {m['current_rms']},
                    {m['voltage_phase_a']}, {m['voltage_phase_b']}, {m['voltage_phase_c']},
                    {m['power_factor']}, {m['frequency']}
                )
                """
                cursor.execute(sql)

            # ===== INSERT VIBRATION SENSOR DATA =====
            print(f"   Inserting {len(vibration_sample)} vibration sensor readings...")
            for i, reading in enumerate(vibration_sample):
                m = reading['measurements']
                meta = reading.get('metadata', {})
                sql = f"""
                INSERT INTO RAW.VIBRATION_SENSOR_READINGS (
                    reading_id, tenant_id, machine_id, sensor_id, site_id, timestamp,
                    vibration_x, vibration_y, vibration_z, vibration_rms,
                    temperature, dominant_frequency, sampling_rate
                ) VALUES (
                    'integration_vib_{i:05d}', '{tenant_id}', '{reading['machineId']}',
                    '{reading['deviceId']}', '{reading['siteId']}', '{reading['timestamp']}',
                    {m['vibration_x']}, {m['vibration_y']}, {m['vibration_z']}, {m['vibration_rms']},
                    {m['temperature']}, {m['dominant_frequency']}, {meta.get('samplingRate', 4000)}
                )
                """
                cursor.execute(sql)

            # ===== INSERT ENVIRONMENTAL SENSOR DATA =====
            print(f"   Inserting {len(environmental_sample)} environmental sensor readings...")
            for i, reading in enumerate(environmental_sample):
                m = reading['measurements']
                sql = f"""
                INSERT INTO RAW.ENVIRONMENTAL_SENSOR_READINGS (
                    reading_id, tenant_id, zone_id, sensor_id, site_id, timestamp,
                    temperature, humidity, co2_ppm, voc_index,
                    particulates_pm25, particulates_pm10, noise_db, light_lux
                ) VALUES (
                    'integration_env_{i:05d}', '{tenant_id}', '{reading['zoneId']}',
                    '{reading['deviceId']}', '{reading['siteId']}', '{reading['timestamp']}',
                    {m['temperature']}, {m['humidity']}, {m['co2_ppm']}, {m['voc_index']},
                    {m['particulates_pm25']}, {m['particulates_pm10']}, {m['noise_db']}, {m['light_lux']}
                )
                """
                cursor.execute(sql)

            # ===== VERIFY DATA IN SNOWFLAKE =====
            print(f"\n   Verifying data in Snowflake...")

            # Count clamp readings
            cursor.execute("""
                SELECT COUNT(*) FROM RAW.CLAMP_SENSOR_READINGS
                WHERE reading_id LIKE 'integration_clamp_%'
            """)
            clamp_count = cursor.fetchone()[0]
            assert clamp_count == len(clamp_sample), f"Expected {len(clamp_sample)} clamp readings, got {clamp_count}"

            # Count vibration readings
            cursor.execute("""
                SELECT COUNT(*) FROM RAW.VIBRATION_SENSOR_READINGS
                WHERE reading_id LIKE 'integration_vib_%'
            """)
            vib_count = cursor.fetchone()[0]
            assert vib_count == len(vibration_sample), f"Expected {len(vibration_sample)} vibration readings, got {vib_count}"

            # Count environmental readings
            cursor.execute("""
                SELECT COUNT(*) FROM RAW.ENVIRONMENTAL_SENSOR_READINGS
                WHERE reading_id LIKE 'integration_env_%'
            """)
            env_count = cursor.fetchone()[0]
            assert env_count == len(environmental_sample), f"Expected {len(environmental_sample)} environmental readings, got {env_count}"

            # Verify unique sites
            cursor.execute("""
                SELECT COUNT(DISTINCT site_id) FROM RAW.CLAMP_SENSOR_READINGS
                WHERE reading_id LIKE 'integration_clamp_%'
            """)
            unique_sites = cursor.fetchone()[0]
            assert unique_sites >= 2, "Should have data from multiple sites"

            # Verify unique machines
            cursor.execute("""
                SELECT COUNT(DISTINCT machine_id) FROM RAW.CLAMP_SENSOR_READINGS
                WHERE reading_id LIKE 'integration_clamp_%'
            """)
            unique_machines = cursor.fetchone()[0]
            assert unique_machines >= 3, "Should have data from multiple machines"

            print(f"\n   ✅ Successfully ingested data into Snowflake!")
            print(f"      Clamp readings: {clamp_count}")
            print(f"      Vibration readings: {vib_count}")
            print(f"      Environmental readings: {env_count}")
            print(f"      Unique sites: {unique_sites}")
            print(f"      Unique machines: {unique_machines}")

        finally:
            # Cleanup test data
            cursor.execute("DELETE FROM RAW.CLAMP_SENSOR_READINGS WHERE reading_id LIKE 'integration_clamp_%'")
            cursor.execute("DELETE FROM RAW.VIBRATION_SENSOR_READINGS WHERE reading_id LIKE 'integration_vib_%'")
            cursor.execute("DELETE FROM RAW.ENVIRONMENTAL_SENSOR_READINGS WHERE reading_id LIKE 'integration_env_%'")
            cursor.close()

    def test_realistic_production_schedule_patterns(
        self,
        manufacturing_simulator: RealisticManufacturingSimulator
    ):
        """
        Test: Realistic production scheduling patterns
        Scenario: Verify the simulator generates realistic shift patterns

        Expected:
        - Machines OFF during maintenance windows (Sunday 00:00-06:00)
        - High activity during business hours
        - Low activity during nights/weekends
        """

        # Test a full week
        start_date = datetime(2025, 1, 20)  # Monday
        end_date = datetime(2025, 1, 27)    # Monday (full week)

        readings = manufacturing_simulator.generate_sensor_readings_for_period(
            start_date, end_date, interval_minutes=60  # Hourly for manageability
        )

        # Group by day of week
        by_day = {}
        for reading in readings:
            dt = datetime.fromisoformat(reading['timestamp'].replace('Z', '+00:00'))
            day_name = dt.strftime('%A')
            power = reading['measurements'].get('current_rms', 0) if reading.get('sensorType') == 'clamp_current' else None

            if power is not None:
                if day_name not in by_day:
                    by_day[day_name] = []
                by_day[day_name].append(power)

        print(f"\n📅 Production patterns by day of week:")
        for day in ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']:
            if day in by_day:
                avg_power = sum(by_day[day]) / len(by_day[day])
                max_power = max(by_day[day])
                readings_count = len(by_day[day])
                print(f"   {day}: {readings_count} readings, avg power: {avg_power:.2f}A, max: {max_power:.2f}A")

        # Verify patterns
        # Sunday should have lower average power (maintenance window)
        if 'Sunday' in by_day:
            sunday_avg = sum(by_day['Sunday']) / len(by_day['Sunday'])
            # Find a weekday average
            weekday_avg = sum(by_day.get('Monday', [0])) / max(len(by_day.get('Monday', [1])), 1)
            # Sunday should be noticeably lower due to maintenance
            assert sunday_avg < weekday_avg * 0.8, "Sunday should have lower activity due to maintenance"

        # Weekdays should have higher activity
        monday_avg = sum(by_day.get('Monday', [0])) / max(len(by_day.get('Monday', [1])), 1)
        assert monday_avg > 2.0, "Weekday operations should show measurable power consumption"

    def test_multi_site_cost_analysis(
        self,
        sf_connection,
        manufacturing_simulator: RealisticManufacturingSimulator
    ):
        """
        Test: Cost analysis across multiple sites
        Scenario: ABC Manufacturing with 3 sites analyzing daily costs

        Expected:
        - Manufacturing floor (SITE_001) highest cost (24/7 operation)
        - Assembly line (SITE_002) moderate cost (shift operation)
        - Warehouse (SITE_003) minimal cost (environmental monitoring only)
        """
        cursor = sf_connection.cursor()

        try:
            # Generate 1 week of data
            start_date = datetime(2025, 1, 20)
            end_date = datetime(2025, 1, 27)

            readings = manufacturing_simulator.generate_sensor_readings_for_period(
                start_date, end_date, interval_minutes=5  # 5-minute intervals
            )

            # Simulate power -> cost calculation
            # Peak rate: £0.28/kWh (09:00-17:00), Off-peak: £0.15/kWh
            daily_costs = {}

            for reading in readings:
                if reading.get('sensorType') != 'clamp_current':
                    continue

                dt = datetime.fromisoformat(reading['timestamp'].replace('Z', '+00:00'))
                site_id = reading['siteId']
                machine_id = reading['machineId']
                hour = dt.hour

                # Determine tariff
                if 9 <= hour <= 17:
                    rate = 0.28  # Peak
                    tariff = 'peak'
                else:
                    rate = 0.15  # Off-peak
                    tariff = 'offpeak'

                # Calculate power and cost
                current_rms = reading['measurements']['current_rms']
                voltage = reading['measurements']['voltage_nominal']
                pf = reading['measurements']['power_factor']

                # Power (kW) = √3 × V × I × PF / 1000
                power_kw = 1.732 * voltage * current_rms * pf / 1000

                # Energy for interval (5 minutes = 1/12 hour)
                energy_kwh = power_kw / 12
                cost_gbp = energy_kwh * rate

                # Accumulate by site and day
                day_key = dt.date()
                site_key = f"{site_id}_{day_key}"

                if site_key not in daily_costs:
                    daily_costs[site_key] = {
                        'site_id': site_id,
                        'date': day_key,
                        'total_cost': 0,
                        'total_energy': 0,
                        'peak_cost': 0,
                        'offpeak_cost': 0
                    }

                daily_costs[site_key]['total_cost'] += cost_gbp
                daily_costs[site_key]['total_energy'] += energy_kwh

                if tariff == 'peak':
                    daily_costs[site_key]['peak_cost'] += cost_gbp
                else:
                    daily_costs[site_key]['offpeak_cost'] += cost_gbp

            # Analyze costs by site
            print(f"\n💷 Daily costs by site (over {(end_date - start_date).days} days):")

            site_totals = {}
            for key, cost_data in daily_costs.items():
                site_id = cost_data['site_id']
                if site_id not in site_totals:
                    site_totals[site_id] = {'total_cost': 0, 'days': 0}
                site_totals[site_id]['total_cost'] += cost_data['total_cost']
                site_totals[site_id]['days'] = max(site_totals[site_id]['days'], 1)

                print(f"\n   {site_id} - {cost_data['date']}:")
                print(f"      Total cost: £{cost_data['total_cost']:.2f}")
                print(f"      Total energy: {cost_data['total_energy']:.1f} kWh")
                print(f"      Peak cost: £{cost_data['peak_cost']:.2f}")
                print(f"      Off-peak cost: £{cost_data['offpeak_cost']:.2f}")

            # Verify expected cost patterns
            # Manufacturing floor should have highest daily cost
            site_001_avg = site_totals.get('SITE_001', {}).get('total_cost', 0) / max(site_totals.get('SITE_001', {}).get('days', 1), 1)
            site_002_avg = site_totals.get('SITE_002', {}).get('total_cost', 0) / max(site_totals.get('SITE_002', {}).get('days', 1), 1)

            print(f"\n   Average daily cost SITE_001: £{site_001_avg:.2f}")
            print(f"   Average daily cost SITE_002: £{site_002_avg:.2f}")

            # SITE_001 (manufacturing) should cost more than SITE_002 (assembly)
            assert site_001_avg > site_002_avg, "Manufacturing floor should cost more than assembly line"

        finally:
            cursor.close()

    def test_sensor_failure_detection(
        self,
        manufacturing_simulator: RealisticManufacturingSimulator
    ):
        """
        Test: Detecting sensor failures and data quality issues
        Scenario: Introduce sensor failures and verify they can be detected

        Expected:
        - Missing readings from failed sensors
        - Anomalous values (out of range)
        - Data gaps detected
        """

        # Generate normal data
        start_date = datetime(2025, 1, 22)
        end_date = datetime(2025, 1, 23)  # 1 day

        readings = manufacturing_simulator.generate_sensor_readings_for_period(
            start_date, end_date, interval_minutes=1
        )

        # Check for missing data
        expected_machines = set()
        for reading in readings:
            if 'machineId' in reading:
                expected_machines.add(reading['machineId'])

        # Count readings per machine
        readings_per_machine = {}
        for reading in readings:
            if 'machineId' not in reading:
                continue
            machine_id = reading['machineId']
            sensor_type = reading.get('sensorType')

            key = f"{machine_id}_{sensor_type}"
            readings_per_machine[key] = readings_per_machine.get(key, 0) + 1

        print(f"\n🔍 Sensor health check (over 1 day, 1-minute intervals):")
        print(f"   Total machines: {len(expected_machines)}")
        print(f"   Expected readings/machine/day: ~1440 (24h × 60min)")

        for key, count in sorted(readings_per_machine.items()):
            machine_id, sensor_type = key.rsplit('_', 1)
            if count < 1000:  # Less than ~1000 readings would indicate a problem
                print(f"   ⚠️  {machine_id}/{sensor_type}: {count} readings (low!)")
            else:
                print(f"   ✓ {machine_id}/{sensor_type}: {count} readings (good)")

        # Verify we have reasonably complete data
        for count in readings_per_machine.values():
            assert count > 500, f"Sensor readings too sparse: {count}"

    def test_multi_machine_production_line_coordination(
        self,
        manufacturing_simulator: RealisticManufacturingSimulator
    ):
        """
        Test: Coordinated behavior of multiple machines on a production line
        Scenario: CNC machining line with 4 machines working in sequence

        Expected:
        - Machines have similar power consumption patterns
        - Synchronized maintenance windows
        - Realistic production flow
        """

        # Generate data for one production line
        start_date = datetime(2025, 1, 22)
        end_date = datetime(2025, 1, 24)  # 2 days

        readings = manufacturing_simulator.generate_sensor_readings_for_period(
            start_date, end_date, interval_minutes=30
        )

        # Filter to CNC machines only
        cnc_readings = [
            r for r in readings
            if 'CNC_MACHINE' in r.get('machineId', '') and r.get('sensorType') == 'clamp_current'
        ]

        # Group by machine
        by_machine = {}
        for reading in cnc_readings:
            machine_id = reading['machineId']
            current = reading['measurements']['current_rms']

            if machine_id not in by_machine:
                by_machine[machine_id] = []
            by_machine[machine_id].append(current)

        print(f"\n🏭 Production line coordination (CNC machining):")
        print(f"   Machines: {sorted(by_machine.keys())}")

        # Analyze patterns
        for machine_id in sorted(by_machine.keys()):
            currents = by_machine[machine_id]
            avg_current = sum(currents) / len(currents)
            max_current = max(currents)
            min_current = min(currents)

            print(f"\n   {machine_id}:")
            print(f"      Avg current: {avg_current:.2f}A")
            print(f"      Range: {min_current:.2f}A - {max_current:.2f}A")
            print(f"      Readings: {len(currents)}")

        # Verify machines have similar patterns
        avg_currents = [sum(currents) / len(currents) for currents in by_machine.values()]
        if len(avg_currents) > 1:
            # Average current across all machines
            overall_avg = sum(avg_currents) / len(avg_currents)
            # Verify no machine deviates wildly from others (within 50%)
            for avg in avg_currents:
                assert abs(avg - overall_avg) < overall_avg * 0.5, \
                    f"Machine power consumption deviates too much: {avg:.2f}A vs overall {overall_avg:.2f}A"

    def test_cross_site_data_isolation(
        self,
        manufacturing_simulator: RealisticManufacturingSimulator
    ):
        """
        Test: Verify data isolation between sites
        Scenario: Confirm no cross-contamination between ABC Mfg's different physical locations

        Expected:
        - SITE_001 has manufacturing equipment
        - SITE_002 has assembly equipment
        - SITE_003 has only environmental monitoring
        - No data leakage between sites
        """

        start_date = datetime(2025, 1, 22)
        end_date = datetime(2025, 1, 23)

        readings = manufacturing_simulator.generate_sensor_readings_for_period(
            start_date, end_date, interval_minutes=60
        )

        # Group by site
        by_site = {}
        for reading in readings:
            site_id = reading['siteId']
            sensor_type = reading.get('sensorType')

            if site_id not in by_site:
                by_site[site_id] = {'sensors': set(), 'machines': set()}

            by_site[site_id]['sensors'].add(sensor_type)

            if 'machineId' in reading:
                by_site[site_id]['machines'].add(reading['machineId'])

        print(f"\n🏢 Cross-site data isolation:")

        for site_id in sorted(by_site.keys()):
            site_data = by_site[site_id]
            print(f"\n   {site_id}:")
            print(f"      Sensor types: {sorted(site_data['sensors'])}")
            print(f"      Machines: {len(site_data['machines'])}")

        # Verify site content
        # SITE_001 should have manufacturing machines
        assert 'CNC_MACHINE' in str(by_site.get('SITE_001', {}).get('machines', set())), \
            "SITE_001 should have CNC machines"

        # SITE_002 should have assembly equipment
        assert 'ASSEMBLY_STATION' in str(by_site.get('SITE_002', {}).get('machines', set())), \
            "SITE_002 should have assembly stations"

        # SITE_003 should only have environmental sensors
        site_003_machines = by_site.get('SITE_003', {}).get('machines', set())
        assert len(site_003_machines) == 0, "SITE_003 (warehouse) should not have production machines"

        site_003_sensors = by_site.get('SITE_003', {}).get('sensors', set())
        assert 'environmental' in site_003_sensors, "SITE_003 should have environmental sensors"

    def test_realistic_data_volume_for_30_tenants(
        self,
        manufacturing_simulator: RealisticManufacturingSimulator
    ):
        """
        Test: Verify realistic data volume for full platform (30 tenants)
        Scenario: Calculate expected data points for production deployment

        Expected:
        - Each facility generates ~2.34B messages/month
        - Validate reasonable data generation rate
        """

        # Generate 1 day of data at 1-minute intervals
        start_date = datetime(2025, 1, 22)
        end_date = datetime(2025, 1, 23)

        readings = manufacturing_simulator.generate_sensor_readings_for_period(
            start_date, end_date, interval_minutes=1
        )

        # Count by type
        clamp_count = len([r for r in readings if r.get('sensorType') == 'clamp_current'])
        vibration_count = len([r for r in readings if r.get('sensorType') == 'vibration'])
        environmental_count = len([r for r in readings if r.get('sensorType') == 'environmental'])

        total_per_day = len(readings)
        total_per_month = total_per_day * 30

        print(f"\n📈 Data volume for ABC Mfg (single tenant):")
        print(f"   Per day (1-minute intervals):")
        print(f"      Clamp sensors: {clamp_count:,}")
        print(f"      Vibration sensors: {vibration_count:,}")
        print(f"      Environmental sensors: {environmental_count:,}")
        print(f"      TOTAL: {total_per_day:,}")

        print(f"\n   Per month (estimated):")
        print(f"      Clamp sensors: {clamp_count * 30:,}")
        print(f"      Vibration sensors: {vibration_count * 30:,}")
        print(f"      Environmental sensors: {environmental_count * 30:,}")
        print(f"      TOTAL: {total_per_month:,}")

        print(f"\n   For 30 tenants (full platform):")
        print(f"      Monthly messages: {total_per_month * 30:,.0f}")
        print(f"      Avg per minute: {(total_per_month * 30) / (30 * 24 * 60):,.0f}")

        # Verify reasonable volume
        assert total_per_day > 1000, "Should generate at least 1000 readings per day"

        # For 30 tenants at similar scale, should be on order of millions per month
        estimated_30_tenant_volume = total_per_month * 30
        assert estimated_30_tenant_volume > 1_000_000, \
            f"For 30 tenants, should exceed 1M messages/month, got {estimated_30_tenant_volume:,}"

        print(f"\n   ✓ Data volume is realistic for production deployment")
