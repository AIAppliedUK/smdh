# Quick Start Guide - SMDH Testing

## 5-Minute Setup

### 1. Install Dependencies
```bash
pip install -r tests/requirements.txt
```

### 2. Set Environment Variables
```bash
export SNOWFLAKE_ACCOUNT=your_account
export SNOWFLAKE_USER=your_user
export SNOWFLAKE_PASSWORD=your_password
export SNOWFLAKE_DATABASE=SMDH_TEST
export SNOWFLAKE_WAREHOUSE=COMPUTE_WH
```

### 3. Run Tests
```bash
# All tests
pytest tests/ -v

# Quick check (just unit tests)
pytest tests/unit/ -v

# Specific test
pytest tests/unit/test_power_calculations.py -v
```

---

## Test Categories

### Unit Tests (Fast - 5-10 seconds each)
```bash
# Power calculations
pytest tests/unit/test_power_calculations.py -v

# State classification
pytest tests/unit/test_state_classification.py -v

# ML models
pytest tests/unit/test_ml_models.py -v
```

**What they test**: Individual formulas, calculations, SQL functions

### Integration Tests (Medium - 15-30 seconds each)
```bash
pytest tests/integration/test_stream_data_flow.py -v
```

**What they test**: Data flows across schema layers (RAW → NORMALIZED → MART)

### End-to-End Tests (Slower - 30-60 seconds each)
```bash
pytest tests/e2e/test_complete_pipeline.py -v
```

**What they test**: Complete pipeline with realistic data and scenarios

---

## Common Commands

```bash
# Run with markers
pytest tests/ -m unit              # Unit tests only
pytest tests/ -m integration       # Integration tests only
pytest tests/ -m e2e              # End-to-end tests only
pytest tests/ -m snowflake         # All Snowflake tests

# Run with output
pytest tests/ -v                   # Verbose
pytest tests/ -s                   # Show print statements
pytest tests/ -vv                  # Very verbose

# Run with coverage
pytest tests/ --cov=tests          # Coverage report
pytest tests/ --cov-report=html    # HTML coverage report

# Run specific test
pytest tests/unit/test_power_calculations.py::TestPowerCalculations::test_power_calculation_from_three_phase_current -v

# Stop on first failure
pytest tests/ -x -v

# Run last failed tests
pytest tests/ --lf
```

---

## Test Summary

| File | Tests | Purpose | Time |
|------|-------|---------|------|
| test_power_calculations.py | 7 | Power metric formulas | ~5s |
| test_state_classification.py | 8 | State classification logic | ~8s |
| test_ml_models.py | 7 | GMM & DBSCAN models | ~6s |
| test_stream_data_flow.py | 6 | Stream transformations | ~20s |
| test_complete_pipeline.py | 3 | Full pipeline cycles | ~40s |
| **Total** | **31** | **All coverage** | **~80s** |

---

## Key Test Flows

### 1. Power Calculation (10 seconds)
```
Clamp Sensor Data → Power Metrics → Energy Calculation
```
Run: `pytest tests/unit/test_power_calculations.py -v`

### 2. State Classification (8 seconds)
```
Power Metrics → State Assignment (OFF/IDLE/WORKING)
```
Run: `pytest tests/unit/test_state_classification.py -v`

### 3. Complete Stream (20 seconds)
```
Raw Sensor → Power → State → Event → Cost
```
Run: `pytest tests/integration/test_stream_data_flow.py::TestStreamDataFlow::test_end_to_end_clamp_to_power_flow -v`

### 4. Full 24-Hour Cycle (40 seconds)
```
1440 sensor readings → 1440 states → Daily cost report
```
Run: `pytest tests/e2e/test_complete_pipeline.py::TestCompletePipeline::test_24hour_production_cycle -v`

---

## Expected Output

```
============================= test session starts ==============================
collected 31 items

tests/unit/test_power_calculations.py::TestPowerCalculations::test_power_calculation_from_three_phase_current PASSED [ 3%]
tests/unit/test_power_calculations.py::TestPowerCalculations::test_apparent_power_calculation PASSED [ 6%]
...
tests/e2e/test_complete_pipeline.py::TestCompletePipeline::test_24hour_production_cycle PASSED [100%]

============================== 31 passed in 78.45s ==============================
```

---

## Troubleshooting

### "Connection failed"
```bash
# Check credentials
echo $SNOWFLAKE_ACCOUNT
echo $SNOWFLAKE_DATABASE

# Re-set if needed
export SNOWFLAKE_ACCOUNT=xyz12345.us-east-1
```

### "Table does not exist"
Tests create their own tables. If error persists:
```bash
# Check database has schema
# Login to Snowflake:
USE DATABASE SMDH_TEST;
SHOW SCHEMAS;
```

### Tests run slowly
```bash
# Use bigger warehouse
export SNOWFLAKE_WAREHOUSE=LARGE_WH

# Or just run fast tests
pytest tests/unit/ -v
```

### Need to clean up test data manually
```sql
-- Login to Snowflake and run:
DELETE FROM RAW.CLAMP_SENSOR_READINGS WHERE reading_id LIKE '%test%';
DELETE FROM NORMALIZED.POWER_METRICS WHERE metric_id LIKE '%test%';
DELETE FROM MART.FACT_MACHINE_STATE WHERE state_id LIKE '%test%';
```

---

## What Gets Tested

✅ Power calculations (3-phase, apparent, real, reactive)
✅ Energy integration (kW → kWh)
✅ Cost calculations (kWh × rate)
✅ State classification (OFF/IDLE/WORKING)
✅ State transitions and duration
✅ ML model storage and inference
✅ Production event detection
✅ Multi-tenant data isolation
✅ Concurrent data handling
✅ 24-hour production cycles

---

## Next Steps

1. **Run quick test**: `pytest tests/unit/test_power_calculations.py::TestPowerCalculations::test_power_calculation_from_three_phase_current -v`
2. **Run all unit tests**: `pytest tests/unit/ -v`
3. **Run integration test**: `pytest tests/integration/ -v`
4. **Run complete pipeline**: `pytest tests/e2e/ -v`
5. **Check full results**: `pytest tests/ -v --tb=short`

For detailed information, see [TESTING_GUIDE.md](TESTING_GUIDE.md)
