# Testing Improvements - Summary

## What Changed

You now have **realistic, production-like test infrastructure** instead of simplistic single-sensor tests.

### Before ❌
```
- Single sensor type per test
- Single machine (always machine_001)
- Unrealistic data (always ON or OFF, no variation)
- No production schedules or shift patterns
- No cost analysis
- No multi-site scenarios
- No sensor failure detection
```

### After ✅
```
- Multiple sensor types (power, vibration, environmental)
- 3 sites, 11 machines, 25+ sensors
- Realistic data with actual shift patterns, maintenance windows
- Complete production schedules (M-F, Sat, Sun patterns)
- Cost analysis across sites
- Cross-site data isolation verification
- Sensor failure and data quality detection
- Platform scalability validation (30-tenant load)
```

---

## New Files Created

### 1. **conftest_manufacturing_scenarios.py**
Complete manufacturing facility definitions:
- `ManufacturingFacility`, `ManufactoringSite`, `ProductionLine`, `Machine`, `Sensor` classes
- `RealisticManufacturingSimulator` for data generation
- Pytest fixtures for easy test usage
- Real factory layouts: 3 sites, 7 production lines, 11 machines

### 2. **test_realistic_manufacturing_scenarios.py**
7 comprehensive integration tests:
1. Multi-site data ingestion
2. Production schedule patterns
3. Multi-site cost analysis
4. Sensor failure detection
5. Production line coordination
6. Cross-site data isolation
7. Data volume validation (30-tenant platform)

### 3. **realistic_facility_simulator.py**
Command-line tool to stream realistic manufacturing data:
```bash
python tests/device-simulators/realistic_facility_simulator.py \
  --endpoint <iot-endpoint> \
  --cert <cert.pem> \
  --key <key.pem> \
  --ca <ca.pem> \
  --tenant-id abc_mfg \
  --duration 3600 \
  --interval 60
```

Simulates the complete facility with:
- Real MQTT topics and payload formats
- All 3 sites operating simultaneously
- All 25+ sensors generating data at intervals
- Realistic production patterns
- Actual data flow to IoT Core → Kinesis → Snowflake

### 4. **Updated conftest.py**
- Added imports for manufacturing scenario fixtures
- All new fixtures automatically available to existing tests
- Backward compatible with existing test suite

### 5. **Documentation Files**
- `REALISTIC_TESTING_GUIDE.md` - How to use the new tools
- `TESTING_IMPROVEMENTS_SUMMARY.md` - This file

---

## How to Use

### Option A: Run Python Tests (Unit/Integration)

```bash
# Run all realistic manufacturing tests
pytest tests/integration/test_realistic_manufacturing_scenarios.py -v

# Run specific test
pytest tests/integration/test_realistic_manufacturing_scenarios.py::TestRealisticMultiSiteScenarios::test_multi_site_cost_analysis -v

# Run with output
pytest tests/integration/test_realistic_manufacturing_scenarios.py -v -s
```

### Option B: Stream Real Data to IoT Core

```bash
# Quick test: 5 minutes
python tests/device-simulators/realistic_facility_simulator.py \
  --endpoint abc123.iot.eu-west-2.amazonaws.com \
  --cert docs/deployment/certificates/test_cert.pem \
  --key docs/deployment/certificates/test_key.pem \
  --ca AmazonRootCA1.pem \
  --client-id simulator_001 \
  --tenant-id abc_mfg \
  --duration 300 \
  --interval 60

# 1-hour realistic shift
python tests/device-simulators/realistic_facility_simulator.py \
  --endpoint abc123.iot.eu-west-2.amazonaws.com \
  --cert docs/deployment/certificates/test_cert.pem \
  --key docs/deployment/certificates/test_key.pem \
  --ca AmazonRootCA1.pem \
  --client-id simulator_001 \
  --tenant-id abc_mfg \
  --duration 3600 \
  --interval 60

# Full 8-hour shift with 5-minute readings
python tests/device-simulators/realistic_facility_simulator.py \
  --endpoint abc123.iot.eu-west-2.amazonaws.com \
  --cert docs/deployment/certificates/test_cert.pem \
  --key docs/deployment/certificates/test_key.pem \
  --ca AmazonRootCA1.pem \
  --client-id simulator_001 \
  --tenant-id abc_mfg \
  --duration 28800 \
  --interval 300
```

