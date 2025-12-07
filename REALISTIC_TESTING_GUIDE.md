# Realistic Manufacturing Test Guide

This guide explains how to use the new realistic testing framework that simulates actual manufacturing environments with multiple sites, equipment types, and sensor types.

## Overview of New Test Infrastructure

### What Changed

**Before:** Tests used single sensor types, single machines, simplistic data patterns
```
❌ Old: Test with one clamp sensor at a time
❌ Old: Always "ON" or "OFF" - no intermediate states
❌ Old: No realistic production schedules
```

**After:** Tests simulate complete manufacturing facilities
```
✅ New: 3 sites, 11 machines, 25+ sensors generating realistic data
✅ New: Realistic shift patterns, maintenance windows, production schedules
✅ New: Multiple sensor types (power, vibration, environmental)
✅ New: Data quality variations, sensor failures, anomalies
```

---

## New Test Components

### 1. **Manufacturing Scenario Fixtures** (`conftest_manufacturing_scenarios.py`)

Provides realistic facility definitions:

```python
# Automatically creates:
realistic_facility()           # Complete ABC Mfg with 3 sites, 11 machines
manufacturing_simulator()     # Data generator with realistic patterns
multi_day_sensor_data()       # 3 days of continuous realistic readings
realistic_site_config()       # Configuration for all sites and equipment
```

### 2. **Realistic Scenario Tests** (`test_realistic_manufacturing_scenarios.py`)

Tests that validate complete manufacturing scenarios:

| Test | What It Does | Data Scenario |
|------|-------------|---|
| `test_ingestion_of_multi_site_sensor_data` | Verify all site data ingests correctly | 3 days, 3 sites, 25+ sensors |
| `test_realistic_production_schedule_patterns` | Validate shift patterns | 1 week data, multiple shift patterns |
| `test_multi_site_cost_analysis` | Calculate costs across sites | Daily cost breakdown by site |
| `test_sensor_failure_detection` | Detect missing/bad data | 1 day, identify sensor gaps |
| `test_multi_machine_production_line_coordination` | Verify line operates together | 2 days, 4 CNC machines synchronized |
| `test_cross_site_data_isolation` | No cross-contamination | Verify data stays isolated by site |
| `test_realistic_data_volume_for_30_tenants` | Platform capacity check | Scale estimate for production |

### 3. **Realistic Facility Simulator** (`realistic_facility_simulator.py`)

Command-line tool to stream realistic data to IoT Core:

```bash
# Simulates complete facility sending MQTT data to AWS IoT Core
# Generates the exact data flow you'd see in production
```

---

## Running the Tests

### Option 1: Run Realistic Integration Tests

```bash
# Run all realistic manufacturing scenario tests
pytest tests/integration/test_realistic_manufacturing_scenarios.py -v

# Run a specific test
pytest tests/integration/test_realistic_manufacturing_scenarios.py::TestRealisticMultiSiteScenarios::test_multi_site_cost_analysis -v

# Run with detailed output
pytest tests/integration/test_realistic_manufacturing_scenarios.py -v -s

# Run only fast tests (skip slow ones)
pytest tests/integration/test_realistic_manufacturing_scenarios.py -v -m "not slow"
```

### Option 2: Stream Real Data to IoT Core

Simulate the entire manufacturing facility streaming data to AWS IoT Core:

