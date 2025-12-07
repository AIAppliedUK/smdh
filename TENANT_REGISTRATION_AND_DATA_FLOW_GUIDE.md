# Tenant Registration and Data Flow Guide

## Quick Overview

When a new tenant registers and starts streaming sensor data, here's what happens:

```
Manufacturing Facility (Tenant)
    ↓ (1-3 sensors per machine)
Sensors → AWS IoT Core → Kinesis → Snowflake → Dashboards
```

This document walks through **exactly what happens** at each step with real data.

---

## Part 1: Tenant Registration (One-Time Setup)

When you onboard a new customer (e.g., "ABC Manufacturing Ltd"), you run one command:

```bash
./onboard_tenant.sh \
  --tenant-id abc_mfg \
  --tenant-name "ABC Manufacturing Ltd" \
  --num-sites 3 \
  --snowflake-account xy12345 \
  --snowflake-user admin_user
```

### What Gets Created (In Snowflake)

The script creates **completely isolated** databases for each tenant:

```
Snowflake Account (Shared for all tenants)
├── smdh_infrastructure (Shared infrastructure)
│   └── tenant_configs.tenants (Registry of all tenants)
│
├── smdh_tenant_abc_mfg (ABC Manufacturing's dedicated database)
│   ├── RAW schema
│   │   ├── sensor_readings (ALL raw sensor data)
│   │   ├── gateway_connections (LoRaWAN gateway status)
│   │   └── device_status (Battery, signal strength, etc.)
│   │
│   ├── NORMALIZED schema
│   │   ├── power_metrics (Calculated power from raw sensors)
│   │   └── sensor_metrics (Validated, cleaned-up data)
│   │
│   ├── AGGREGATED schema
│   │   ├── hourly_summaries
│   │   ├── daily_summaries
│   │   └── monthly_summaries
│   │
│   └── ANALYTICS schema
│       ├── v_system_summary (Dashboard views)
│       ├── fact_machine_state (Machine status over time)
│       └── fact_energy_cost_daily (Cost calculations)
│
├── smdh_tenant_xyz_corp (XYZ Corporation's isolated database)
│   └── (Same structure, completely separate data)
```

### Key Point: Data Isolation

- **ABC Manufacturing data stays only in `smdh_tenant_abc_mfg`** - no cross-tenant leakage
- Each tenant gets their own database with the same schema structure
- RBAC (Role-Based Access Control) ensures only authorized users can access their data
- **This is multi-tenancy by database, not shared tables** (highest security model)

---

## Part 2: Device Setup in AWS IoT Core

After tenant registration, you deploy IoT certificates for the devices:

```
abc_mfg (Tenant ID)
├── Site 1 (Manufacturing Floor 1)
│   ├── Machine 1
│   │   └── Clamp Sensor (measures current/power)
│   ├── Machine 2
│   │   └── Vibration Sensor (measures vibration/temp)
│   └── Zone A
│       └── Environmental Sensor (temp/humidity/air quality)
│
├── Site 2 (Warehouse)
│   ├── Storage Zone
│   │   └── Environmental Sensor
│   └── Pump Station
│       └── Power Sensor
│
└── Site 3 (Assembly Line)
    └── (More machines)
```

