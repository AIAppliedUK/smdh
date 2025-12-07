# Testing Quick Start

Get realistic manufacturing tests running in 2 minutes.

## 1. Run Python Tests (Fastest)

```bash
# Install dependencies (if not already done)
pip install pytest

# Run realistic manufacturing tests
pytest tests/integration/test_realistic_manufacturing_scenarios.py -v

# Run one specific test
pytest tests/integration/test_realistic_manufacturing_scenarios.py::TestRealisticMultiSiteScenarios::test_multi_site_cost_analysis -v -s
```

**What you'll see:**
```
test_ingestion_of_multi_site_sensor_data PASSED                    [14%]
📊 Multi-site data summary:
   Total readings: 42,341
   Clamp (power) sensors: 18,234
   Vibration sensors: 18,234
   Environmental sensors: 5,873
   Unique sites: 3 -> ['SITE_001', 'SITE_002', 'SITE_003']
   Unique machines: 11

test_realistic_production_schedule_patterns PASSED                  [28%]
📅 Production patterns by day of week:
   Monday: 1234 readings, avg power: 8.45A, max: 15.32A
   Tuesday: 1234 readings, avg power: 8.42A, max: 15.28A
   ...
   Sunday: 234 readings, avg power: 2.15A, max: 5.43A
```

---

## 2. Stream Real Data (See Live Flow)

### Setup (One Time)

Get your IoT endpoint and certificates:
```bash
# Find your endpoint
aws iot describe-endpoint --region eu-west-2 | grep endpointAddress

# List your certificates
aws iot list-certificates --region eu-west-2

# Download if needed
aws iot describe-certificate --certificate-id <ID> --region eu-west-2
```

### Run Simulator

```bash
# Quick 5-minute test
python tests/device-simulators/realistic_facility_simulator.py \
  --endpoint xxxxxxxx-ats.iot.eu-west-2.amazonaws.com \
  --cert path/to/cert.pem \
  --key path/to/key.pem \
  --ca path/to/AmazonRootCA1.pem \
  --client-id simulator_001 \
  --tenant-id abc_mfg \
  --duration 300 \
  --interval 60
```

**What you'll see:**
```
2025-01-24 14:35:22 - INFO - ✅ Connected to AWS IoT Core as simulator_001
2025-01-24 14:35:22 - INFO - 🚀 Starting facility simulation for abc_mfg
2025-01-24 14:35:22 - INFO -    Duration: 300s (5.0 minutes)
2025-01-24 14:35:22 - INFO -    Interval: 60s
2025-01-24 14:35:23 - INFO - 📊 Progress: 20.0% (46 messages)
2025-01-24 14:35:45 - INFO - ✅ Simulation complete! Sent 230 messages
```

### Monitor in Snowflake (While simulator runs)

In a **separate terminal**:

```sql
-- Connect to Snowflake
USE DATABASE smdh_tenant_abc_mfg;

-- Watch raw data arrive (updates every 5 seconds)
SELECT
  COUNT(*) as total,
  COUNT(DISTINCT PAYLOAD:siteId) as sites,
  COUNT(DISTINCT PAYLOAD:machineId) as machines,
  MAX(TIMESTAMP) as latest
FROM raw.sensor_readings
WHERE TIMESTAMP >= CURRENT_TIMESTAMP() - INTERVAL '15 minutes';

-- Watch power metrics calculate (after ~1 minute)
SELECT
  MACHINE_ID,
  COUNT(*) as readings,
  AVG(REAL_POWER_KW) as avg_power,
  MAX(REAL_POWER_KW) as peak_power
FROM normalized.power_metrics
WHERE TIMESTAMP >= CURRENT_TIMESTAMP() - INTERVAL '15 minutes'
GROUP BY MACHINE_ID;

-- Watch machine states get classified (after ~2 minutes)
SELECT
  MACHINE_ID,
  STATE,
  COUNT(*) as count,
  SUM(ENERGY_KWH) as total_energy,
  SUM(COST_GBP) as total_cost
FROM mart.fact_machine_state
WHERE TIMESTAMP_UTC >= CURRENT_TIMESTAMP() - INTERVAL '15 minutes'
GROUP BY MACHINE_ID, STATE;
```