```bash
# Make the simulator executable
chmod +x tests/device-simulators/realistic_facility_simulator.py

# Simulate for 1 hour (3600 seconds) with 1-minute intervals (360 messages)
python tests/device-simulators/realistic_facility_simulator.py \
  --endpoint abc123.iot.eu-west-2.amazonaws.com \
  --cert docs/deployment/certificates/test_cert.pem \
  --key docs/deployment/certificates/test_key.pem \
  --ca AmazonRootCA1.pem \
  --client-id facility_simulator_001 \
  --tenant-id abc_mfg \
  --duration 3600 \
  --interval 60

# Simulate a single shift (8 hours) with 5-minute readings (96 messages)
python tests/device-simulators/realistic_facility_simulator.py \
  --endpoint abc123.iot.eu-west-2.amazonaws.com \
  --cert docs/deployment/certificates/test_cert.pem \
  --key docs/deployment/certificates/test_key.pem \
  --ca AmazonRootCA1.pem \
  --client-id facility_simulator_001 \
  --tenant-id abc_mfg \
  --duration 28800 \
  --interval 300

# Quick test: 5 minutes with 1-minute intervals (5 messages from all sensors)
python tests/device-simulators/realistic_facility_simulator.py \
  --endpoint abc123.iot.eu-west-2.amazonaws.com \
  --cert docs/deployment/certificates/test_cert.pem \
  --key docs/deployment/certificates/test_key.pem \
  --ca AmazonRootCA1.pem \
  --client-id facility_simulator_001 \
  --tenant-id abc_mfg \
  --duration 300 \
  --interval 60
```

---

## Realistic Data Explanation

### Facility Structure

The simulator creates a realistic manufacturing environment:

```
ABC Manufacturing Ltd (abc_mfg)
│
├─ SITE_001: Manufacturing Floor (Leeds, UK)
│  ├─ LINE_001: CNC Machining (4 machines)
│  │  ├─ CNC_MACHINE_001 [Clamp Sensor + Vibration Sensor]
│  │  ├─ CNC_MACHINE_002 [Clamp Sensor + Vibration Sensor]
│  │  ├─ CNC_MACHINE_003 [Clamp Sensor + Vibration Sensor]
│  │  └─ CNC_MACHINE_004 [Clamp Sensor + Vibration Sensor]
│  │
│  ├─ LINE_002: Precision Milling (3 machines)
│  │  ├─ MILL_MACHINE_001 [Clamp Sensor + Vibration Sensor]
│  │  ├─ MILL_MACHINE_002 [Clamp Sensor + Vibration Sensor]
│  │  └─ MILL_MACHINE_003 [Clamp Sensor + Vibration Sensor]
│  │
│  └─ ZONE_FLOOR_001: Environmental Monitoring
│     └─ Environmental Sensor [Temp, Humidity, CO2, Noise, Light]
│
├─ SITE_002: Assembly Line (Manchester, UK)
│  ├─ LINE_003: Manual Assembly (4 stations)
│  │  ├─ ASSEMBLY_STATION_001 [Clamp Sensor]
│  │  ├─ ASSEMBLY_STATION_002 [Clamp Sensor]
│  │  ├─ ASSEMBLY_STATION_003 [Clamp Sensor]
│  │  └─ ASSEMBLY_STATION_004 [Clamp Sensor]
│  │
│  └─ ZONE_ASSEMBLY_001: Environmental Monitoring
│     └─ Environmental Sensor
│
└─ SITE_003: Warehouse (Bristol, UK)
   └─ ZONE_WAREHOUSE_001: Climate Control
      └─ Environmental Sensor [Monitoring only, no production equipment]
```

### Realistic Production Patterns

The simulator generates realistic operational patterns:

```
Monday-Friday (Business Days):
  00:00-06:00: Maintenance (machines OFF)
  06:00-14:00: Morning shift (machines WORKING)
  14:00-22:00: Afternoon shift (machines WORKING)
  22:00-00:00: Night shift (low activity)

Saturday:
  00:00-08:00: Off (machines OFF)
  08:00-18:00: Reduced shift (machines WORKING)
  18:00-00:00: Off (machines OFF)

Sunday:
  All day OFF (maintenance day)
```

**Within each shift:**
- 75% of time: Machines WORKING (full power)
- 15% of time: Machines IDLE (warmup/cooldown)
- 10% of time: Machines OFF (between jobs)

### Realistic Sensor Data