Each device gets:
- **Certificate** (proves it's a real device)
- **Private Key** (signs all messages)
- **Topic Pattern** it can publish to

---

## Part 3: Real Data Flow Example

Let's trace ONE complete sensor reading from a real device all the way through the system.

### Scenario: Power Measurement at ABC Manufacturing

**Device Details:**
- Tenant: `abc_mfg` (ABC Manufacturing)
- Site: `site_001` (Manufacturing Floor 1)
- Machine: `MACHINE_001` (CNC Lathe)
- Sensor: `osm_pulse_001` (Clamp current sensor monitoring power consumption)
- Time: 2025-01-22 at 14:35:22 UTC

---

### STEP 1: Sensor Generates Data

The clamp sensor physically measures the current flowing through the machine's power line.

**Physical readings (from 3-phase power system):**
- Phase A Current: 15.3 amps
- Phase B Current: 14.8 amps
- Phase C Current: 15.1 amps
- Voltage Nominal: 400V (industrial 3-phase)
- Power Factor: 0.85
- Frequency: 50Hz (EU standard)

**Device Health:**
- Firmware Version: 1.2.3
- Signal Quality: 95% (excellent signal)
- Battery Level: 87%

---

### STEP 2: Device Creates MQTT Message

The sensor formats this as a JSON message and publishes to AWS IoT Core:

```json
{
  "deviceId": "osm_pulse_001",
  "machineId": "MACHINE_001",
  "siteId": "SITE_001",
  "timestamp": "2025-01-22T14:35:22.123Z",
  "sensorType": "clamp_current",
  "measurements": {
    "current_phase_a": 15.3,
    "current_phase_b": 14.8,
    "current_phase_c": 15.1,
    "current_rms": 15.07,
    "voltage_nominal": 400,
    "power_factor": 0.85,
    "frequency": 50.0
  },
  "metadata": {
    "firmwareVersion": "1.2.3",
    "signalQuality": 95,
    "batteryLevel": 87
  }
}
```

**Published to Topic:** `smdh/abc_mfg/MACHINE_001/current`

---

### STEP 3: AWS IoT Core Rules Engine Routes It

AWS IoT Core has a rule that intercepts ALL MQTT messages matching the pattern `smdh/+/+/+/#`

```sql
-- AWS IoT Rule: route_to_kinesis
SELECT
  topic(2) as tenant_id,      -- Extracts 'abc_mfg' from topic
  topic(3) as sensor_type,    -- Extracts 'MACHINE_001' from topic
  topic(4) as entity_id,      -- Extracts 'current' from topic
  * as payload,               -- Entire JSON message
  timestamp() as iot_timestamp -- When IoT Core received it
FROM 'smdh/+/+/+/#'
```

**After extraction:**

```json
{
  "tenant_id": "abc_mfg",
  "sensor_type": "MACHINE_001",
  "entity_id": "current",
  "payload": {
    "deviceId": "osm_pulse_001",
    "machineId": "MACHINE_001",
    "siteId": "SITE_001",
    "timestamp": "2025-01-22T14:35:22.123Z",
    "sensorType": "clamp_current",
    "measurements": { ... },
    "metadata": { ... }
  },
  "iot_timestamp": "2025-01-22T14:35:22.456Z"  -- When IoT Core saw it
}
```

**Key Insight:** The IoT rule **adds context** (tenant_id, entity_id) to the original message and adds a receipt timestamp.

---

### STEP 4: Message Lands in Kinesis Stream

The IoT rule forwards the enriched message to the Kinesis stream: **`smdh-sensor-data-stream`**

**Kinesis Configuration:**
- **Partition Key:** `${topic(2)}_${topic(4)}` = `abc_mfg_current`
  - This ensures all messages from the same tenant's same entity type stay together in the same shard
  - Enables efficient replay and parallel processing
- **Retention:** 24 hours (enough time for recovery if Snowflake ingestion temporarily fails)
- **Shards:** Auto-scaling (5 shards minimum for 30 tenants)

**Message sits in Kinesis for < 1 minute** before being picked up by Snowflake.

---

### STEP 5: Snowflake Openflow Connector Ingests Data

Snowflake has an integration configured to **continuously pull** from Kinesis and insert into the RAW tables.

**How it works:**
1. Snowflake monitors the Kinesis stream every 30-60 seconds
2. Fetches new messages from each shard
3. Validates the JSON structure
4. Inserts into the tenant's RAW.SENSOR_READINGS table

**Total latency:** < 1 minute from sensor to Snowflake table

---

### STEP 6: Data Lands in RAW.SENSOR_READINGS

The data is now persisted in Snowflake:

```sql
-- Actual INSERT into smdh_tenant_abc_mfg.raw.sensor_readings
INSERT INTO smdh_tenant_abc_mfg.raw.sensor_readings (
  reading_id,           -- 'abc_mfg_2025-01-22T14:35:22.123Z_osm_pulse_001'
  tenant_id,            -- 'abc_mfg'
  sensor_id,            -- 'osm_pulse_001'
  site_id,              -- 'SITE_001'
  device_id,            -- 'osm_pulse_001'
  timestamp,            -- 2025-01-22 14:35:22.123 (when sensor recorded it)
  ingestion_timestamp,  -- 2025-01-22 14:35:45.892 (when Snowflake received it)
  iot_timestamp,        -- 2025-01-22 14:35:22.456 (when IoT Core received it)
  payload,              -- Full JSON stored as VARIANT
  source_system,        -- 'mqtt'
  mqtt_topic,           -- 'smdh/abc_mfg/MACHINE_001/current'
  message_id,           -- Generated by Snowflake
  is_duplicate,         -- FALSE
  is_valid,             -- TRUE
  validation_errors     -- NULL
) VALUES (...)
```

**Key Observations:**

1. **Three timestamps are tracked:**
   - `timestamp` (14:35:22.123) - When the sensor measured the current
   - `iot_timestamp` (14:35:22.456) - When AWS IoT Core received the MQTT message (0.333 seconds later)
   - `ingestion_timestamp` (14:35:45.892) - When Snowflake ingested it (23 seconds later)
   - **Total latency: ~23 seconds** from physical measurement to database

2. **Raw JSON stored as VARIANT:**
   The entire `payload` is stored as-is for auditability:
   ```json
   {
     "deviceId": "osm_pulse_001",
     "machineId": "MACHINE_001",
     "siteId": "SITE_001",
     "timestamp": "2025-01-22T14:35:22.123Z",
     "measurements": {
       "current_phase_a": 15.3,
       "current_phase_b": 14.8,
       "current_phase_c": 15.1,
       "current_rms": 15.07,
       "voltage_nominal": 400,
       "power_factor": 0.85,
       "frequency": 50.0
     }
   }
   ```

3. **Tenant isolation is enforced:**
   - The data goes to `smdh_tenant_abc_mfg` database
   - Row-level security ensures other tenants can't see this data
   - The `tenant_id` field is immutable (cannot be changed once inserted)

---

## Part 4: Data Transformation Pipeline

Once data is in the RAW table, Snowflake Tasks automatically transform it:

### Stage 1: RAW → NORMALIZED (Power Metrics Calculation)

A **Stream + Task** detects new rows in `raw.sensor_readings` and calculates **power** from the raw current measurements:

```sql
-- Triggered when new data appears in raw.sensor_readings
-- Runs automatically every minute (configurable)

INSERT INTO smdh_tenant_abc_mfg.normalized.power_metrics (
  metric_id,          -- Generated ID
  tenant_id,          -- 'abc_mfg'
  machine_id,         -- 'MACHINE_001'
  timestamp,          -- 2025-01-22 14:35:22.123
  real_power_kw,      -- Calculated: √3 × V × I × PF / 1000
  apparent_power_kva, -- Calculated: √3 × V × I / 1000
  power_factor,       -- 0.85
  avg_current_amps,   -- 15.07
  max_current_amps,   -- 15.3
  voltage_volts,      -- 400
  energy_kwh          -- Real power × time (for 1-minute interval)
)
```

**Calculation Example:**

For 3-phase industrial system:
```
Real Power (kW) = √3 × V × I × PF / 1000
                = 1.732 × 400V × 15.07A × 0.85 / 1000
                = 8.83 kW

Apparent Power (kVA) = √3 × V × I / 1000
                     = 1.732 × 400V × 15.07A / 1000
                     = 10.39 kVA

Energy (kWh for 1 minute) = Power × time
                          = 8.83 kW × (1/60 hour)
                          = 0.147 kWh
```

**Result in NORMALIZED.POWER_METRICS:**
```
timestamp              | real_power_kw | apparent_power_kva | energy_kwh
2025-01-22 14:35:22   | 8.83          | 10.39              | 0.147
```

### Stage 2: NORMALIZED → AGGREGATED (Machine State Classification)

Another Task looks at power metrics and classifies the machine's **state**:

```sql
-- Every minute, classify machine state based on power consumption

INSERT INTO smdh_tenant_abc_mfg.mart.fact_machine_state (
  state_id,           -- Generated ID
  tenant_id,          -- 'abc_mfg'
  machine_id,         -- 'MACHINE_001'
  timestamp_utc,      -- 2025-01-22 14:35:22
  date_key,           -- 2025-01-22
  hour_of_day,        -- 14
  state,              -- 'WORKING' (8.83 kW > threshold_working_min_kw)
  state_confidence,   -- 0.95 (95% confidence this is correct)
  power_kw,           -- 8.83
  current_amps,       -- 15.07
  power_factor,       -- 0.85
  interval_minutes,   -- 1
  energy_kwh,         -- 0.147
  tariff_band,        -- 'peak' (based on time of day)
  rate_per_kwh,       -- £0.28 (electricity rate for peak time)
  cost_gbp            -- 0.147 × £0.28 = £0.041
)
```

**State Classification Logic:**

```
IF real_power_kw <= 0.5 kW  → 'OFF'     (machine is idle/off)
ELSE IF real_power_kw < 5 kW → 'IDLE'   (machine is on but not working)
ELSE                          → 'WORKING' (machine is actively running)
```

In our example: 8.83 kW > 5 kW → **State = 'WORKING'**

---

## Part 5: Complete Pipeline Summary

Here's the **full journey** of one sensor reading:

```
TIME        LOCATION              DATA FORM                    LATENCY
────────────────────────────────────────────────────────────────────────
14:35:22    Physical Sensor       Current measured             0s
            (on machine)

14:35:22.123 Sensor MQTT Buffer   JSON formatted message       ~1ms
             (device memory)

14:35:22.456 AWS IoT Core        Message received + enriched   +334ms
             (routing engine)     with metadata

14:35:22.456 Kinesis Stream      Message partitioned by        +0ms
             (shard)              tenant_id_entity

14:35:45.892 Snowflake RAW       Row inserted into            +23.4s
             (smdh_tenant_abc_mfg raw.sensor_readings
              .raw.sensor_readings)

14:36:22    Snowflake NORMALIZED  Power calculated            +60s
             (power_metrics)       and inserted

14:37:22    Snowflake MART        State classification        +120s
             (fact_machine_state)  (OFF/IDLE/WORKING)

14:37:22    Snowflake MART        Cost calculated             +120s
             (fact_energy_cost)    (power × rate)
```

**Total end-to-end latency: ~120 seconds (2 minutes) from sensor to insight**

---

## Part 6: Looking at Your Data

### Query 1: See Raw Ingestion Happening

```sql
-- Connect as: smdh_tenant_abc_mfg
-- What's coming in right now?

SELECT
  TIMESTAMP,
  SENSOR_ID,
  PAYLOAD:measurements.current_rms AS current_amps,
  PAYLOAD:measurements.power_factor,
  INGESTION_TIMESTAMP,
  DATEDIFF(SECOND, TIMESTAMP, INGESTION_TIMESTAMP) AS latency_seconds
FROM raw.sensor_readings
WHERE TIMESTAMP >= CURRENT_TIMESTAMP() - INTERVAL '1 hour'
ORDER BY TIMESTAMP DESC
LIMIT 100;
```

**Output Example:**
```
TIMESTAMP              | SENSOR_ID        | CURRENT_AMPS | POWER_FACTOR | LATENCY_SECONDS
2025-01-22 14:35:22   | osm_pulse_001    | 15.07        | 0.85         | 23
2025-01-22 14:34:21   | osm_pulse_001    | 14.92        | 0.85         | 24
2025-01-22 14:33:20   | osm_pulse_001    | 15.15        | 0.85         | 22
```

### Query 2: See Calculated Power

```sql
SELECT
  TIMESTAMP,
  MACHINE_ID,
  REAL_POWER_KW,
  APPARENT_POWER_KVA,
  ENERGY_KWH
FROM normalized.power_metrics
WHERE TIMESTAMP >= CURRENT_TIMESTAMP() - INTERVAL '1 hour'
ORDER BY TIMESTAMP DESC
LIMIT 10;
```

**Output Example:**
```
TIMESTAMP              | MACHINE_ID    | REAL_POWER_KW | APPARENT_POWER_KVA | ENERGY_KWH
2025-01-22 14:35:22   | MACHINE_001   | 8.83          | 10.39              | 0.147
2025-01-22 14:34:21   | MACHINE_001   | 8.71          | 10.26              | 0.145
2025-01-22 14:33:20   | MACHINE_001   | 8.95          | 10.53              | 0.149
```

### Query 3: See Machine States

```sql
SELECT
  TIMESTAMP_UTC,
  MACHINE_ID,
  STATE,
  POWER_KW,
  COST_GBP,
  STATE_CONFIDENCE
FROM mart.fact_machine_state
WHERE TIMESTAMP_UTC >= CURRENT_TIMESTAMP() - INTERVAL '1 hour'
ORDER BY TIMESTAMP_UTC DESC
LIMIT 20;
```

**Output Example:**
```
TIMESTAMP_UTC          | MACHINE_ID    | STATE    | POWER_KW | COST_GBP | STATE_CONFIDENCE
2025-01-22 14:35:22   | MACHINE_001   | WORKING  | 8.83     | 0.041    | 0.95
2025-01-22 14:34:21   | MACHINE_001   | WORKING  | 8.71     | 0.041    | 0.95
2025-01-22 14:33:20   | MACHINE_001   | WORKING  | 8.95     | 0.042    | 0.95
2025-01-22 14:32:19   | MACHINE_001   | IDLE     | 2.50     | 0.012    | 0.92
2025-01-22 14:31:18   | MACHINE_001   | OFF      | 0.10     | 0.000    | 0.98
```

### Query 4: Daily Cost Summary

```sql
SELECT
  DATE_KEY,
  MACHINE_ID,
  WORKING_HOURS,
  IDLE_HOURS,
  OFF_HOURS,
  TOTAL_ENERGY_KWH,
  TOTAL_COST_GBP,
  WORKING_PERCENTAGE
FROM mart.fact_energy_cost_daily
WHERE DATE_KEY >= CURRENT_DATE() - INTERVAL '7 days'
ORDER BY DATE_KEY DESC, MACHINE_ID;
```

**Output Example:**
```
DATE       | MACHINE_ID    | WORKING_HRS | IDLE_HRS | OFF_HRS | ENERGY_KWH | COST_GBP | WORKING_%
2025-01-22 | MACHINE_001   | 8.5         | 1.2      | 14.3    | 75.1       | 21.03    | 70.8%
2025-01-22 | MACHINE_002   | 6.2         | 2.1      | 15.7    | 54.3       | 15.20    | 51.7%
2025-01-21 | MACHINE_001   | 8.3         | 1.5      | 14.2    | 73.2       | 20.49    | 69.2%
```

---

## Part 7: Multiple Sensors Per Machine Example

Real factories have multiple sensors per machine. Here's how they all flow together:

```
MACHINE_001 (CNC Lathe)
├── osm_pulse_001 (Current/Power Sensor)
│   └── Topic: smdh/abc_mfg/MACHINE_001/current
│       └── Measures: Current A,B,C / Voltage / Power Factor
│           └── Used for: Power calculation, state classification
│
├── osm_sentinel_001 (Vibration/Temperature Sensor)
│   └── Topic: smdh/abc_mfg/MACHINE_001/vibration
│       └── Measures: Vibration X/Y/Z / Temperature
│           └── Used for: Predictive maintenance, anomaly detection
│
└── osm_haven_001 (Environmental Sensor)
    └── Topic: smdh/abc_mfg/MACHINE_001/environment
        └── Measures: Temperature / Humidity / CO2 / Air Quality
            └── Used for: Environmental compliance, facility monitoring
```

**All three sensors send data simultaneously, every 1 minute.**

Each follows the same path:
```
Sensor → IoT Core → Kinesis (partitioned by tenant_id) → Snowflake RAW
```

The raw data lands in different tables based on sensor type:
- Clamp sensor → `raw.clamp_sensor_readings`
- Vibration sensor → `raw.vibration_readings`
- Environmental sensor → `raw.environmental_readings`

But they all eventually get unified in `raw.sensor_readings` (the catch-all table).

---

## Part 8: What Happens When Things Go Wrong

### Scenario 1: Sensor Fails to Connect

```
Device tries to send → Connection fails → Message sits in device's memory buffer
```

**After 24 hours:**
- Device storage is full
- Oldest messages are discarded
- Newer messages persist

**When device reconnects:**
- Buffered messages are sent in burst
- Kinesis receives them and adds timestamps
- Snowflake ingests them all with real timestamp (not current time)
- Your dashboard shows them arriving late but with correct timestamp
- No data loss within the 24-hour window

### Scenario 2: Kinesis Temporarily Overloaded

```
Kinesis is processing 100K messages/sec → Backpressure → Messages queue
```

**Snowflake Openflow Connector:**
- Has retry logic (exponential backoff)
- Waits for Kinesis to have capacity
- Then catches up

**Your dashboard:** No latency spike visible because timestamps are preserved

### Scenario 3: Snowflake Down (Unlikely but Possible)

```
Snowflake maintenance window → Connector can't write
```

**What happens:**
- Kinesis keeps the messages (24-hour retention)
- Messages accumulate in Kinesis
- When Snowflake comes back, connector replays all accumulated messages
- Data catches up

**Result:** You might have a gap in your dashboard, but no data loss

---

## Part 9: Scaling to Multiple Tenants

When you add a **second tenant** (e.g., "XYZ Corp"):

```bash
./onboard_tenant.sh \
  --tenant-id xyz_corp \
  --tenant-name "XYZ Corporation" \
  --num-sites 5
```

What happens:

1. **New database created:** `smdh_tenant_xyz_corp`
2. **Same schema cloned:** raw, normalized, aggregated, analytics
3. **New IoT certificates generated:** For XYZ Corp's devices
4. **Same Kinesis stream used:** But messages are partitioned by tenant_id
   - Partition key: `abc_mfg_current` (ABC Manufacturing's current sensors)
   - Partition key: `xyz_corp_power` (XYZ Corp's power sensors)
   - Different partitions = parallel processing, no interference
5. **Openflow connector ingests both:**
   - Reads from all partitions
   - Routes based on `tenant_id` field
   - Inserts into correct database

**Key Insight:** Both tenants share the same AWS/Kinesis infrastructure but have completely isolated Snowflake databases. You pay per-tenant compute (Snowflake credits) but shared ingestion costs (IoT Core, Kinesis, Openflow).

---

## Part 10: Testing Your Data Flow

### Manual Test: Simulate a Single Sensor Reading

```bash
# 1. Start the device simulator
python tests/device-simulators/test-iot-transmission.py \
  --endpoint your-iot-endpoint.iot.eu-west-2.amazonaws.com \
  --cert docs/deployment/certificates/test_cert.pem \
  --key docs/deployment/certificates/test_key.pem \
  --ca /path/to/AmazonRootCA1.pem \
  --client-id test_device_001 \
  --tenant-id abc_mfg \
  --site-id site_001 \
  --device-type power_sensor \
  --mode single
```

This sends ONE power sensor message to your IoT Core.

### 2. Check Raw Table (30 seconds later)

```sql
USE DATABASE smdh_tenant_abc_mfg;

SELECT * FROM raw.sensor_readings
WHERE TIMESTAMP >= CURRENT_TIMESTAMP() - INTERVAL '1 minute'
ORDER BY INGESTION_TIMESTAMP DESC;
```

You should see your message with:
- `source_system: 'mqtt'`
- `is_valid: TRUE`
- `payload` containing all your measurements

### 3. Check Normalized (60 seconds later)

```sql
SELECT * FROM normalized.power_metrics
WHERE TIMESTAMP >= CURRENT_TIMESTAMP() - INTERVAL '1 minute'
ORDER BY TIMESTAMP DESC;
```

You should see calculated power values.

### 4. Check State Classification (120 seconds later)

```sql
SELECT * FROM mart.fact_machine_state
WHERE TIMESTAMP_UTC >= CURRENT_TIMESTAMP() - INTERVAL '1 minute'
ORDER BY TIMESTAMP_UTC DESC;
```

You should see state classification (OFF/IDLE/WORKING).

---

## Part 11: Real Test Case Flow

From `test_complete_pipeline.py`:

```python
# Simulate 30 minutes of data (1 reading per minute)
for minute in range(30):
    # First 10 minutes: machine OFF (minimal current)
    if minute < 10:
        current = 0.1A  # Standby current

    # Next 5 minutes: machine IDLE (low power)
    elif minute < 15:
        current = 2.5A  # Idle current

    # Last 15 minutes: machine WORKING (full power)
    else:
        current = 10.0A  # Full power
```

**What you'd see in your database:**

**RAW.SENSOR_READINGS (first 10 rows):**
```
Time        | Current | Status
14:00:00    | 0.1A    | OFF
14:01:00    | 0.1A    | OFF
14:02:00    | 0.1A    | OFF
...
14:09:00    | 0.1A    | OFF
14:10:00    | 2.5A    | (transitioning)
14:11:00    | 2.5A    | IDLE
...
14:15:00    | 10.0A   | WORKING
14:16:00    | 10.0A   | WORKING
...
14:29:00    | 10.0A   | WORKING
```

**NORMALIZED.POWER_METRICS (corresponding power):**
```
Time        | Real Power | Apparent Power
14:00:00    | 0.05 kW    | 0.06 kVA
14:01:00    | 0.05 kW    | 0.06 kVA
...
14:15:00    | 5.8 kW     | 6.8 kVA
14:16:00    | 5.8 kW     | 6.8 kVA
...
```

**FACT_MACHINE_STATE (state classification):**
```
Time        | State    | Power    | Confidence
14:00:00    | OFF      | 0.05 kW  | 0.98
...
14:10:00    | IDLE     | 1.5 kW   | 0.92
...
14:15:00    | WORKING  | 5.8 kW   | 0.95
...
14:29:00    | WORKING  | 5.8 kW   | 0.95
```

**FACT_ENERGY_COST_DAILY (summary):**
```
Date       | Total Hours | Off Hours | Idle Hours | Working Hours | Total Energy | Total Cost
2025-01-22 | 0.5         | 0.17      | 0.08       | 0.25          | 2.45 kWh     | £0.686
```

---

## Part 12: Troubleshooting Common Issues

### Issue: No data appearing in RAW table

**Check in order:**

1. **Is the device actually sending messages?**
   ```bash
   # Monitor IoT Core topic in real-time
   aws iot-data get-thing-shadow \
     --thing-name test_device_001 \
     --region eu-west-2
   ```

2. **Are messages being routed to Kinesis?**
   ```bash
   # Check Kinesis stream for recent records
   aws kinesis get-records \
     --shard-iterator \
     --stream-name smdh-sensor-data-stream \
     --region eu-west-2
   ```

3. **Is Openflow connector running?**
   ```sql
   -- Check Snowflake integration status
   SHOW INTEGRATIONS;

   -- Check Snowflake streams for accumulated data
   SELECT COUNT(*) FROM smdh_ingest_stream;
   ```

### Issue: Data appearing but very late (> 5 minutes)

**Likely causes:**
1. Kinesis is backed up → Check shard count and scaling
2. Snowflake is slow → Check warehouse size (should be medium or larger)
3. Network latency from device → Check device logs for connection quality

### Issue: Data showing wrong timestamps

**Check order:**
1. Device clock is wrong? → Sync device time to NTP
2. Timezone issues? → All timestamps should be UTC
3. IoT Core clock wrong? → AWS systems always have correct time

---

## Summary: The Complete Journey

```
What Happens                          | Where               | Time Elapsed
──────────────────────────────────────────────────────────────────────────
1. Sensor measures power              | Physical device     | 0s
2. Device sends MQTT message          | WiFi/Cellular       | +1-2s
3. IoT Core receives + routes          | AWS IoT Core        | +0.3s
4. Message lands in Kinesis           | AWS Kinesis         | +0s
5. Snowflake reads from Kinesis       | Snowflake Openflow  | +23s (avg)
6. RAW table populated                | RAW schema          | +0s
7. Power calculated                   | NORMALIZED schema   | +60s (next task run)
8. State classified                   | MART schema         | +120s (next task run)
9. Cost calculated                    | MART schema         | +120s (next task run)
10. Dashboard shows result            | Streamlit           | +0s (queries raw tables)
──────────────────────────────────────────────────────────────────────────
Total: ~2-5 minutes for insight availability
```

**For your specific setup with 30 tenants and 2.34B data points/month:**
- ~78K messages per minute (2.34B / 30 days / 24 hours / 60 minutes)
- Average 2,600 messages per minute per tenant
- Snowflake can easily handle this (designed for billions of records)
- Cost primarily comes from Snowflake compute (£1,400-2,300/month)

---

## Next Steps

1. **Run the simulator** to see real data flowing
2. **Monitor the RAW tables** with the queries above
3. **Create dashboards** on top of MART tables (not RAW, they're too detailed)
4. **Set up alerts** for when machines enter unexpected states
5. **Analyze cost trends** to identify optimization opportunities

