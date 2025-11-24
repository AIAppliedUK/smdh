# SMDH Snowflake Testing Guide

Comprehensive testing suite for the SMDH (Smart Manufacturing Data Hub) Snowflake implementation, ensuring data flows correctly through streams and all transformations work as expected.

## Overview

This testing suite provides complete coverage of the SMDH data layer, including:

- **Unit Tests**: Individual component testing (power calculations, state classification, ML models)
- **Integration Tests**: Stream-to-stream data flow validation
- **End-to-End Tests**: Complete pipeline from raw sensor to analytics
- **Fixtures & Utilities**: Reusable test data generators and database helpers

## Test Structure

```
tests/
├── conftest.py                          # Pytest configuration and fixtures
├── TESTING_GUIDE.md                     # This file
├── requirements.txt                     # Python dependencies
├── unit/
│   ├── test_power_calculations.py      # Power metric tests
│   ├── test_state_classification.py    # State classification tests
│   └── test_ml_models.py               # GMM and DBSCAN model tests
├── integration/
│   ├── test_stream_data_flow.py        # Stream flow integration tests
│   └── validate-data-flow.py           # Existing AWS validation
├── e2e/
│   └── test_complete_pipeline.py       # Complete pipeline tests
├── device-simulators/
│   └── test-iot-transmission.py        # Existing IoT simulation
└── scripts/
    └── mqtt-quick-test.sh              # Existing MQTT testing
```

## Quick Start

### 1. Setup Environment

```bash
# Navigate to project
cd /Users/david/projects/smdh

# Install test dependencies
pip install -r tests/requirements.txt

# Set Snowflake credentials
export SNOWFLAKE_ACCOUNT=your_account
export SNOWFLAKE_USER=your_user
export SNOWFLAKE_PASSWORD=your_password
export SNOWFLAKE_DATABASE=SMDH_TEST
export SNOWFLAKE_WAREHOUSE=SMDH_TEST_WH
```

### 2. Run Tests

```bash
# Run all tests
pytest tests/

# Run specific test file
pytest tests/unit/test_power_calculations.py

# Run specific test class
pytest tests/unit/test_state_classification.py::TestStateClassification

# Run with verbose output
pytest tests/ -v

# Run with markers
pytest tests/ -m unit          # Only unit tests
pytest tests/ -m integration   # Only integration tests
pytest tests/ -m e2e          # Only end-to-end tests
pytest tests/ -m snowflake    # Only tests requiring Snowflake connection

# Run with coverage
pytest tests/ --cov=tests --cov-report=html
```

## Test Files Detail

### 1. conftest.py - Shared Fixtures & Configuration

**Purpose**: Provides reusable fixtures and test utilities

**Key Fixtures**:

- `snowflake_config`: Loads Snowflake connection parameters from environment
- `sf_connection`: Creates Snowflake database connection for tests
- `tenant_id`, `machine_id`, `sensor_id`: Standard test identifiers
- `raw_clamp_reading()`: Generates realistic clamp sensor data
- `power_metrics_batch()`: Generates 60 minutes of power metrics
- `machine_state_batch()`: Generates machine state timeline
- `production_event()`: Generates production event data
- `energy_cost_daily()`: Generates daily cost record
- `cleanup_test_data()`: Cleans up test data after each test

**Usage**:
```python
def test_something(sf_connection, tenant_id, machine_id, cleanup_test_data):
    cursor = sf_connection.cursor()
    # Your test code here
    cursor.close()
```

---

### 2. unit/test_power_calculations.py - Power Metric Tests

**Purpose**: Validate power calculation logic and formulas

**Test Cases**:

| Test | What it validates |
|------|------------------|
| `test_power_calculation_from_three_phase_current` | Three-phase current → power conversion |
| `test_apparent_power_calculation` | S = V × I × √3 formula |
| `test_energy_calculation_from_power` | Integration of power over time → energy |
| `test_power_factor_impact_on_real_power` | Real power = Apparent power × PF |
| `test_reactive_power_calculation` | Q = S × √(1 - PF²) formula |
| `test_power_calculation_across_multiple_intervals` | Complete time series handling |
| `test_total_harmonic_distortion_values` | THD value ranges and storage |

**What Gets Tested**:
- RAW.CLAMP_SENSOR_READINGS → NORMALIZED.POWER_METRICS transformation
- Correct calculation of real, apparent, and reactive power
- Energy integration over time intervals
- Power factor impact on calculations
- THD (Total Harmonic Distortion) values

