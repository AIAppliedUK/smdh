# Quick Reference: Data Flow Visualization

## Single Message Journey (30-second high-level overview)

```
┌─────────────────────────────────────────────────────────────────────┐
│                        PHYSICAL SENSOR                              │
│  (Clamp sensor on CNC Lathe at ABC Manufacturing, Site 001)         │
│                                                                      │
│  Measures 3-phase current: 15.3A, 14.8A, 15.1A (400V, PF: 0.85)    │
└─────────────────────────┬───────────────────────────────────────────┘
                          │ (MQTT over WiFi/Cellular)
                          │ Topic: smdh/abc_mfg/MACHINE_001/current
                          │ Payload: JSON with measurements
                          ↓
┌─────────────────────────────────────────────────────────────────────┐
│                  AWS IOT CORE (Route & Enrich)                       │
│                                                                      │
│  Rule: route_to_kinesis                                             │
│  Extracts: tenant_id=abc_mfg, entity=MACHINE_001, current           │
│  Adds: iot_timestamp=2025-01-22T14:35:22.456Z                       │
└─────────────────────────┬───────────────────────────────────────────┘
                          │ (Enriched JSON)
                          ↓
┌─────────────────────────────────────────────────────────────────────┐
│            KINESIS DATA STREAM (Buffer & Partition)                  │
│  Stream: smdh-sensor-data-stream                                    │
│  Partition Key: abc_mfg_current (ensures ordering for this tenant)  │
│  Retention: 24 hours                                                │
└─────────────────────────┬───────────────────────────────────────────┘
                          │ (<1 minute wait)
                          ↓
┌─────────────────────────────────────────────────────────────────────┐
│       SNOWFLAKE OPENFLOW CONNECTOR (Pull & Validate)                │
│                                                                      │
│  Continuously polls Kinesis                                         │
│  Validates JSON structure                                           │
│  Transforms to table format                                         │
└─────────────────────────┬───────────────────────────────────────────┘
                          │ (INSERT statement)
                          ↓
┌─────────────────────────────────────────────────────────────────────┐
│         SNOWFLAKE RAW TABLE (Store Original Data)                    │
│                                                                      │
│  Database: smdh_tenant_abc_mfg                                       │
│  Schema:   raw                                                      │
│  Table:    sensor_readings                                          │
│                                                                      │
│  Columns stored:                                                    │
│  • reading_id: UUID                                                 │
│  • tenant_id: abc_mfg                                               │
│  • sensor_id: osm_pulse_001                                         │
│  • timestamp: 2025-01-22T14:35:22.123Z (sensor time)                │
│  • ingestion_timestamp: 2025-01-22T14:35:45.892Z (Snowflake time)   │
│  • payload: {"measurements": {...}} (Full JSON as VARIANT)          │
│  • source_system: mqtt                                              │
│  • is_valid: true, is_duplicate: false                              │
│                                                                      │
│  ⏱️  Total latency: ~23 seconds                                      │
└─────────────────────────┬───────────────────────────────────────────┘
                          │ (Stream detects new row)
                          │ (Task runs every 1 minute)
                          ↓
┌─────────────────────────────────────────────────────────────────────┐
│      SNOWFLAKE NORMALIZED TABLE (Calculate Power)                    │
│                                                                      │
│  Database: smdh_tenant_abc_mfg                                       │
│  Schema:   normalized                                               │
│  Table:    power_metrics                                            │
│                                                                      │
│  Calculation: P = √3 × V × I × PF / 1000                            │
│            = 1.732 × 400V × 15.07A × 0.85 / 1000                    │
│            = 8.83 kW                                                │
│                                                                      │
│  Columns stored:                                                    │
│  • metric_id: UUID                                                  │
│  • tenant_id: abc_mfg                                               │
│  • machine_id: MACHINE_001                                          │
│  • timestamp: 2025-01-22T14:35:22Z                                  │
│  • real_power_kw: 8.83                                              │
│  • apparent_power_kva: 10.39                                        │
│  • power_factor: 0.85                                               │
│  • energy_kwh: 0.147 (for 1-minute interval)                        │
│                                                                      │
│  ⏱️  Added latency: +60 seconds                                      │
└─────────────────────────┬───────────────────────────────────────────┘
                          │ (Task runs every 1 minute)
                          ↓
┌─────────────────────────────────────────────────────────────────────┐
│         SNOWFLAKE MART TABLE (State Classification)                  │
│                                                                      │
│  Database: smdh_tenant_abc_mfg                                       │
│  Schema:   mart                                                     │
│  Table:    fact_machine_state                                       │
│                                                                      │
│  State Logic:                                                       │
│  • If power ≤ 0.5 kW  → 'OFF'      (confidence: 0.98)              │
│  • If power ≤ 5 kW    → 'IDLE'     (confidence: 0.92)              │
│  • If power > 5 kW    → 'WORKING'  (confidence: 0.95)              │
│                                                                      │
│  Our reading: 8.83 kW → 'WORKING'                                  │
│                                                                      │
│  Columns stored:                                                    │
│  • state_id: UUID                                                   │
│  • tenant_id: abc_mfg                                               │
│  • machine_id: MACHINE_001                                          │
│  • timestamp_utc: 2025-01-22T14:35:22Z                              │
│  • date_key: 2025-01-22                                             │
│  • hour_of_day: 14                                                  │
│  • state: 'WORKING'                                                 │
│  • state_confidence: 0.95                                           │
│  • power_kw: 8.83                                                   │
│  • tariff_band: 'peak' (based on time of day)                       │
│  • rate_per_kwh: 0.28 (£ for peak time)                             │
│  • cost_gbp: 0.041 (power × rate for 1 minute)                      │
│                                                                      │
│  ⏱️  Added latency: +60 seconds                                      │
└─────────────────────────┬───────────────────────────────────────────┘
                          │ (Queries from this layer)
                          ↓
┌─────────────────────────────────────────────────────────────────────┐
│             DASHBOARDS & ANALYTICS (Visualization)                   │
│                                                                      │
│  Streamlit Portal queries:                                          │
│  • Real-time machine status (ON/OFF/IDLE)                           │
│  • Power consumption graphs                                         │
│  • Daily cost breakdowns                                            │
│  • Energy KPI reports                                               │
│                                                                      │
│  ⏱️  Instant queries (< 1 second)                                    │
└─────────────────────────────────────────────────────────────────────┘

📊 TOTAL JOURNEY TIME: ~130 seconds (2+ minutes)
   - Raw data in Snowflake: ~23 seconds
   - Power calculation: +60 seconds
   - State classification: +60 seconds
   - Dashboard shows: immediate (queries existing tables)
```