---

## 3. Understand Your Data

### What the Simulator Sends

From **11 machines** across **3 sites**:

```
SITE_001 (Manufacturing Floor - Leeds)
├─ CNC_MACHINE_001
│  ├─ osm_pulse_001     (Current/Power sensor) ──────┐
│  └─ osm_sentinel_001  (Vibration sensor)    ──────┤
├─ CNC_MACHINE_002                                  │
│  ├─ osm_pulse_002                            │
│  └─ osm_sentinel_002                         │
├─ CNC_MACHINE_003                             │
├─ CNC_MACHINE_004                             │
├─ MILL_MACHINE_001                            │
├─ MILL_MACHINE_002                            │
├─ MILL_MACHINE_003                            │
└─ ZONE_FLOOR_001                              │
   └─ Environmental sensor                     ─┐

SITE_002 (Assembly Line - Manchester)           │ Total: 25+ sensors
├─ ASSEMBLY_STATION_001                         │
├─ ASSEMBLY_STATION_002                         │
├─ ASSEMBLY_STATION_003                         │ Generating data
├─ ASSEMBLY_STATION_004                         │ every 60 seconds
└─ ZONE_ASSEMBLY_001                            │
   └─ Environmental sensor                      │

SITE_003 (Warehouse - Bristol)                   │
└─ ZONE_WAREHOUSE_001                           │
   └─ Environmental sensor                      ─┘
```

### Sample Message Format

```json
{
  "deviceId": "osm_pulse_001",
  "machineId": "CNC_MACHINE_001",
  "siteId": "SITE_001",
  "timestamp": "2025-01-24T14:35:22.123Z",
  "sensorType": "clamp_current",
  "measurements": {
    "current_phase_a": 14.32,
    "current_phase_b": 14.18,
    "current_phase_c": 14.56,
    "current_rms": 14.35,
    "voltage_nominal": 400.2,
    "power_factor": 0.89,
    "frequency": 50.0
  },
  "metadata": {
    "firmwareVersion": "1.2.3",
    "signalQuality": 92,
    "batteryLevel": 87
  }
}
```

### How Much Data?

Per day (1-minute intervals):
- **Single facility:** ~47,000 readings
- **30 tenants:** ~1.4 million readings/day
- **Monthly:** ~42 million readings total
- **Cost:** ~£75 per tenant/month

---

## 4. Different Test Scenarios

### Scenario 1: Normal Production Day
```bash
# Monday morning 06:00-18:00 (12 hours)
python tests/device-simulators/realistic_facility_simulator.py \
  ... \
  --duration 43200 \
  --interval 60

# Expected: High power consumption, lots of vibration, moderate costs
```

### Scenario 2: Maintenance Window
```bash
# Sunday 00:00-06:00 (6 hours)
python tests/device-simulators/realistic_facility_simulator.py \
  ... \
  --duration 21600 \
  --interval 300

# Expected: All machines OFF, minimal power, no costs
```

### Scenario 3: Multi-Site Shift Change
```bash
# Friday afternoon + Saturday (24 hours)
python tests/device-simulators/realistic_facility_simulator.py \
  ... \
  --duration 86400 \
  --interval 300

# Expected: Different power patterns by site and time
```

---

## 5. Verify It Works

### Quick Check (3 steps)

```bash
# 1. Run simulator for 5 minutes
python tests/device-simulators/realistic_facility_simulator.py \
  --endpoint <endpoint> --cert <cert> --key <key> --ca <ca> \
  --client-id test_001 --tenant-id abc_mfg \
  --duration 300 --interval 60

# 2. Wait 30 seconds, then run this in Snowflake
USE DATABASE smdh_tenant_abc_mfg;
SELECT COUNT(*) as raw_readings FROM raw.sensor_readings
  WHERE TIMESTAMP >= CURRENT_TIMESTAMP() - INTERVAL '5 minutes';

# Expected output: ~230 (23 sensors × 5 mins ÷ 60 sec interval × some overhead)

# 3. Wait 2 minutes total, then check power metrics
SELECT COUNT(*) as power_metrics FROM normalized.power_metrics
  WHERE TIMESTAMP >= CURRENT_TIMESTAMP() - INTERVAL '5 minutes';

# Expected output: ~40-50 (only machine sensors, not environmental)
```