**Example Coverage**:
```
Power Calculation: 230V × 15A × 0.95 PF × √3 ÷ 1000 = 5.97 kW ✓
Energy = Power × Time: 5.97 kW × (15 minutes ÷ 60) = 1.49 kWh ✓
```

---

### 3. unit/test_state_classification.py - State Classification Tests

**Purpose**: Validate machine state classification (OFF/IDLE/WORKING)

**Test Cases**:

| Test | What it validates |
|------|-----------------|
| `test_state_classification_off_state` | Low power → OFF classification |
| `test_state_classification_idle_state` | Medium power → IDLE classification |
| `test_state_classification_working_state` | High power → WORKING classification |
| `test_state_transitions_detection` | Detecting state changes using window functions |
| `test_state_confidence_scores` | Confidence scores in valid range (0-1) |
| `test_state_duration_calculation` | Duration calculation for each state |
| `test_hourly_state_distribution` | State patterns across 24 hours |
| `test_state_with_missing_data` | Handling degraded data quality |

**What Gets Tested**:
- NORMALIZED.POWER_METRICS → MART.FACT_MACHINE_STATE transformation
- Correct state assignment based on power thresholds:
  - OFF: < 0.5 kW
  - IDLE: 0.5 - 5 kW
  - WORKING: > 5 kW
- State transition detection
- Confidence score validity
- Time spent in each state
- Data quality impact on classification

**Example Coverage**:
```
Power 0.1 kW → OFF state (confidence 0.98) ✓
Power 2.5 kW → IDLE state (confidence 0.92) ✓
Power 8.5 kW → WORKING state (confidence 0.95) ✓
State transition OFF → IDLE → WORKING detected ✓
```

---

### 4. unit/test_ml_models.py - Machine Learning Model Tests

**Purpose**: Validate ML model training, storage, and inference

**GMM (Gaussian Mixture Model) Tests**:

| Test | What it validates |
|------|-----------------|
| `test_gmm_model_storage` | Model parameters stored correctly |
| `test_gmm_state_assignment_logic` | Using GMM thresholds to assign states |
| `test_gmm_confidence_score_variation` | Confidence based on distance from centroid |

**DBSCAN Clustering Tests**:

| Test | What it validates |
|------|-----------------|
| `test_dbscan_cluster_creation` | Cluster creation and storage |
| `test_dbscan_event_assignment_to_clusters` | Events assigned to correct clusters |
| `test_dbscan_outlier_detection` | Anomalous events identified |
| `test_product_cluster_inference` | Mapping clusters to product types |

**What Gets Tested**:
- ML_MODELS.GMM_MODELS table for parameter storage
- State assignment using learned thresholds
- MART.DIM_PROD_CLUSTER dimension table
- Production event clustering
- Outlier detection (is_outlier flag)
- Product inference from production patterns

**Example Coverage**:
```
GMM with 5 components stored ✓
State thresholds: OFF ≤ 0.5 kW, IDLE 0.5-5.5 kW, WORKING > 5.5 kW ✓
Cluster 0: 25 min duration ± 3.5 min (Product A) ✓
Cluster 1: 45 min duration ± 5 min (Product B) ✓
Events < 5 min detected as outliers ✓
```

---

### 5. integration/test_stream_data_flow.py - Stream Integration Tests

**Purpose**: Validate complete data transformations across schema layers

**Test Cases**:

| Test | What it validates |
|------|-----------------|
| `test_end_to_end_clamp_to_power_flow` | Raw sensor → Power metrics transformation |
| `test_production_event_detection_from_states` | State sequence → Production events |
| `test_energy_cost_calculation_flow` | Power metrics → Daily cost calculation |
| `test_multi_tenant_data_isolation` | Data isolation between tenants |
| `test_data_latency_measurement` | Latency through pipeline |
| `test_concurrent_writes_handling` | Multiple machines writing simultaneously |

**What Gets Tested**:
- Complete transformation pipeline:
  - RAW.CLAMP_SENSOR_READINGS
  - ↓ (task_calculate_power)
  - NORMALIZED.POWER_METRICS
  - ↓ (task_assign_machine_states)
  - MART.FACT_MACHINE_STATE
  - ↓ (task_detect_production_events)
  - MART.FACT_PRODUCTION_EVENT
  - ↓ (task_calculate_energy_costs)
  - MART.FACT_ENERGY_COST_DAILY

- Multi-tenant data isolation
- Concurrent data handling
- Pipeline latency

**Example Coverage**:
```
Raw clamp reading inserted ✓
Power calculated (V × I × PF × √3) ✓
State classified based on power ✓
Production event detected from WORKING period ✓
Energy cost calculated with tariff band ✓
Multi-tenant data properly isolated ✓
Concurrent writes handled correctly ✓
```