### Monitor Results in Snowflake

While data is streaming (or after it completes):

```sql
USE DATABASE smdh_tenant_abc_mfg;

-- Raw sensor data
SELECT COUNT(*) as readings, COUNT(DISTINCT sensor_id) as sensors
FROM raw.sensor_readings
WHERE TIMESTAMP >= CURRENT_TIMESTAMP() - INTERVAL '30 minutes';

-- By sensor type
SELECT PAYLOAD:sensorType, COUNT(*)
FROM raw.sensor_readings
WHERE TIMESTAMP >= CURRENT_TIMESTAMP() - INTERVAL '30 minutes'
GROUP BY PAYLOAD:sensorType;

-- By site
SELECT PAYLOAD:siteId, COUNT(*), COUNT(DISTINCT PAYLOAD:machineId)
FROM raw.sensor_readings
WHERE TIMESTAMP >= CURRENT_TIMESTAMP() - INTERVAL '30 minutes'
GROUP BY PAYLOAD:siteId;

-- Normalized power metrics
SELECT MACHINE_ID, AVG(REAL_POWER_KW), MAX(REAL_POWER_KW)
FROM normalized.power_metrics
WHERE TIMESTAMP >= CURRENT_TIMESTAMP() - INTERVAL '30 minutes'
GROUP BY MACHINE_ID;

-- Machine states and costs
SELECT MACHINE_ID, STATE, SUM(ENERGY_KWH), SUM(COST_GBP)
FROM mart.fact_machine_state
WHERE TIMESTAMP_UTC >= CURRENT_TIMESTAMP() - INTERVAL '30 minutes'
GROUP BY MACHINE_ID, STATE;
```

---

## Facility Structure

The tests/simulator use a realistic multi-site facility:

```
ABC Manufacturing Ltd
│
├─ SITE_001: Manufacturing Floor (Leeds)
│  ├─ LINE_001: CNC Machining (4 machines + sensors)
│  ├─ LINE_002: Precision Milling (3 machines + sensors)
│  └─ ZONE_FLOOR_001: Environmental monitoring
│
├─ SITE_002: Assembly Line (Manchester)
│  ├─ LINE_003: Manual Assembly (4 stations + sensors)
│  └─ ZONE_ASSEMBLY_001: Environmental monitoring
│
└─ SITE_003: Warehouse (Bristol)
   └─ ZONE_WAREHOUSE_001: Environmental monitoring
```

**Total:** 3 sites, 7 production lines, 11 machines, 25+ sensors

---

## Realistic Data Patterns

### Sensor Data
- **Power sensors (clamp):** Realistic current (0.05-16A), voltage (395-405V), power factor (0.83-0.97)
- **Vibration sensors:** Temp-aware (18-55°C), state-aware vibration (0.01-0.8 mm/s)
- **Environmental sensors:** Temperature, humidity, CO2, noise, light with realistic diurnal patterns

### Production Patterns
- **Monday-Friday:** 06:00-22:00 active, maintenance 00:00-06:00
- **Saturday:** 08:00-18:00 active (reduced shift)
- **Sunday:** Fully off (maintenance day)
- **Within shifts:** 75% working, 15% idle, 10% off

### Cost Patterns
- Peak rate (09:00-17:00): £0.28/kWh
- Off-peak rate (17:00-09:00): £0.15/kWh
- Manufacturing > Assembly > Warehouse cost
- Realistic daily costs: £20-40 per machine depending on state

---

## Test Coverage

| Test | Scenario | Data Size | Validates |
|------|----------|-----------|-----------|
| Multi-site ingestion | 3 days, 25+ sensors | ~50K readings | Data variety, site isolation |
| Production schedules | 1 week | ~10K readings | Shift patterns, maintenance |
| Cost analysis | 1 week | Multi-site | Peak/off-peak rates, site comparison |
| Sensor failures | 1 day | ~1440/sensor | Missing data, anomalies |
| Production coordination | 2 days | 4 CNC machines | Line synchronization |
| Data isolation | 1 day | All sites | No cross-contamination |
| Platform scale | 1 day | ~47K messages | 30-tenant load estimate |