#### Power Sensors (Clamp)
```
Machine State  | Current (Amps) | Voltage (V) | Power Factor
OFF            | 0.05-0.15      | 395-405     | 0.90
IDLE           | 2.0-3.5        | 395-405     | 0.90
WORKING        | 12.0-16.0      | 395-405     | 0.83-0.97
```

**Calculated Power:** P = √3 × V × I × PF / 1000
- OFF: ~0.03-0.10 kW
- IDLE: ~1.2-2.0 kW
- WORKING: ~7-10 kW

#### Vibration Sensors
```
Machine State  | Vibration (mm/s) | Temperature (°C)
OFF            | 0.01-0.05        | 18-22 (ambient)
IDLE           | 0.1-0.3          | 22-30
WORKING        | 0.3-0.8          | 35-55
```

#### Environmental Sensors
```
Time of Day    | Temperature | Humidity | CO2 (ppm)
06:00-22:00    | 20-25°C     | 45-65%   | 450-650 (higher during production)
22:00-06:00    | 15-20°C     | 50-70%   | 350-450 (baseline)
```

---

## Example: Streaming Real Data and Checking Results

### Step 1: Start Facility Simulator

```bash
python tests/device-simulators/realistic_facility_simulator.py \
  --endpoint abc123.iot.eu-west-2.amazonaws.com \
  --cert docs/deployment/certificates/test_cert.pem \
  --key docs/deployment/certificates/test_key.pem \
  --ca AmazonRootCA1.pem \
  --client-id simulator_001 \
  --tenant-id abc_mfg \
  --duration 600 \
  --interval 60
```

**Output:**
```
2025-01-24 14:35:22 - INFO - ✅ Connected to AWS IoT Core as simulator_001
2025-01-24 14:35:22 - INFO - 🚀 Starting facility simulation for abc_mfg
2025-01-24 14:35:22 - INFO -    Duration: 600s (10.0 minutes)
2025-01-24 14:35:22 - INFO -    Interval: 60s
2025-01-24 14:35:23 - INFO - 📊 Progress: 3.3% (46 messages)
2025-01-24 14:36:23 - INFO - 📊 Progress: 6.7% (92 messages)
...
2025-01-24 14:44:23 - INFO - ✅ Simulation complete! Sent 460 messages
```

### Step 2: Monitor Snowflake Tables (In Another Terminal)