---

## Multi-Tenant Isolation

```
┌────────────────────────────────────────────────────────────────┐
│                    AWS ACCOUNT (Shared)                        │
│                                                                │
│  ┌──────────────┐                                             │
│  │  IoT Core    │ (Receives ALL messages from ALL tenants)    │
│  │              │                                              │
│  │ Route rule:  │ Forwards to Kinesis → Partition by tenant  │
│  └──────┬───────┘                                              │
│         │                                                      │
│         ↓                                                      │
│  ┌──────────────────────────────────────┐                     │
│  │    Kinesis Data Stream               │                     │
│  │  smdh-sensor-data-stream             │                     │
│  │                                      │                     │
│  │  Partition 1: abc_mfg_*              │                     │
│  │  (ABC Manufacturing messages)        │                     │
│  │  Partition 2: xyz_corp_*             │                     │
│  │  (XYZ Corp messages)                 │                     │
│  │  Partition 3: other_tenant_*         │                     │
│  │  (Other tenant messages)             │                     │
│  └──────┬──────────────────────────────┘                      │
│         │ (Openflow reads all partitions)                     │
│         ↓                                                      │
└────────────────────────────────────────────────────────────────┘
         │ (Routes by tenant_id field)
         │
         ├──────────────────┬──────────────────┬──────────────────┐
         │                  │                  │                  │
         ↓                  ↓                  ↓                  ↓
    ┌─────────────┐   ┌─────────────┐   ┌─────────────┐
    │ Snowflake   │   │ Snowflake   │   │ Snowflake   │
    │             │   │             │   │             │
    │smdh_tenant_ │   │smdh_tenant_ │   │smdh_tenant_ │
    │abc_mfg      │   │xyz_corp     │   │other_tenant │
    │             │   │             │   │             │
    │ ├─ raw      │   │ ├─ raw      │   │ ├─ raw      │
    │ ├─ normal.  │   │ ├─ normal.  │   │ ├─ normal.  │
    │ ├─ aggreg.  │   │ ├─ aggreg.  │   │ ├─ aggreg.  │
    │ └─ analytics│   │ └─ analytics│   │ └─ analytics│
    │             │   │             │   │             │
    │ (ABC data   │   │ (XYZ data   │   │ (Other      │
    │ only)       │   │ only)       │   │ only)       │
    └─────────────┘   └─────────────┘   └─────────────┘
         │                  │                  │
         ↓                  ↓                  ↓
    ┌─────────────┐   ┌─────────────┐   ┌─────────────┐
    │   Portal    │   │   Portal    │   │   Portal    │
    │  Login:     │   │  Login:     │   │  Login:     │
    │ abc@mfg.com │   │ ops@xyz.com │   │other_user   │
    │             │   │             │   │             │
    │ Sees ABC    │   │ Sees XYZ    │   │ Sees their  │
    │ data only   │   │ data only   │   │ data only   │
    └─────────────┘   └─────────────┘   └─────────────┘
```

