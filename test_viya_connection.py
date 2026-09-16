#!/usr/bin/env python3
"""
Test Databricks connection through Viya/CAS
Reads credentials from .env
"""
import os
import sys
from dotenv import dotenv_values

# Load .env credentials
env = dotenv_values(".env")
os.environ["CAS_CLIENT_SSL_CA_LIST"] = env.get("CAS_CLIENT_SSL_CA_LIST", "")

try:
    import swat
    
    print("=" * 70)
    print("Testing Viya/CAS connection...")
    print("=" * 70)
    
    # Connect to CAS
    s = swat.CAS(
        env["SAS_VIYA_URL"], 
        password=env["SAS_VIYA_TOKEN"],
        ssl_ca_list=env.get("CAS_CLIENT_SSL_CA_LIST")
    )
    
    print(f"\n✓ Connected to CAS server: {s.get_connection_id()}")
    
    # List available CAS libraries
    print("\n" + "=" * 70)
    print("Available CAS Libraries:")
    print("=" * 70)
    
    lib_info = s.about()
    if hasattr(lib_info, 'LibPath'):
        print(lib_info.to_string())
    
    # Check DB_DEMO caslib
    print("\n" + "=" * 70)
    print("Checking DB_DEMO CAS Library:")
    print("=" * 70)
    
    try:
        tables = s.list_tables(caslib="DB_DEMO")
        print(f"\nTables in DB_DEMO caslib:")
        if hasattr(tables, 'TableInfo'):
            for idx, row in tables['TableInfo'].iterrows():
                print(f"  • {row.get('Name', 'Unknown')} ({row.get('Rows', 0)} rows)")
        else:
            print("  (No tables yet)")
    except Exception as e:
        print(f"  Note: DB_DEMO caslib may not exist yet: {e}")
    
    # Check for accessible caslibs
    print("\n" + "=" * 70)
    print("All Accessible CAS Libraries:")
    print("=" * 70)
    
    try:
        caslibs = s.list_caslibs()
        if hasattr(caslibs, 'CASLibInfo'):
            for idx, row in caslibs['CASLibInfo'].iterrows():
                caslib_name = row.get('CASLib', 'Unknown')
                print(f"\n  {caslib_name}:")
                try:
                    tables_in_lib = s.list_tables(caslib=caslib_name)
                    if hasattr(tables_in_lib, 'TableInfo'):
                        for t_idx, t_row in tables_in_lib['TableInfo'].iterrows():
                            table_name = t_row.get('Name', 'Unknown')
                            rows = t_row.get('Rows', 0)
                            print(f"    • {table_name} ({rows} rows)")
                except:
                    pass
    except Exception as e:
        print(f"  Error listing caslibs: {e}")
    
    print("\n" + "=" * 70)
    print("✓ Connection test complete")
    print("=" * 70)
    
    s.close()

except ModuleNotFoundError:
    print("ERROR: swat module not installed.")
    print("Install with: pip install swat")
    sys.exit(1)
except Exception as e:
    print(f"\nERROR: {type(e).__name__}: {e}")
    sys.exit(1)