```sql
-- Connect to ABC Mfg tenant database
USE DATABASE smdh_tenant_abc_mfg;

-- 1. Check raw sensor readings (should appear within 30 seconds)
SELECT COUNT(*) as total_readings, COUNT(DISTINCT sensor_id) as unique_sensors
FROM raw.sensor_readings
WHERE TIMESTAMP >= CURRENT_TIMESTAMP() - INTERVAL '15 minutes'
GROUP BY DATE_TRUNC('minute', TIMESTAMP)
ORDER BY 1 DESC
LIMIT 10;

-- 2. Check by sensor type
SELECT
  PAYLOAD:sensorType as sensor_type,
  COUNT(*) as reading_count,
  COUNT(DISTINCT PAYLOAD:machineId) as machines,
  COUNT(DISTINCT PAYLOAD:siteId) as sites
FROM raw.sensor_readings
WHERE TIMESTAMP >= CURRENT_TIMESTAMP() - INTERVAL '15 minutes'
GROUP BY PAYLOAD:sensorType;

-- 3. Check data from each site
SELECT
  PAYLOAD:siteId as site_id,
  PAYLOAD:sensorType as sensor_type,
  COUNT(*) as readings,
  MIN(TIMESTAMP) as first_reading,
  MAX(TIMESTAMP) as last_reading
FROM raw.sensor_readings
WHERE TIMESTAMP >= CURRENT_TIMESTAMP() - INTERVAL '15 minutes'
GROUP BY PAYLOAD:siteId, PAYLOAD:sensorType
ORDER BY PAYLOAD:siteId, PAYLOAD:sensorType;

-- 4. Check normalized power metrics (after ~1 minute)
SELECT
  MACHINE_ID,
  TIMESTAMP,
  REAL_POWER_KW,
  APPARENT_POWER_KVA,
  ENERGY_KWH
FROM normalized.power_metrics
WHERE TIMESTAMP >= CURRENT_TIMESTAMP() - INTERVAL '15 minutes'
ORDER BY TIMESTAMP DESC
LIMIT 20;

-- 5. Check machine states (after ~2 minutes)
SELECT
  MACHINE_ID,
  TIMESTAMP_UTC,
  STATE,
  POWER_KW,
  STATE_CONFIDENCE,
  COST_GBP
FROM mart.fact_machine_state
WHERE TIMESTAMP_UTC >= CURRENT_TIMESTAMP() - INTERVAL '15 minutes'
ORDER BY TIMESTAMP_UTC DESC
LIMIT 20;

-- 6. Summary dashboard
SELECT
  'SITE_001' as site,
  COUNT(*) as total_readings,
  COUNT(DISTINCT PAYLOAD:machineId) as active_machines,
  AVG(PAYLOAD:measurements.current_rms) as avg_current,
  MAX(PAYLOAD:measurements.current_rms) as peak_current
FROM raw.sensor_readings
WHERE PAYLOAD:siteId = 'SITE_001'
  AND PAYLOAD:sensorType = 'clamp_current'
  AND TIMESTAMP >= CURRENT_TIMESTAMP() - INTERVAL '15 minutes'
UNION ALL
SELECT
  'SITE_002' as site,
  COUNT(*) as total_readings,
  COUNT(DISTINCT PAYLOAD:machineId) as active_machines,
  AVG(PAYLOAD:measurements.current_rms) as avg_current,
  MAX(PAYLOAD:measurements.current_rms) as peak_current
FROM raw.sensor_readings
WHERE PAYLOAD:siteId = 'SITE_002'
  AND PAYLOAD:sensorType = 'clamp_current'
  AND TIMESTAMP >= CURRENT_TIMESTAMP() - INTERVAL '15 minutes'
UNION ALL
SELECT
  'SITE_003' as site,
  COUNT(*) as total_readings,
  COUNT(DISTINCT PAYLOAD:zoneId) as active_zones,
  NULL as avg_current,
  NULL as peak_current
FROM raw.sensor_readings
WHERE PAYLOAD:siteId = 'SITE_003'
  AND TIMESTAMP >= CURRENT_TIMESTAMP() - INTERVAL '15 minutes';
```

---

## Test Scenarios Covered

### Multi-Site Ingestion
✅ Verifies data from 3 sites ingests correctly
✅ Different equipment types per site
✅ No cross-site contamination

### Production Schedule Patterns
✅ Shift patterns (morning, afternoon, night)
✅ Maintenance windows (Sunday mornings)
✅ Business hours vs. off-hours behavior
✅ Weekend scheduling (reduced Saturday, closed Sunday)

### Cost Analysis
✅ Peak vs. off-peak tariff rates (£0.28 vs £0.15/kWh)
✅ Cost per site (manufacturing > assembly > warehouse)
✅ Cost per shift
✅ Cost per machine state (working > idle > off)

### Sensor Failure Detection
✅ Detect missing sensor readings
✅ Identify out-of-range values
✅ Spot data gaps in time series
✅ Distinguish offline from degraded sensors

### Multi-Machine Coordination
✅ Production line synchronization
✅ Similar power consumption patterns within lines
✅ State transitions across line
✅ Predictive maintenance signals from vibration

### Data Volume Validation
✅ For single tenant: ~47K messages/day
✅ For 30 tenants: ~1.4M messages/day
✅ Matches production estimate of 2.34B/month

---

## Common Scenarios to Test

### Scenario 1: Normal Production Day
```bash
# Simulate Monday 6am-6pm (morning + afternoon shifts)
# Duration: 43200 seconds (12 hours)
python realistic_facility_simulator.py ... --duration 43200 --interval 60
```

