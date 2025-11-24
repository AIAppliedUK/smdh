#!/usr/bin/env python3
"""
SMDH Data Flow Validation Script
Validates that data is flowing correctly from IoT Core to Kinesis and beyond
"""

import json
import time
import boto3
import argparse
from datetime import datetime, timedelta
from collections import defaultdict
import hashlib
import logging
from tabulate import tabulate

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class DataFlowValidator:
    def __init__(self, region, kinesis_stream_name):
        """Initialize the validator with AWS clients"""
        self.region = region
        self.kinesis_stream_name = kinesis_stream_name

        # Initialize AWS clients
        self.iot_client = boto3.client('iot', region_name=region)
        self.iot_data_client = boto3.client('iot-data', region_name=region)
        self.kinesis_client = boto3.client('kinesis', region_name=region)
        self.cloudwatch_client = boto3.client('cloudwatch', region_name=region)

        # Track messages for validation
        self.sent_messages = {}
        self.received_messages = {}
        self.validation_results = defaultdict(dict)

    def get_iot_endpoint(self):
        """Get the IoT endpoint for the region"""
        response = self.iot_client.describe_endpoint(endpointType='iot:Data-ATS')
        return response['endpointAddress']

    def publish_test_message(self, tenant_id, site_id, message_id=None):
        """Publish a test message to IoT Core"""
        if not message_id:
            message_id = f"test_{int(time.time() * 1000)}"

        topic = f"smdh/{tenant_id}/{site_id}/sensor-data"

        payload = {
            "messageId": message_id,
            "timestamp": datetime.utcnow().isoformat() + 'Z',
            "tenantId": tenant_id,
            "siteId": site_id,
            "deviceType": "validation_test",
            "testMarker": hashlib.md5(message_id.encode()).hexdigest()[:8],
            "measurements": {
                "testValue": 42.0,
                "sequenceNumber": len(self.sent_messages) + 1
            }
        }

        try:
            self.iot_data_client.publish(
                topic=topic,
                qos=1,
                payload=json.dumps(payload)
            )

            self.sent_messages[message_id] = {
                "payload": payload,
                "topic": topic,
                "sent_at": datetime.utcnow()
            }

            logger.info(f"✅ Published test message: {message_id} to {topic}")
            return True

        except Exception as e:
            logger.error(f"❌ Failed to publish message: {e}")
            return False

    def check_kinesis_records(self, duration_seconds=60, max_records=100):
        """Check Kinesis stream for received messages"""
        logger.info(f"🔍 Checking Kinesis stream: {self.kinesis_stream_name}")

        try:
            # Get stream description
            stream_desc = self.kinesis_client.describe_stream(
                StreamName=self.kinesis_stream_name
            )

            shard_ids = [shard['ShardId'] for shard in stream_desc['StreamDescription']['Shards']]

            all_records = []

            for shard_id in shard_ids:
                # Get shard iterator from TRIM_HORIZON or timestamp
                iterator_response = self.kinesis_client.get_shard_iterator(
                    StreamName=self.kinesis_stream_name,
                    ShardId=shard_id,
                    ShardIteratorType='AT_TIMESTAMP',
                    Timestamp=datetime.utcnow() - timedelta(seconds=duration_seconds)
                )

                shard_iterator = iterator_response['ShardIterator']

                # Read records from the shard
                while shard_iterator:
                    try:
                        response = self.kinesis_client.get_records(
                            ShardIterator=shard_iterator,
                            Limit=max_records
                        )

                        records = response.get('Records', [])
                        all_records.extend(records)

                        # Check for our test messages
                        for record in records:
                            try:
                                data = json.loads(record['Data'])
                                if 'messageId' in data and data['messageId'] in self.sent_messages:
                                    self.received_messages[data['messageId']] = {
                                        "data": data,
                                        "received_at": datetime.utcnow(),
                                        "shard_id": shard_id,
                                        "sequence_number": record['SequenceNumber']
                                    }
                                    logger.info(f"✅ Found message in Kinesis: {data['messageId']}")
                            except json.JSONDecodeError:
                                continue

                        shard_iterator = response.get('NextShardIterator')

                        if not records:
                            break

                    except Exception as e:
                        logger.error(f"Error reading from shard {shard_id}: {e}")
                        break

            logger.info(f"📊 Total records read from Kinesis: {len(all_records)}")
            return all_records

        except Exception as e:
            logger.error(f"❌ Error checking Kinesis: {e}")
            return []

    def check_cloudwatch_metrics(self, tenant_id=None):
        """Check CloudWatch metrics for IoT and Kinesis"""
        logger.info("📈 Checking CloudWatch metrics...")

        metrics_to_check = [
            {
                'namespace': 'AWS/IoT',
                'metric': 'PublishIn.Success',
                'stat': 'Sum',
                'label': 'IoT Messages Published'
            },
            {
                'namespace': 'AWS/IoT',
                'metric': 'RuleMessageThrottled',
                'stat': 'Sum',
                'label': 'IoT Rules Throttled'
            },
            {
                'namespace': 'AWS/Kinesis',
                'metric': 'IncomingRecords',
                'stat': 'Sum',
                'label': 'Kinesis Incoming Records',
                'dimensions': [{'Name': 'StreamName', 'Value': self.kinesis_stream_name}]
            },
            {
                'namespace': 'AWS/Kinesis',
                'metric': 'GetRecords.Success',
                'stat': 'Sum',
                'label': 'Kinesis GetRecords Success',
                'dimensions': [{'Name': 'StreamName', 'Value': self.kinesis_stream_name}]
            }
        ]

        end_time = datetime.utcnow()
        start_time = end_time - timedelta(minutes=10)

        metric_results = []

        for metric_config in metrics_to_check:
            try:
                dimensions = metric_config.get('dimensions', [])

                response = self.cloudwatch_client.get_metric_statistics(
                    Namespace=metric_config['namespace'],
                    MetricName=metric_config['metric'],
                    Dimensions=dimensions,
                    StartTime=start_time,
                    EndTime=end_time,
                    Period=300,  # 5 minutes
                    Statistics=[metric_config['stat']]
                )

                if response['Datapoints']:
                    latest_point = sorted(response['Datapoints'], key=lambda x: x['Timestamp'])[-1]
                    value = latest_point[metric_config['stat']]
                    metric_results.append({
                        'Metric': metric_config['label'],
                        'Value': value,
                        'Timestamp': latest_point['Timestamp'].strftime('%H:%M:%S')
                    })
                else:
                    metric_results.append({
                        'Metric': metric_config['label'],
                        'Value': 'No data',
                        'Timestamp': 'N/A'
                    })

            except Exception as e:
                logger.error(f"Error fetching metric {metric_config['metric']}: {e}")
                metric_results.append({
                    'Metric': metric_config['label'],
                    'Value': 'Error',
                    'Timestamp': 'N/A'
                })

        return metric_results

    def validate_iot_rules(self, tenant_id):
        """Validate IoT Rules are configured correctly"""
        logger.info(f"🔧 Validating IoT Rules for tenant: {tenant_id}")

        rule_name = f"smdh_route_{tenant_id.replace('-', '_')}"

        try:
            response = self.iot_client.get_topic_rule(ruleName=rule_name)
            rule = response['rule']

            validation = {
                'exists': True,
                'enabled': not rule['ruleDisabled'],
                'sql': rule['sql'],
                'actions': []
            }

            # Check if Kinesis action is configured
            for action in rule.get('actions', []):
                if 'kinesis' in action:
                    kinesis_action = action['kinesis']
                    validation['actions'].append({
                        'type': 'kinesis',
                        'stream': kinesis_action['streamName'],
                        'partition_key': kinesis_action.get('partitionKey', 'N/A')
                    })

                    # Verify the stream name matches
                    if kinesis_action['streamName'] == self.kinesis_stream_name:
                        logger.info(f"✅ Rule correctly targets Kinesis stream: {self.kinesis_stream_name}")
                    else:
                        logger.warning(f"⚠️ Rule targets different stream: {kinesis_action['streamName']}")

            # Check error action
            if 'errorAction' in rule:
                if 'republish' in rule['errorAction']:
                    error_topic = rule['errorAction']['republish']['topic']
                    validation['error_handling'] = f"Republish to {error_topic}"
                    logger.info(f"✅ Error handling configured: {error_topic}")

            return validation

        except self.iot_client.exceptions.ResourceNotFoundException:
            logger.error(f"❌ IoT Rule not found: {rule_name}")
            return {'exists': False}
        except Exception as e:
            logger.error(f"❌ Error validating IoT rule: {e}")
            return {'error': str(e)}

    def run_end_to_end_test(self, tenant_id, site_id, num_messages=5, wait_time=30):
        """Run a complete end-to-end validation test"""
        logger.info("=" * 60)
        logger.info("🚀 Starting End-to-End Data Flow Validation")
        logger.info("=" * 60)

        # Step 1: Validate IoT Rule
        logger.info("\n📋 Step 1: Validating IoT Rule Configuration")
        rule_validation = self.validate_iot_rules(tenant_id)

        if not rule_validation.get('exists'):
            logger.error("❌ IoT Rule does not exist. Cannot proceed with test.")
            return False

        if not rule_validation.get('enabled'):
            logger.error("❌ IoT Rule is disabled. Cannot proceed with test.")
            return False

        # Step 2: Send test messages
        logger.info(f"\n📤 Step 2: Sending {num_messages} test messages")
        message_ids = []

        for i in range(num_messages):
            message_id = f"e2e_test_{int(time.time() * 1000)}_{i}"
            if self.publish_test_message(tenant_id, site_id, message_id):
                message_ids.append(message_id)
            time.sleep(1)  # Small delay between messages

        logger.info(f"✅ Sent {len(message_ids)} messages successfully")

        # Step 3: Wait for processing
        logger.info(f"\n⏱️ Step 3: Waiting {wait_time} seconds for processing...")
        time.sleep(wait_time)

        # Step 4: Check Kinesis for messages
        logger.info("\n🔍 Step 4: Checking Kinesis Stream")
        self.check_kinesis_records(duration_seconds=wait_time + 10)

        # Step 5: Analyze results
        logger.info("\n📊 Step 5: Analyzing Results")

        results = []
        for message_id in message_ids:
            sent_info = self.sent_messages.get(message_id, {})
            received_info = self.received_messages.get(message_id)

            if received_info:
                latency = (received_info['received_at'] - sent_info['sent_at']).total_seconds()
                status = '✅ Success'
            else:
                latency = 'N/A'
                status = '❌ Not Found'

            results.append({
                'Message ID': message_id[-10:],  # Last 10 chars for readability
                'Status': status,
                'Latency (s)': latency if latency != 'N/A' else 'N/A'
            })

        # Display results table
        print("\n" + "=" * 60)
        print("📋 TEST RESULTS")
        print("=" * 60)
        print(tabulate(results, headers='keys', tablefmt='grid'))

        # Calculate success rate
        success_count = sum(1 for r in results if '✅' in r['Status'])
        success_rate = (success_count / len(results)) * 100 if results else 0

        print(f"\n✨ Success Rate: {success_rate:.1f}% ({success_count}/{len(results)})")

        # Step 6: Check CloudWatch metrics
        logger.info("\n📈 Step 6: CloudWatch Metrics")
        metrics = self.check_cloudwatch_metrics(tenant_id)

        if metrics:
            print("\n" + tabulate(metrics, headers='keys', tablefmt='grid'))

        return success_rate == 100

    def continuous_monitor(self, tenant_id, site_id, duration_minutes=5, interval_seconds=30):
        """Continuously monitor data flow for a specified duration"""
        logger.info(f"🔄 Starting continuous monitoring for {duration_minutes} minutes")

        end_time = datetime.utcnow() + timedelta(minutes=duration_minutes)
        iteration = 0

        while datetime.utcnow() < end_time:
            iteration += 1
            logger.info(f"\n--- Iteration {iteration} ---")

            # Send a test message
            message_id = f"monitor_{iteration}_{int(time.time() * 1000)}"
            self.publish_test_message(tenant_id, site_id, message_id)

            # Wait a bit
            time.sleep(10)

            # Check if it arrived
            self.check_kinesis_records(duration_seconds=20, max_records=10)

            # Report status
            if message_id in self.received_messages:
                logger.info(f"✅ Message {message_id} confirmed in Kinesis")
            else:
                logger.warning(f"⚠️ Message {message_id} not found yet")

            # Check metrics periodically
            if iteration % 3 == 0:
                metrics = self.check_cloudwatch_metrics(tenant_id)
                logger.info("Current metrics:")
                for metric in metrics:
                    logger.info(f"  {metric['Metric']}: {metric['Value']}")

            # Wait before next iteration
            remaining_time = (end_time - datetime.utcnow()).total_seconds()
            if remaining_time > interval_seconds:
                time.sleep(interval_seconds)

        # Final summary
        logger.info("\n" + "=" * 60)
        logger.info("📊 MONITORING SUMMARY")
        logger.info("=" * 60)
        logger.info(f"Total messages sent: {len(self.sent_messages)}")
        logger.info(f"Total messages received: {len(self.received_messages)}")
        success_rate = (len(self.received_messages) / len(self.sent_messages)) * 100 if self.sent_messages else 0
        logger.info(f"Success rate: {success_rate:.1f}%")