---

## Key Improvements Over Previous Tests

### 1. **Realistic Hardware Simulation**
```
Old: Test with hardcoded "12.5A current"
New: Realistic 0.05-16A range based on machine state
```

### 2. **Complete Facility Simulation**
```
Old: Single machine MACHINE_001
New: 3 sites, 11 machines, all operating simultaneously
```

### 3. **Production Schedule Awareness**
```
Old: Always assume production is running
New: Respects business hours, maintenance windows, shift patterns
```

### 4. **Multi-Sensor Coverage**
```
Old: Only clamp (power) sensors
New: Power, vibration, environmental all generating data
```

### 5. **Cost Analysis**
```
Old: No cost calculations in tests
New: Peak/off-peak tariff rate application, cross-site analysis
```

### 6. **Data Quality Validation**
```
Old: Assume all data is perfect
New: Detect missing sensors, out-of-range values, data gaps
```

### 7. **Production Realism**
```
Old: Machines always ON
New: Realistic OFF/IDLE/WORKING states with proper timing
```

---

## Using in Development

### When Adding New Features

1. **Add test case to `test_realistic_manufacturing_scenarios.py`:**
   ```python
   def test_your_new_feature(self, manufacturing_simulator, multi_day_sensor_data):
       # Use real manufacturing data
       readings = multi_day_sensor_data

       # Your test logic...
       assert your_assertion
   ```

2. **Run tests to verify:**
   ```bash
   pytest tests/integration/test_realistic_manufacturing_scenarios.py::TestRealisticMultiSiteScenarios::test_your_new_feature -v
   ```

### When Debugging Data Flow

1. **Stream realistic data:**
   ```bash
   python tests/device-simulators/realistic_facility_simulator.py \
     --endpoint ... --duration 600 --interval 60
   ```

2. **Monitor in Snowflake:**
   ```sql
   -- Watch data flow through layers in real-time
   SELECT * FROM raw.sensor_readings WHERE TIMESTAMP >= NOW() - '5 min';
   SELECT * FROM normalized.power_metrics WHERE TIMESTAMP >= NOW() - '5 min';
   SELECT * FROM mart.fact_machine_state WHERE TIMESTAMP_UTC >= NOW() - '5 min';
   ```

### When Testing at Scale

1. **Estimate for 30 tenants:**
   ```python
   # From test output:
   # Single tenant: ~47K messages/day
   # 30 tenants: ~1.4M messages/day
   # Monthly: ~42M messages
   ```

2. **Verify cost calculations:**
   ```python
   # Manufacturing floor (24/7): ~£30-40/day
   # Assembly line (shift): ~£15-20/day
   # Warehouse (env only): ~£2-5/day
   # Scale to platform: realistic month budget
   ```

---

## Next Steps

1. **Try the simulator:**
   ```bash
   python tests/device-simulators/realistic_facility_simulator.py --help
   ```

2. **Run the tests:**
   ```bash
   pytest tests/integration/test_realistic_manufacturing_scenarios.py -v
   ```

3. **Monitor real data flow:**
   - Stream data for 5 minutes
   - Watch tables populate in real-time
   - Trace data through RAW → NORMALIZED → MART

4. **Extend scenarios:**
   - Add more sensor types
   - Adjust production schedules
   - Create industry-specific patterns (food, automotive, etc.)

---

## Documentation

- **How to use tests:** See [REALISTIC_TESTING_GUIDE.md](REALISTIC_TESTING_GUIDE.md)
- **Data flow explanation:** See [TENANT_REGISTRATION_AND_DATA_FLOW_GUIDE.md](TENANT_REGISTRATION_AND_DATA_FLOW_GUIDE.md)
- **Quick visual reference:** See [QUICK_REFERENCE_DATA_FLOW.md](QUICK_REFERENCE_DATA_FLOW.md)

