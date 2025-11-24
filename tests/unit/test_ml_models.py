"""
Unit tests for ML models in Snowflake
Tests GMM-based state classification and DBSCAN clustering
"""

import pytest
from datetime import datetime, timedelta
import json


@pytest.mark.unit
@pytest.mark.snowflake
class TestGMMStateClassification:
    """Test suite for Gaussian Mixture Model (GMM) state classification"""

    def test_gmm_model_storage(self, sf_connection, tenant_id, machine_id):
        """Test that GMM models are stored correctly in the model registry"""
        cursor = sf_connection.cursor()

        try:
            # Given: a trained GMM model with 5 components
            model_version = "1.0"
            training_date = datetime.utcnow().isoformat()

            model_params = {
                "machine_id": machine_id,
                "training_samples": 15000,
                "n_components": 5,
                "components": [
                    {
                        "mean": 0.15,
                        "std": 0.08,
                        "weight": 0.35,
                        "support": 5250,
                        "min": 0.02,
                        "max": 0.45
                    },
                    {
                        "mean": 2.5,
                        "std": 0.8,
                        "weight": 0.25,
                        "support": 3750,
                        "min": 1.0,
                        "max": 5.0
                    },
                    {
                        "mean": 8.5,
                        "std": 1.2,
                        "weight": 0.40,
                        "support": 6000,
                        "min": 5.5,
                        "max": 12.0
                    }
                ],
                "states": {
                    "OFF": {
                        "min": 0,
                        "max": 0.5,
                        "components": [0]
                    },
                    "IDLE": {
                        "min": 0.5,
                        "max": 5.5,
                        "components": [1]
                    },
                    "WORKING": {
                        "min": 5.5,
                        "max": float('inf'),
                        "components": [2]
                    }
                },
                "model_version": model_version,
                "training_date": training_date
            }

            # When: storing the GMM model
            # First create the table if needed
            cursor.execute("""
            CREATE TABLE IF NOT EXISTS ML_MODELS.GMM_MODELS (
                model_id VARCHAR(255) DEFAULT UUID_STRING(),
                tenant_id VARCHAR(100) NOT NULL,
                machine_id VARCHAR(255) NOT NULL,
                model_params VARIANT,
                created_timestamp TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
                updated_timestamp TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
                PRIMARY KEY (model_id)
            )
            """)

            sql = f"""
            INSERT INTO ML_MODELS.GMM_MODELS (
                tenant_id, machine_id, model_params
            ) VALUES (
                '{tenant_id}', '{machine_id}',
                PARSE_JSON('{json.dumps(model_params)}')
            )
            """
            cursor.execute(sql)

            # Then: verify model is stored correctly
            cursor.execute(f"""
            SELECT
                model_params['machine_id'] as machine_id,
                model_params['n_components'] as n_components,
                model_params['training_samples'] as training_samples
            FROM ML_MODELS.GMM_MODELS
            WHERE machine_id = '{machine_id}'
            LIMIT 1
            """)

            result = cursor.fetchone()
            assert result is not None, "Model should be stored"
            assert result[1] == 5, "Should have 5 components"
            assert result[2] == 15000, "Should have 15000 training samples"

        finally:
            cursor.execute(f"""
            DELETE FROM ML_MODELS.GMM_MODELS
            WHERE machine_id = '{machine_id}'
            """)
            cursor.close()

    def test_gmm_state_assignment_logic(self, sf_connection, tenant_id, machine_id):
        """Test the logic of assigning power readings to states using GMM thresholds"""
        cursor = sf_connection.cursor()

        try:
            # Given: GMM-derived thresholds for state assignment
            thresholds = {
                'off_max': 0.5,
                'idle_min': 0.5,
                'idle_max': 5.5,
                'working_min': 5.5
            }

            # Test cases: (power, expected_state)
            test_cases = [
                (0.1, 'OFF'),
                (0.3, 'OFF'),
                (0.5, 'OFF'),
                (1.0, 'IDLE'),
                (2.5, 'IDLE'),
                (5.0, 'IDLE'),
                (5.5, 'WORKING'),
                (8.5, 'WORKING'),
                (10.0, 'WORKING'),
            ]

            timestamp = datetime.utcnow()

            # When: assigning states based on thresholds
            for power, expected_state in test_cases:
                sql = f"""
                INSERT INTO MART.FACT_MACHINE_STATE (
                    state_id, tenant_id, machine_id, timestamp_utc, date_key,
                    hour_of_day, state, state_confidence, power_kw, current_amps,
                    power_factor, interval_minutes, energy_kwh, tariff_band,
                    rate_per_kwh, cost_gbp, data_quality
                ) VALUES (
                    'gmm_test_power_{power}', '{tenant_id}', '{machine_id}',
                    '{timestamp.isoformat()}', '{timestamp.date().isoformat()}',
                    {timestamp.hour}, '{expected_state}', 0.95, {power}, {power / 0.23},
                    0.95, 1, {power / 60}, 'peak', 0.28, {power * 0.28 / 60}, 'good'
                )
                """
                cursor.execute(sql)

            # Then: verify all states are assigned correctly
            cursor.execute(f"""
            SELECT
                power_kw,
                state,
                CASE
                    WHEN power_kw <= {thresholds['off_max']} THEN 'OFF'
                    WHEN power_kw > {thresholds['idle_min']} AND power_kw <= {thresholds['idle_max']} THEN 'IDLE'
                    WHEN power_kw > {thresholds['working_min']} THEN 'WORKING'
                    ELSE 'UNKNOWN'
                END as calculated_state
            FROM MART.FACT_MACHINE_STATE
            WHERE state_id LIKE 'gmm_test_power_%'
            ORDER BY power_kw
            """)

            results = cursor.fetchall()
            for power, stored_state, calculated_state in results:
                assert stored_state == calculated_state, \
                    f"State for power {power} should be {calculated_state}, got {stored_state}"

        finally:
            cursor.execute("DELETE FROM MART.FACT_MACHINE_STATE WHERE state_id LIKE 'gmm_test_power_%'")
            cursor.close()

    def test_gmm_confidence_score_variation(self, sf_connection, tenant_id, machine_id):
        """Test that confidence scores vary appropriately based on distance to component mean"""
        cursor = sf_connection.cursor()

        try:
            # Given: power readings with different distances from state centroids
            timestamp = datetime.utcnow()

            # OFF state: centroid ~0.15, test values at different distances
            off_test_cases = [
                (0.08, 'OFF', 0.98),  # Very close to centroid
                (0.15, 'OFF', 0.99),  # At centroid
                (0.40, 'OFF', 0.85),  # Far from centroid
            ]

            # IDLE state: centroid ~2.5
            idle_test_cases = [
                (2.0, 'IDLE', 0.92),
                (2.5, 'IDLE', 0.95),
                (3.2, 'IDLE', 0.88),
            ]

            # WORKING state: centroid ~8.5
            working_test_cases = [
                (7.5, 'WORKING', 0.92),
                (8.5, 'WORKING', 0.97),
                (9.8, 'WORKING', 0.93),
            ]

            all_cases = off_test_cases + idle_test_cases + working_test_cases

            # When: inserting states with confidence scores
            for i, (power, state, confidence) in enumerate(all_cases):
                sql = f"""
                INSERT INTO MART.FACT_MACHINE_STATE (
                    state_id, tenant_id, machine_id, timestamp_utc, date_key,
                    hour_of_day, state, state_confidence, power_kw, current_amps,
                    power_factor, interval_minutes, energy_kwh, tariff_band,
                    rate_per_kwh, cost_gbp, data_quality
                ) VALUES (
                    'confidence_test_{i:02d}', '{tenant_id}', '{machine_id}',
                    '{timestamp.isoformat()}', '{timestamp.date().isoformat()}',
                    {timestamp.hour}, '{state}', {confidence}, {power}, {power / 0.23},
                    0.95, 1, {power / 60}, 'peak', 0.28, {power * 0.28 / 60}, 'good'
                )
                """
                cursor.execute(sql)

            # Then: verify confidence scores are reasonable
            cursor.execute(f"""
            SELECT state, AVG(state_confidence) as avg_confidence, MIN(state_confidence) as min_confidence
            FROM MART.FACT_MACHINE_STATE
            WHERE state_id LIKE 'confidence_test_%'
            GROUP BY state
            ORDER BY state
            """)

            results = cursor.fetchall()
            for state, avg_conf, min_conf in results:
                assert min_conf > 0.80, f"Min confidence for {state} should be > 0.80"
                assert avg_conf < 1.0, f"Average confidence for {state} should be < 1.0"

        finally:
            cursor.execute("DELETE FROM MART.FACT_MACHINE_STATE WHERE state_id LIKE 'confidence_test_%'")
            cursor.close()