def main():
    parser = argparse.ArgumentParser(description='SMDH Data Flow Validator')
    parser.add_argument('--region', default='eu-west-1', help='AWS region')
    parser.add_argument('--stream', required=True, help='Kinesis stream name')
    parser.add_argument('--tenant', required=True, help='Tenant ID')
    parser.add_argument('--site', default='site_001', help='Site ID')
    parser.add_argument('--mode', default='test',
                       choices=['test', 'monitor', 'metrics'],
                       help='Validation mode')
    parser.add_argument('--messages', type=int, default=5,
                       help='Number of test messages (for test mode)')
    parser.add_argument('--duration', type=int, default=5,
                       help='Duration in minutes (for monitor mode)')
    parser.add_argument('--wait', type=int, default=30,
                       help='Wait time in seconds for messages to process')

    args = parser.parse_args()

    # Create validator
    validator = DataFlowValidator(args.region, args.stream)

    try:
        if args.mode == 'test':
            # Run end-to-end test
            success = validator.run_end_to_end_test(
                args.tenant,
                args.site,
                args.messages,
                args.wait
            )

            if success:
                logger.info("\n🎉 All tests passed!")
                return 0
            else:
                logger.warning("\n⚠️ Some tests failed. Check the results above.")
                return 1

        elif args.mode == 'monitor':
            # Continuous monitoring
            validator.continuous_monitor(
                args.tenant,
                args.site,
                args.duration,
                30  # Check every 30 seconds
            )
            return 0

        elif args.mode == 'metrics':
            # Just check metrics
            metrics = validator.check_cloudwatch_metrics(args.tenant)
            print(tabulate(metrics, headers='keys', tablefmt='grid'))
            return 0

    except KeyboardInterrupt:
        logger.info("\n⚠️ Validation interrupted by user")
        return 1
    except Exception as e:
        logger.error(f"❌ Validation failed: {e}")
        return 1

if __name__ == "__main__":
    exit(main())