### Troubleshooting

| Issue | Check |
|-------|-------|
| **No data in Snowflake** | Is simulator showing "✅ Connected"? Check IoT rule is firing. |
| **Delayed data (>5 min)** | Check Kinesis and Snowflake warehouse size (should be MEDIUM+). |
| **Simulator won't connect** | Verify endpoint is correct and certificates are valid. |
| **Wrong tenant data** | Verify `--tenant-id abc_mfg` matches your database. |

---

## 6. Run Full Test Suite

```bash
# All tests (includes realistic + basic)
pytest tests/integration/ -v

# Only realistic manufacturing tests
pytest tests/integration/test_realistic_manufacturing_scenarios.py -v

# Show full output
pytest tests/integration/test_realistic_manufacturing_scenarios.py -v -s

# Run in parallel (faster)
pytest tests/integration/test_realistic_manufacturing_scenarios.py -v -n auto
```

---

## 7. What You Should See

### From Tests
```
✅ Readings from 3 sites: SITE_001, SITE_002, SITE_003
✅ Data from 11 machines: CNC_MACHINE_001, MILL_MACHINE_001, ASSEMBLY_STATION_001, etc.
✅ Multiple sensor types: clamp_current, vibration, environmental
✅ 3 days of data: 42,341 readings
✅ Cost analysis: Site 1 (£30-40), Site 2 (£15-20), Site 3 (£2-5)
✅ Production patterns: Active Mon-Fri 06:00-22:00, Off Sunday
✅ Machine coordination: Similar power patterns on same line
✅ Data isolation: No cross-site contamination
```

### From Simulator
```
✅ Connected to AWS IoT Core as facility_simulator_001
✅ Starting facility simulation for abc_mfg
✅ Generating data from 11 machines, 25+ sensors
✅ Progress: 20%, 50%, 100%
✅ Total: 230 messages sent (over 5 minute period)
```

### From Snowflake
```
Raw: 230 readings from 25 sensors, across 3 sites
Normalized: 46 power metrics calculated from raw readings
MART: 46 machine state classifications + costs
```

---

## Next Steps

1. **Run tests** (2 min):
   ```bash
   pytest tests/integration/test_realistic_manufacturing_scenarios.py -v
   ```

2. **Stream data** (5 min):
   ```bash
   python tests/device-simulators/realistic_facility_simulator.py ...
   ```

3. **Monitor in Snowflake** (real-time):
   ```sql
   SELECT * FROM raw.sensor_readings WHERE TIMESTAMP >= NOW() - '1 hour';
   ```

4. **Read full guides**:
   - [REALISTIC_TESTING_GUIDE.md](REALISTIC_TESTING_GUIDE.md) - Complete guide
   - [TESTING_IMPROVEMENTS_SUMMARY.md](TESTING_IMPROVEMENTS_SUMMARY.md) - What changed

---

## Common Commands

```bash
# Quick test
pytest tests/integration/test_realistic_manufacturing_scenarios.py::TestRealisticMultiSiteScenarios::test_multi_site_cost_analysis -v -s

# Stream for 10 minutes
python tests/device-simulators/realistic_facility_simulator.py \
  --endpoint <endpoint> --cert <cert> --key <key> --ca <ca> \
  --client-id sim_001 --tenant-id abc_mfg --duration 600 --interval 60

# Watch data in Snowflake
SELECT COUNT(*), MAX(TIMESTAMP) FROM raw.sensor_readings
WHERE TIMESTAMP >= CURRENT_TIMESTAMP() - INTERVAL '1 hour';

# Check cost calculations
SELECT MACHINE_ID, STATE, SUM(COST_GBP) FROM mart.fact_machine_state
WHERE TIMESTAMP_UTC >= CURRENT_TIMESTAMP() - INTERVAL '1 day'
GROUP BY MACHINE_ID, STATE;
```