**Key Points:**
- ✅ All tenants share AWS IoT Core, Kinesis, Openflow infrastructure
- ✅ Each tenant gets **completely separate** Snowflake database
- ✅ No shared tables between tenants (highest security)
- ✅ Cost: Common infrastructure (IoT, Kinesis) + Per-tenant compute (Snowflake)

---

## Example: 30 Minutes of Real Data

### Scenario
Machine runs for 30 minutes:
- Minutes 0-9:   OFF (standby)
- Minutes 10-14: IDLE (warming up)
- Minutes 15-29: WORKING (producing)

### What You See in Each Table

**RAW.SENSOR_READINGS**
```
Time (min)  | Current (A) | Payload
0           | 0.1         | {...measurements...}
1           | 0.1         | {...measurements...}
...
9           | 0.1         | {...measurements...}
10          | 2.5         | {...measurements...}  ← Transition
11          | 2.5         | {...measurements...}
...
14          | 2.5         | {...measurements...}
15          | 10.0        | {...measurements...}  ← Transition
16          | 10.0        | {...measurements...}
...
29          | 10.0        | {...measurements...}
```

**NORMALIZED.POWER_METRICS** (calculated 60 seconds later)
```
Time (min)  | Power (kW)  | Energy (kWh)
0           | 0.05        | 0.0008
1           | 0.05        | 0.0008
...
9           | 0.05        | 0.0008
10          | 1.5         | 0.025
11          | 1.5         | 0.025
...
14          | 1.5         | 0.025
15          | 5.8         | 0.097
16          | 5.8         | 0.097
...
29          | 5.8         | 0.097
```

**MART.FACT_MACHINE_STATE** (classified 120 seconds later)
```
Time (min)  | State    | Power (kW) | Confidence
0           | OFF      | 0.05       | 0.98
1           | OFF      | 0.05       | 0.98
...
9           | OFF      | 0.05       | 0.98
10          | IDLE     | 1.5        | 0.92
11          | IDLE     | 1.5        | 0.92
...
14          | IDLE     | 1.5        | 0.92
15          | WORKING  | 5.8        | 0.95
16          | WORKING  | 5.8        | 0.95
...
29          | WORKING  | 5.8        | 0.95
```

**MART.FACT_ENERGY_COST_DAILY** (summarized)
```
Date        | Off Hours | Idle Hours | Working Hours | Total Energy | Total Cost (£)
2025-01-22  | 0.17      | 0.08       | 0.25          | 2.43 kWh     | 0.68
```

---

## Scaling to 30 Tenants

```
IoT Messages:
  30 tenants × 4 sensors per machine × 5 machines per site × 3 sites
  = 30 × 4 × 5 × 3 = 1,800 sensors
  = 2.34B messages/month
  = 78,000 messages/minute
  ≈ 2,600 messages/minute per tenant on average

Kinesis:
  ✓ Partitioned by tenant_id → parallel processing
  ✓ No tenant conflicts
  ✓ On-demand scaling (auto-scales with load)

Snowflake:
  ✓ 30 separate databases (each reads from Kinesis)
  ✓ Each runs its own tasks independently
  ✓ Compute scaled per volume (all tenants together: 1 large warehouse)
  ✓ Cost: ~£1,500-2,300/month (shared compute across all tenants)
  ✓ Per-tenant cost: £50-77/month

Cost Breakdown (Option B - Recommended):
  • Common Infrastructure:     £181/month
    - IoT Core: £1.68
    - API Gateway: £27.60
    - Portal (ECS): £56.94
    - NAT Gateway: £66.96
    - KMS: £28.00

  • Snowflake (variable):      £1,479-2,305/month
    - Compute: £1,416-2,242 (scales with data volume)
    - Storage: £63 (2TB at £31.50/TB)

  • Kinesis:                   £44/month (5 shards)

  • QuickSight:                £360/month (30 users × £12)

  TOTAL:  £2,064-2,790/month for 30 tenants
          £69-93 per tenant
```

---

## Query Examples by Use Case

