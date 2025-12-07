#!/bin/bash

# SMDH Snowflake Credentials Setup Script
# This script configures Snowflake credentials for unit tests

set -e

echo "═══════════════════════════════════════════════════════════════"
echo "SMDH - Snowflake Credentials Configuration"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# Display current configuration
echo "Current Snowflake Configuration:"
echo "  Account:   qqoylnv-zy42691"
echo "  Username:  AIAPPLIED"
echo "  Database:  SMDH_TEST"
echo "  Warehouse: SMDH_TEST_WH"
echo "  Region:    us-east-1"
echo ""

# Check if SNOWFLAKE_PASSWORD is already set
if [ -n "$SNOWFLAKE_PASSWORD" ]; then
    echo "✅ SNOWFLAKE_PASSWORD environment variable is already set"
    PASSWORD="$SNOWFLAKE_PASSWORD"
else
    # Prompt for password
    echo "Enter your Snowflake password for user AIAPPLIED:"
    read -s PASSWORD
    echo ""
fi

if [ -z "$PASSWORD" ]; then
    echo "❌ Error: Password cannot be empty"
    exit 1
fi

# Set environment variables
export SNOWFLAKE_ACCOUNT="qqoylnv-zy42691"
export SNOWFLAKE_USER="AIAPPLIED"
export SNOWFLAKE_PASSWORD="$PASSWORD"
export SNOWFLAKE_DATABASE="SMDH_TEST"
export SNOWFLAKE_WAREHOUSE="SMDH_TEST_WH"
export SNOWFLAKE_REGION="us-east-1"

echo "✅ Snowflake credentials configured"
echo ""
echo "Running diagnostic check..."
echo ""

# Test the connection using Python
python3 << PYTHON_EOF
import os
import sys

try:
    import snowflake.connector
    
    config = {
        'account': os.getenv('SNOWFLAKE_ACCOUNT'),
        'user': os.getenv('SNOWFLAKE_USER'),
        'password': os.getenv('SNOWFLAKE_PASSWORD'),
        'database': os.getenv('SNOWFLAKE_DATABASE'),
        'warehouse': os.getenv('SNOWFLAKE_WAREHOUSE'),
    }
    
    print(f"Attempting to connect to: {config['account']}")
    print(f"User: {config['user']}")
    print(f"Database: {config['database']}")
    print(f"Warehouse: {config['warehouse']}")
    print("")
    
    conn = snowflake.connector.connect(**config)
    cursor = conn.cursor()
    
    # Test basic query
    cursor.execute("SELECT 1 AS test_connection")
    result = cursor.fetchone()
    
    if result:
        print("✅ Successfully connected to Snowflake!")
        print(f"   Connection test result: {result[0]}")
    
    # Get available databases
    cursor.execute("SHOW DATABASES LIKE 'SMDH%'")
    databases = cursor.fetchall()
    
    if databases:
        print("\n✅ Available SMDH databases:")
        for db in databases:
            print(f"   - {db[1]}")  # Database name is in second column
    else:
        print("\n⚠️  No SMDH databases found")
    
    cursor.close()
    conn.close()
    
except ImportError:
    print("❌ snowflake-connector-python is not installed")
    print("   Install with: pip install snowflake-connector-python")
    sys.exit(1)
except Exception as e:
    print(f"❌ Connection failed: {e}")
    sys.exit(1)

PYTHON_EOF

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "Environment variables are now configured in this shell session."
echo ""
echo "Next steps:"
echo "1. To run the tests: pytest tests/unit/test_power_calculations.py -v"
echo "2. To verify databases: python3 -c \"import snowflake.connector; ...\""
echo ""
echo "Note: These environment variables are only set in this shell session."
echo "To make them permanent, add to your ~/.bashrc or ~/.zshrc:"
echo ""
echo "export SNOWFLAKE_ACCOUNT='qqoylnv-zy42691'"
echo "export SNOWFLAKE_USER='AIAPPLIED'"
echo "export SNOWFLAKE_PASSWORD='your_password'"
echo "export SNOWFLAKE_DATABASE='SMDH_TEST'"
echo "export SNOWFLAKE_WAREHOUSE='SMDH_TEST_WH'"
echo ""
echo "═══════════════════════════════════════════════════════════════"