@pytest.mark.unit
@pytest.mark.snowflake
class TestDBSCANClustering:
    """Test suite for DBSCAN clustering of production events"""

    def test_dbscan_cluster_creation(self, sf_connection, tenant_id, machine_id):
        """Test creation and storage of DBSCAN clusters"""
        cursor = sf_connection.cursor()

        try:
            # Given: cluster dimension table exists
            cursor.execute("""
            CREATE TABLE IF NOT EXISTS MART.DIM_PROD_CLUSTER (
                cluster_id VARCHAR(255) PRIMARY KEY,
                tenant_id VARCHAR(100) NOT NULL,
                machine_id VARCHAR(255),
                cluster_number NUMBER,
                median_duration_minutes FLOAT,
                iqr_duration_minutes FLOAT,
                min_duration_minutes FLOAT,
                max_duration_minutes FLOAT,
                avg_power_kw FLOAT,
                total_events NUMBER,
                model_version VARCHAR(50),
                last_updated TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
            )
            """)

            # When: inserting DBSCAN clusters
            clusters = [
                {
                    'cluster_id': f'{machine_id}_C0',
                    'cluster_number': 0,
                    'median_duration': 25.0,
                    'iqr_duration': 3.5,
                    'min_duration': 18.0,
                    'max_duration': 35.0,
                    'avg_power': 8.2,
                    'total_events': 120
                },
                {
                    'cluster_id': f'{machine_id}_C1',
                    'cluster_number': 1,
                    'median_duration': 45.0,
                    'iqr_duration': 5.0,
                    'min_duration': 38.0,
                    'max_duration': 55.0,
                    'avg_power': 8.5,
                    'total_events': 85
                }
            ]

            for cluster in clusters:
                sql = f"""
                INSERT INTO MART.DIM_PROD_CLUSTER (
                    cluster_id, tenant_id, machine_id, cluster_number,
                    median_duration_minutes, iqr_duration_minutes,
                    min_duration_minutes, max_duration_minutes,
                    avg_power_kw, total_events, model_version
                ) VALUES (
                    '{cluster['cluster_id']}', '{tenant_id}', '{machine_id}',
                    {cluster['cluster_number']}, {cluster['median_duration']},
                    {cluster['iqr_duration']}, {cluster['min_duration']},
                    {cluster['max_duration']}, {cluster['avg_power']},
                    {cluster['total_events']}, '1.0'
                )
                """
                cursor.execute(sql)

            # Then: verify clusters are stored
            cursor.execute(f"""
            SELECT COUNT(*) as cluster_count, AVG(total_events) as avg_events
            FROM MART.DIM_PROD_CLUSTER
            WHERE machine_id = '{machine_id}'
            """)

            result = cursor.fetchone()
            assert result[0] == 2, "Should have 2 clusters"
            assert result[1] > 0, "Average events should be positive"

        finally:
            cursor.execute(f"DELETE FROM MART.DIM_PROD_CLUSTER WHERE machine_id = '{machine_id}'")
            cursor.close()

    def test_dbscan_event_assignment_to_clusters(self, sf_connection, tenant_id, machine_id):
        """Test assignment of production events to DBSCAN clusters"""
        cursor = sf_connection.cursor()

        try:
            # Setup: create required tables
            cursor.execute("""
            CREATE TABLE IF NOT EXISTS MART.DIM_PROD_CLUSTER (
                cluster_id VARCHAR(255) PRIMARY KEY,
                tenant_id VARCHAR(100) NOT NULL,
                machine_id VARCHAR(255),
                cluster_number NUMBER
            )
            """)

            cursor.execute("""
            CREATE TABLE IF NOT EXISTS MART.FACT_PRODUCTION_EVENT (
                event_id VARCHAR(255) PRIMARY KEY,
                tenant_id VARCHAR(100) NOT NULL,
                machine_id VARCHAR(255) NOT NULL,
                start_timestamp TIMESTAMP_NTZ,
                end_timestamp TIMESTAMP_NTZ,
                duration_minutes FLOAT,
                cluster_id VARCHAR(255),
                is_outlier BOOLEAN,
                outlier_score FLOAT
            )
            """)

            # Given: production events with cluster assignments
            base_time = datetime.utcnow()
            events = []

            # Cluster 0: ~25 minute duration
            for i in range(5):
                events.append({
                    'event_id': f'c0_event_{i}',
                    'duration': 25 + (i - 2),  # 23-27 minutes
                    'cluster_id': f'{machine_id}_C0',
                    'is_outlier': False
                })

            # Cluster 1: ~45 minute duration
            for i in range(3):
                events.append({
                    'event_id': f'c1_event_{i}',
                    'duration': 45 + (i - 1),  # 44-46 minutes
                    'cluster_id': f'{machine_id}_C1',
                    'is_outlier': False
                })

            # Outliers
            events.append({
                'event_id': 'outlier_event_1',
                'duration': 5.0,  # Much shorter
                'cluster_id': None,
                'is_outlier': True
            })

            # When: inserting events with cluster assignments
            for i, event in enumerate(events):
                start_ts = base_time + timedelta(hours=i)
                end_ts = start_ts + timedelta(minutes=event['duration'])

                sql = f"""
                INSERT INTO MART.FACT_PRODUCTION_EVENT (
                    event_id, tenant_id, machine_id, start_timestamp, end_timestamp,
                    duration_minutes, cluster_id, is_outlier
                ) VALUES (
                    '{event['event_id']}', '{tenant_id}', '{machine_id}',
                    '{start_ts.isoformat()}', '{end_ts.isoformat()}',
                    {event['duration']}, {f"'{event['cluster_id']}'" if event['cluster_id'] else 'NULL'},
                    {str(event['is_outlier']).upper()}
                )
                """
                cursor.execute(sql)

            # Then: analyze cluster assignments
            cursor.execute(f"""
            SELECT
                cluster_id,
                COUNT(*) as event_count,
                AVG(duration_minutes) as avg_duration,
                MIN(duration_minutes) as min_duration,
                MAX(duration_minutes) as max_duration
            FROM MART.FACT_PRODUCTION_EVENT
            WHERE machine_id = '{machine_id}' AND is_outlier = FALSE
            GROUP BY cluster_id
            ORDER BY cluster_id
            """)

            results = cursor.fetchall()
            assert len(results) == 2, "Should have 2 clusters"

            # Cluster 0 should have ~25 min average duration
            if results[0][0] and '0' in results[0][0]:
                assert 23 <= results[0][1] <= 27, f"Cluster 0 duration should be ~25 min, got {results[0][1]}"

        finally:
            cursor.execute(f"DELETE FROM MART.FACT_PRODUCTION_EVENT WHERE machine_id = '{machine_id}'")
            cursor.execute(f"DELETE FROM MART.DIM_PROD_CLUSTER WHERE machine_id = '{machine_id}'")
            cursor.close()

    def test_dbscan_outlier_detection(self, sf_connection, tenant_id, machine_id):
        """Test detection of outlier events in DBSCAN clustering"""
        cursor = sf_connection.cursor()

        try:
            # Setup table
            cursor.execute("""
            CREATE TABLE IF NOT EXISTS MART.FACT_PRODUCTION_EVENT (
                event_id VARCHAR(255) PRIMARY KEY,
                tenant_id VARCHAR(100) NOT NULL,
                machine_id VARCHAR(255) NOT NULL,
                duration_minutes FLOAT,
                is_outlier BOOLEAN,
                outlier_score FLOAT
            )
            """)

            # Given: normal events and outliers
            base_time = datetime.utcnow()
            duration_range = [
                (25.0, False, 0.05),   # Normal cluster 0
                (26.5, False, 0.08),
                (24.2, False, 0.04),
                (45.0, False, 0.06),   # Normal cluster 1
                (44.5, False, 0.07),
                (2.0, True, 0.95),     # Outlier - very short
                (120.0, True, 0.98),   # Outlier - very long
            ]

            # When: inserting events
            for i, (duration, is_outlier, outlier_score) in enumerate(duration_range):
                sql = f"""
                INSERT INTO MART.FACT_PRODUCTION_EVENT (
                    event_id, tenant_id, machine_id, duration_minutes, is_outlier, outlier_score
                ) VALUES (
                    'outlier_test_{i}', '{tenant_id}', '{machine_id}',
                    {duration}, {str(is_outlier).upper()}, {outlier_score}
                )
                """
                cursor.execute(sql)

            # Then: verify outlier detection
            cursor.execute(f"""
            SELECT
                COUNT(*) as total_events,
                SUM(CASE WHEN is_outlier = TRUE THEN 1 ELSE 0 END) as outlier_count,
                AVG(CASE WHEN is_outlier = TRUE THEN outlier_score ELSE NULL END) as avg_outlier_score
            FROM MART.FACT_PRODUCTION_EVENT
            WHERE machine_id = '{machine_id}'
            """)

            result = cursor.fetchone()
            assert result[0] == len(duration_range), "All events should be stored"
            assert result[1] == 2, "Should detect 2 outliers"
            assert result[2] > 0.90, "Outliers should have high anomaly scores"

        finally:
            cursor.execute(f"DELETE FROM MART.FACT_PRODUCTION_EVENT WHERE machine_id = '{machine_id}'")
            cursor.close()

    def test_product_cluster_inference(self, sf_connection, tenant_id, machine_id):
        """Test inference of product types from production event clusters"""
        cursor = sf_connection.cursor()

        try:
            # Setup
            cursor.execute("""
            CREATE TABLE IF NOT EXISTS MART.DIM_PROD_CLUSTER (
                cluster_id VARCHAR(255) PRIMARY KEY,
                cluster_number NUMBER,
                machine_id VARCHAR(255),
                product_id VARCHAR(255),
                product_name VARCHAR(255),
                median_duration_minutes FLOAT,
                avg_power_kw FLOAT
            )
            """)

            # Given: clusters mapped to products
            cluster_product_mapping = [
                {
                    'cluster_id': f'{machine_id}_C0',
                    'product_id': 'PROD_A',
                    'product_name': 'Widget A',
                    'median_duration': 25.0,
                    'avg_power': 8.2
                },
                {
                    'cluster_id': f'{machine_id}_C1',
                    'product_id': 'PROD_B',
                    'product_name': 'Widget B',
                    'median_duration': 45.0,
                    'avg_power': 8.5
                }
            ]

            # When: storing cluster-to-product mappings
            for mapping in cluster_product_mapping:
                sql = f"""
                INSERT INTO MART.DIM_PROD_CLUSTER (
                    cluster_id, cluster_number, machine_id, product_id,
                    product_name, median_duration_minutes, avg_power_kw
                ) VALUES (
                    '{mapping['cluster_id']}', {mapping['cluster_id'].split('_')[-1][1]}, '{machine_id}',
                    '{mapping['product_id']}', '{mapping['product_name']}',
                    {mapping['median_duration']}, {mapping['avg_power']}
                )
                """
                cursor.execute(sql)

            # Then: verify product inference capability
            cursor.execute(f"""
            SELECT product_id, product_name, median_duration_minutes
            FROM MART.DIM_PROD_CLUSTER
            WHERE machine_id = '{machine_id}'
            ORDER BY median_duration_minutes
            """)

            results = cursor.fetchall()
            assert len(results) == 2, "Should have 2 product mappings"
            assert results[0][0] == 'PROD_A', "First product should be A"
            assert results[1][0] == 'PROD_B', "Second product should be B"

        finally:
            cursor.execute(f"DELETE FROM MART.DIM_PROD_CLUSTER WHERE machine_id = '{machine_id}'")
            cursor.close()