### "Show me machine status NOW"
```sql
SELECT
  machine_id,
  state,
  power_kw,
  DATEDIFF(MINUTE, timestamp_utc, CURRENT_TIMESTAMP()) as minutes_ago,
  cost_gbp
FROM mart.fact_machine_state
WHERE timestamp_utc >= CURRENT_TIMESTAMP() - INTERVAL '5 minutes'
ORDER BY timestamp_utc DESC;
```

### "Show me total energy cost today"
```sql
SELECT
  SUM(total_cost_gbp) as total_cost,
  SUM(total_energy_kwh) as total_energy,
  COUNT(DISTINCT machine_id) as machines_running
FROM mart.fact_energy_cost_daily
WHERE date_key = CURRENT_DATE();
```

### "Show me which machines are idle right now"
```sql
SELECT
  machine_id,
  timestamp_utc,
  power_kw,
  DATEDIFF(MINUTE, timestamp_utc, CURRENT_TIMESTAMP()) as idle_minutes
FROM mart.fact_machine_state
WHERE state = 'IDLE'
  AND timestamp_utc >= CURRENT_TIMESTAMP() - INTERVAL '10 minutes'
ORDER BY power_kw DESC;
```

### "Show me raw sensor readings for debugging"
```sql
SELECT
  timestamp,
  sensor_id,
  payload:measurements.current_rms as current,
  payload:measurements.power_factor as pf,
  DATEDIFF(SECOND, timestamp, ingestion_timestamp) as latency_sec
FROM raw.sensor_readings
WHERE timestamp >= CURRENT_TIMESTAMP() - INTERVAL '1 hour'
ORDER BY timestamp DESC;
```

---

## Troubleshooting Checklist

```
❌ No data in RAW tables (after 2 minutes)
  ├─ Check: Device sending to correct topic?
  │  Command: aws iot-data publish --topic smdh/... --payload ...
  │
  ├─ Check: IoT rule firing?
  │  AWS Console → IoT Core → Rules → Check rule hit counter
  │
  ├─ Check: Messages in Kinesis?
  │  Command: aws kinesis get-records --stream-name smdh-sensor-data-stream
  │
  └─ Check: Snowflake connector running?
     Query: SELECT * FROM information_schema.pipes;

❌ Data in Kinesis but not in Snowflake
  ├─ Check: Openflow connector status
  │  Query: SHOW INTEGRATIONS;
  │
  ├─ Check: Error messages in connector logs
  │  AWS Console → S3 → smdh-logs bucket
  │
  └─ Check: Snowflake warehouse active?
     Query: SHOW WAREHOUSES;

⏱️ Data delayed (> 5 minutes)
  ├─ Check: Kinesis shard count
  │  Command: aws kinesis describe-stream --stream-name smdh-sensor-data-stream
  │
  ├─ Check: Snowflake query performance
  │  Query: SELECT * FROM snowflake.account_usage.query_history;
  │
  └─ Check: Device network latency
     Device logs should show MQTT publish time vs IoT Core timestamp

🔐 Can't see other tenant's data
  ✓ This is CORRECT behavior
  ✓ Use correct database: USE DATABASE smdh_tenant_their_id;
```

---

## Performance Benchmarks (For Your 30-Tenant Setup)

```
Operation                          | Typical Time  | Max Time
───────────────────────────────────────────────────────────────
Device → IoT Core                  | 0.3s          | 2s
IoT Core → Kinesis                 | < 0.1s        | 1s
Kinesis → Snowflake RAW            | 23s           | 60s (backlog)
RAW → NORMALIZED (power calc)      | +60s          | +120s (next task)
NORMALIZED → MART (state)          | +60s          | +120s (next task)
Query RAW table (100K rows)        | < 100ms       | 1s
Query MART table (all machines)    | < 500ms       | 2s
Daily cost calculation             | < 1s          | 5s
───────────────────────────────────────────────────────────────
Total: Data → Dashboard            | ~130s         | ~300s
```

---

## Architecture Decision: Why This Design?

| Decision | Why | Benefit |
|----------|-----|---------|
| **Separate database per tenant** | Maximum isolation | No cross-tenant data leaks |
| **Raw table stores JSON as VARIANT** | Flexibility | Handle new sensor types without schema changes |
| **Three schemas (raw/norm/agg)** | Separation of concerns | Easy to understand, modify, debug |
| **Kinesis before Snowflake** | Buffering & ordering | Handles traffic spikes, guarantees order per tenant |
| **Tasks for transformation** | Automatic processing | No manual ETL, scales with data |
| **Streams for CDC** | Incremental processing | Only process new data, not full table scan |
| **Separate MART tables** | Business logic | Ready for dashboards, no complex joins |
| **Snowflake (not SiteWise)** | Cost & flexibility | £73-100 per tenant vs £83 for SiteWise |