Then check:
- CNC machines running at high power (12-16A)
- Vibration sensors showing activity
- Environmental conditions stable (temp ~22°C)
- Cost accrual: ~£30-40 for the day

### Scenario 2: Maintenance Window (Sunday)
```bash
# Simulate Sunday morning (maintenance)
# Duration: 21600 seconds (6 hours)
python realistic_facility_simulator.py ... --duration 21600 --interval 300
```

Then check:
- All machines OFF (current ~0.1A)
- No vibration (< 0.05 mm/s)
- No costs accrued
- Only environmental sensors active

### Scenario 3: Mixed Shift Work (Multi-Day)
```bash
# Simulate Friday afternoon + Saturday (shift change)
# Duration: 86400 seconds (24 hours)
python realistic_facility_simulator.py ... --duration 86400 --interval 300
```

Then check:
- Friday 14-22: High activity (afternoon shift)
- Friday 22-06: Low activity (night shift)
- Saturday 08-18: Reduced shift (half staff)
- Saturday 18-00: Off
- Cost differences: Friday > Saturday

---

## Troubleshooting

### Problem: No data appearing in Snowflake

**Check:**
1. Is simulator successfully connected?
   - Look for "✅ Connected to AWS IoT Core"

2. Are messages being published?
   - Look for "📊 Progress: X% (Y messages)"

3. Is IoT rule firing?
   - AWS Console → IoT Core → Rules → route_to_kinesis → View metric

4. Is Kinesis receiving messages?
   ```bash
   aws kinesis describe-stream \
     --stream-name smdh-sensor-data-stream \
     --region eu-west-2
   ```

5. Is Snowflake connector running?
   ```sql
   SHOW INTEGRATIONS;
   SELECT * FROM information_schema.pipes;
   ```

### Problem: Data appearing but with delay > 5 minutes

**Check:**
1. **Kinesis backed up?**
   - Check shard metrics in CloudWatch
   - May need to increase shard count

2. **Snowflake slow?**
   - Check warehouse size (should be MEDIUM or larger)
   - Run: `SHOW WAREHOUSES;`

3. **Network latency?**
   - Simulator shows "❌ Failed to publish" if connectivity issues

### Problem: Cost calculations seem wrong

**Check:**
1. Are timestamps in UTC? (All should be)
   - Verify: `SELECT TIMESTAMP FROM raw.sensor_readings LIMIT 1;`

2. Are tariff rates applied correctly?
   - Peak (09:00-17:00): £0.28/kWh
   - Off-peak (17:00-09:00): £0.15/kWh
   - Verify: `SELECT DISTINCT TARIFF_BAND, RATE_PER_KWH FROM mart.fact_machine_state;`

3. Is power calculation correct?
   - Formula: P = √3 × V × I × PF / 1000
   - Verify: `SELECT REAL_POWER_KW, (1.732 * 400 * AVG_CURRENT_AMPS * 0.9 / 1000) as calculated FROM normalized.power_metrics LIMIT 1;`

---

## Production Use

When you onboard a real customer, the same infrastructure handles their data:

```
Real Customer Hardware
(machines with IoT sensors)
         ↓
   AWS IoT Core  ← Same as simulator
         ↓
   Kinesis Stream ← Same partitioning
         ↓
   Snowflake  ← Isolated database per tenant
```

The simulator sends data in **exactly the same format** as real devices, so testing with the simulator is a true production simulation.

---

## Next Steps

1. **Run the simulator** to understand data flow
2. **Monitor Snowflake tables** to see data transformations
3. **Check cost calculations** to understand pricing
4. **Modify the simulator** if you need different scenarios
5. **Use the test patterns** for regression testing when updating code

For detailed implementation, see: [TENANT_REGISTRATION_AND_DATA_FLOW_GUIDE.md](TENANT_REGISTRATION_AND_DATA_FLOW_GUIDE.md)