---

### 6. e2e/test_complete_pipeline.py - End-to-End Tests

**Purpose**: Test complete data pipeline with realistic data patterns

**Test Cases**:

| Test | What it validates |
|------|-----------------|
| `test_full_cycle_clamp_sensor_to_dashboard` | Complete 30-min cycle: raw → cost |
| `test_multi_machine_production_monitoring` | 3 machines × 1 hour staggered operation |
| `test_24hour_production_cycle` | Complete day with realistic schedule |

**What Gets Tested**:
- **Full Cycle Test**: 30-minute simulation with realistic state transitions
  - OFF → IDLE → WORKING → OFF sequence
  - Proper power profile for each state
  - Cost calculation with peak/off-peak rates
  - Event detection and clustering

- **Multi-Machine Test**: 3 machines with staggered operation
  - 1 hour × 3 machines = 180 records
  - Data isolation verified
  - Concurrent write handling
  - Per-machine analytics

- **24-Hour Cycle**: Complete production day
  - 6h OFF (maintenance)
  - 1h IDLE (warmup)
  - 5h WORKING (morning)
  - 1h IDLE (lunch)
  - 4h WORKING (afternoon)
  - 1h IDLE (cooldown)
  - 6h OFF
  - Total: 1440 minute records

**Example Coverage**:
```
Phase 1: 30 raw clamp readings inserted ✓
Phase 2: 30 power metrics calculated ✓
Phase 3: 30 state classifications (OFF/IDLE/WORKING) ✓
Phase 4: Production events detected ✓
Phase 5: Daily costs calculated ✓
Multi-machine: 3 × 60 = 180 records ✓
24-hour cycle: Working 9h, Idle 3h, OFF 12h ✓
```

---

## Data Flow Validation

### Stream Processing Pipeline

```
┌──────────────────────────┐
│  Raw Sensor Data         │ ← test_power_calculations
│  CLAMP_SENSOR_READINGS   │ ← test_stream_data_flow
└────────────┬─────────────┘
             ↓
┌──────────────────────────┐
│  Power Calculations      │ ← test_power_calculations
│  NORMALIZED.power_metrics│ ← test_stream_data_flow
└────────────┬─────────────┘
             ↓
┌──────────────────────────┐
│  State Classification    │ ← test_state_classification
│  MART.fact_machine_state │ ← test_ml_models
└────────────┬─────────────┘
             ↓
┌──────────────────────────┐
│  Production Events       │ ← test_stream_data_flow
│  MART.fact_product_event │ ← test_ml_models
└────────────┬─────────────┘
             ↓
┌──────────────────────────┐
│  Energy & Cost           │ ← test_stream_data_flow
│  MART.fact_energy_cost   │
└──────────────────────────┘
```

## Running Specific Test Scenarios

### Test Scenario 1: Power Calculation Pipeline
```bash
pytest tests/unit/test_power_calculations.py -v
```
**Validates**: Raw current → calculated power metrics

### Test Scenario 2: State Classification Pipeline
```bash
pytest tests/unit/test_state_classification.py -v
```
**Validates**: Power metrics → machine states (OFF/IDLE/WORKING)

### Test Scenario 3: Complete Stream Flow
```bash
pytest tests/integration/test_stream_data_flow.py::TestStreamDataFlow::test_end_to_end_clamp_to_power_flow -v
```
**Validates**: Complete transformation RAW → NORMALIZED → MART

### Test Scenario 4: ML Model Inference
```bash
pytest tests/unit/test_ml_models.py -v
```
**Validates**: GMM state classification, DBSCAN clustering

### Test Scenario 5: Full End-to-End Pipeline
```bash
pytest tests/e2e/test_complete_pipeline.py::TestCompletePipeline::test_full_cycle_clamp_sensor_to_dashboard -v
```
**Validates**: Complete 30-minute cycle with realistic data

### Test Scenario 6: 24-Hour Production Monitoring
```bash
pytest tests/e2e/test_complete_pipeline.py::TestCompletePipeline::test_24hour_production_cycle -v
```
**Validates**: Full production day with staggered schedules

## Expected Test Results

All tests should pass with output similar to:

```
=========================== test session starts ===========================
collected 45 items

tests/unit/test_power_calculations.py ........................  [ 42%]
tests/unit/test_state_classification.py ....................  [ 62%]
tests/unit/test_ml_models.py .......................      [ 75%]
tests/integration/test_stream_data_flow.py ................  [ 90%]
tests/e2e/test_complete_pipeline.py ...................     [100%]

======================== 45 passed in 127.35s ==========================
```

