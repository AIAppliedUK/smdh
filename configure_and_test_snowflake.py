#!/usr/bin/env python3
"""
Interactive script to configure Snowflake credentials and run tests
"""

import os
import sys
import subprocess
from pathlib import Path
from getpass import getpass

def test_snowflake_connection(account, user, password, database, warehouse):
    """Test Snowflake connection"""
    try:
        import snowflake.connector
        
        print("\n📡 Testing Snowflake connection...")
        print(f"   Account: {account}")
        print(f"   User: {user}")
        print(f"   Database: {database}")
        print(f"   Warehouse: {warehouse}")
        
        conn = snowflake.connector.connect(
            account=account,
            user=user,
            password=password,
            database=database,
            warehouse=warehouse
        )
        
        cursor = conn.cursor()
        cursor.execute("SELECT 1 AS test")
        result = cursor.fetchone()
        cursor.close()
        conn.close()
        
        return True, "✅ Connection successful"
    except Exception as e:
        return False, f"❌ Connection failed: {str(e)}"

def get_credentials():
    """Get Snowflake credentials from environment or user input"""
    
    # Check environment variables first
    account = os.getenv('SNOWFLAKE_ACCOUNT', 'qqoylnv-zy42691')
    user = os.getenv('SNOWFLAKE_USER', 'AIAPPLIED')
    password = os.getenv('SNOWFLAKE_PASSWORD', '')
    database = os.getenv('SNOWFLAKE_DATABASE', 'SMDH_TEST')
    warehouse = os.getenv('SNOWFLAKE_WAREHOUSE', 'SMDH_TEST_WH')
    
    print("\n" + "="*60)
    print("SMDH Snowflake Configuration")
    print("="*60)
    print("\nCurrent settings:")
    print(f"  Account:   {account}")
    print(f"  User:      {user}")
    print(f"  Database:  {database}")
    print(f"  Warehouse: {warehouse}")
    
    if password:
        print(f"  Password:  [SET from environment] (length: {len(password)})")
    else:
        print(f"  Password:  [NOT SET]")
    
    # If password is not set, prompt for it
    if not password:
        print("\n⚠️  Password required to proceed with testing")
        password = getpass("Enter Snowflake password for AIAPPLIED: ")
    
    if not password:
        print("❌ Password cannot be empty")
        return None
    
    return {
        'account': account,
        'user': user,
        'password': password,
        'database': database,
        'warehouse': warehouse
    }

def retrieve_database_tables(creds):
    """Retrieve and display available tables"""
    try:
        import snowflake.connector
        
        print("\n" + "="*60)
        print("Retrieving Database Tables")
        print("="*60)
        
        conn = snowflake.connector.connect(**creds)
        cursor = conn.cursor()
        
        # Check if database exists
        cursor.execute(f"SHOW DATABASES LIKE '{creds['database']}'")
        db_exists = cursor.fetchall()
        
        if not db_exists:
            print(f"⚠️  Database '{creds['database']}' not found")
            print("   Available SMDH databases:")
            cursor.execute("SHOW DATABASES LIKE 'SMDH%'")
            databases = cursor.fetchall()
            if databases:
                for db in databases:
                    print(f"   - {db[1]}")
            cursor.close()
            conn.close()
            return False
        
        print(f"\n✅ Database '{creds['database']}' found")
        
        # Switch to database and list tables
        cursor.execute(f"USE DATABASE {creds['database']}")
        
        # Get all schemas
        cursor.execute(f"SHOW SCHEMAS IN DATABASE {creds['database']}")
        schemas = cursor.fetchall()
        
        print(f"\n📋 Schemas in {creds['database']}:")
        for schema in schemas:
            schema_name = schema[1]
            if schema_name not in ['INFORMATION_SCHEMA']:
                cursor.execute(f"USE SCHEMA {creds['database']}.{schema_name}")
                cursor.execute("SHOW TABLES")
                tables = cursor.fetchall()
                
                if tables:
                    print(f"\n  {schema_name}/")
                    for table in tables:
                        print(f"    - {table[1]}")
                else:
                    print(f"\n  {schema_name}/ (empty)")
        
        # Check for required tables for unit tests
        print("\n" + "="*60)
        print("Checking for Required Test Tables")
        print("="*60)
        
        required_tables = [
            ('RAW', 'CLAMP_SENSOR_READINGS'),
            ('NORMALIZED', 'POWER_METRICS'),
            ('MART', 'FACT_MACHINE_STATE'),
            ('MART', 'FACT_PRODUCTION_EVENT'),
        ]
        
        cursor.execute(f"USE DATABASE {creds['database']}")
        
        all_exist = True
        for schema, table in required_tables:
            try:
                cursor.execute(f"SELECT COUNT(*) FROM {creds['database']}.{schema}.{table}")
                count = cursor.fetchone()
                print(f"✅ {schema}.{table} - EXISTS (rows: {count[0] if count else 0})")
            except:
                print(f"❌ {schema}.{table} - NOT FOUND")
                all_exist = False
        
        cursor.close()
        conn.close()
        
        return all_exist
        
    except Exception as e:
        print(f"❌ Error retrieving tables: {e}")
        return False

def run_tests():
    """Run the pytest tests"""
    print("\n" + "="*60)
    print("Running Snowflake Unit Tests")
    print("="*60)
    
    result = subprocess.run(
        ['pytest', 'tests/unit/test_power_calculations.py', '-v'],
        cwd='/Users/david/projects/smdh'
    )
    
    return result.returncode == 0

def main():
    """Main entry point"""
    
    # Get credentials
    creds = get_credentials()
    if not creds:
        sys.exit(1)
    
    # Test connection
    success, message = test_snowflake_connection(**creds)
    print(f"\n{message}")
    
    if not success:
        sys.exit(1)
    
    # Set environment variables for subprocess
    os.environ['SNOWFLAKE_ACCOUNT'] = creds['account']
    os.environ['SNOWFLAKE_USER'] = creds['user']
    os.environ['SNOWFLAKE_PASSWORD'] = creds['password']
    os.environ['SNOWFLAKE_DATABASE'] = creds['database']
    os.environ['SNOWFLAKE_WAREHOUSE'] = creds['warehouse']
    
    # Retrieve tables
    tables_ok = retrieve_database_tables(creds)
    
    if not tables_ok:
        print("\n⚠️  Some required tables not found")
        print("   You may need to create the Snowflake database schema first")
        print("   Run: cd infrastructure/snowflake && ./validate_setup.sh test_tenant")
    
    # Ask if user wants to run tests
    print("\n" + "="*60)
    if tables_ok:
        print("✅ All required tables found. Ready to run tests.")
    else:
        print("⚠️  Missing some tables, but proceeding with tests...")
    
    print("\nRun tests? (y/n) [y]: ", end='', flush=True)
    response = input().strip().lower()
    
    if response != 'n':
        print()
        tests_passed = run_tests()
        
        if tests_passed:
            print("\n" + "="*60)
            print("✅ ALL TESTS PASSED!")
            print("="*60)
        else:
            print("\n" + "="*60)
            print("❌ SOME TESTS FAILED")
            print("="*60)
    
    print("\nConfiguration saved for this session.")
    print("To make permanent, run:")
    print("  ./setup_snowflake_env.sh")

if __name__ == '__main__':
    main()