## Data Quality Assurance

### What Gets Validated

1. **Calculation Accuracy**
   - Power formulas correct (S = V × I × √3, P = S × cos(φ), Q = S × sin(φ))
   - Energy integration correct (kWh = kW × hours)
   - Cost calculation correct (Cost = Energy × Rate)

2. **State Classification**
   - Correct threshold application
   - Proper confidence score assignment
   - Valid state transitions
   - Duration calculation accuracy

3. **Data Integrity**
   - No data loss through transformations
   - Multi-tenant isolation maintained
   - Concurrent writes handled safely
   - Proper data ordering and indexing

4. **Performance**
   - Reasonable pipeline latency
   - Efficient bulk operations
   - Proper resource usage

5. **Reliability**
   - Consistent results across multiple runs
   - Proper error handling
   - Data recovery capabilities

## Troubleshooting

### Connection Issues

```bash
# Verify Snowflake credentials
echo $SNOWFLAKE_ACCOUNT
echo $SNOWFLAKE_USER
# Re-export if needed
export SNOWFLAKE_ACCOUNT=your_account
export SNOWFLAKE_USER=your_user
export SNOWFLAKE_PASSWORD=your_password
```

### Missing Tables

Tests create their own test tables. If you get "table does not exist" errors:

```bash
# Verify database exists
# Login to Snowflake and run:
SHOW DATABASES;
SHOW TABLES IN DATABASE SMDH_TEST;
```

### Test Cleanup Issues

Each test cleans up after itself using the `cleanup_test_data` fixture. If you need manual cleanup:

```bash
# Login to Snowflake and run:
DELETE FROM RAW.CLAMP_SENSOR_READINGS WHERE reading_id LIKE 'test_%';
DELETE FROM NORMALIZED.POWER_METRICS WHERE metric_id LIKE 'test_%';
DELETE FROM MART.FACT_MACHINE_STATE WHERE state_id LIKE 'test_%';
DELETE FROM MART.FACT_PRODUCTION_EVENT WHERE event_id LIKE 'test_%';
```

### Performance Issues

If tests run slowly:

```bash
# Use a larger warehouse
export SNOWFLAKE_WAREHOUSE=LARGE_WH

# Run fewer tests first
pytest tests/unit/test_power_calculations.py::TestPowerCalculations::test_power_calculation_from_three_phase_current -v
```

## Continuous Integration

For CI/CD pipelines (GitHub Actions, Jenkins, etc.):

```yaml
# Example GitHub Actions workflow
name: Snowflake Tests
on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - uses: actions/setup-python@v2
        with:
          python-version: 3.9
      - name: Install dependencies
        run: pip install -r tests/requirements.txt
      - name: Run tests
        env:
          SNOWFLAKE_ACCOUNT: ${{ secrets.SNOWFLAKE_ACCOUNT }}
          SNOWFLAKE_USER: ${{ secrets.SNOWFLAKE_USER }}
          SNOWFLAKE_PASSWORD: ${{ secrets.SNOWFLAKE_PASSWORD }}
          SNOWFLAKE_DATABASE: SMDH_TEST
          SNOWFLAKE_WAREHOUSE: COMPUTE_WH
        run: pytest tests/ -v --cov=tests
```

## Documentation

- **Data Design**: [SMDH_Data_Layer_Design_Working.md](../applications/data-layer/SMDH_Data_Layer_Design_Working.md)
- **Implementation Guide**: [SMDH_Data_Layer_Implementation_Guide.md](../applications/data-layer/SMDH_Data_Layer_Implementation_Guide.md)
- **Data Ingestion**: [DATA_INGESTION_MAPPING.md](../applications/data-layer/DATA_INGESTION_MAPPING.md)

## Support

For issues or questions:
1. Check the test output for specific failures
2. Review the conftest.py fixtures being used
3. Verify Snowflake connection and credentials
4. Check that required tables exist in the database
5. Review test logs for data and assertion details

## Contributing

To add new tests:

1. Create test in appropriate directory (unit/integration/e2e)
2. Use fixtures from conftest.py where possible
3. Add cleanup in finally block or use cleanup_test_data fixture
4. Document test purpose and expectations
5. Run with `-v` flag for detailed output
6. Add documentation to this guide

---

**Last Updated**: 2024
**Test Coverage**: 45 tests across unit, integration, and end-to-end scenarios
**Snowflake Schemas**: RAW, NORMALIZED, MART, ML_MODELS
