#!/usr/bin/env python3
"""
Verify ACS data availability for NE25 raking targets
Expected: Nebraska children ages 0-5, years 2019-2023
"""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent))

from python.db.connection import DatabaseManager

def verify_acs_data():
    db = DatabaseManager()

    # Check if ACS table exists
    table_names = db.list_tables()

    print("[INFO] Checking ACS data availability...")
    print(f"[INFO] Available tables: {len(table_names)}")

    acs_tables = [t for t in table_names if 'acs' in t.lower()]
    print(f"[INFO] ACS-related tables: {acs_tables}")

    if not acs_tables:
        print("[WARN] No ACS tables found in database")
        print("[INFO] Need to run ACS pipeline first")
        return False

    # Check the main ACS table
    with db.get_connection() as conn:
        for table in acs_tables:
            count_result = conn.execute(f"SELECT COUNT(*) FROM {table}").fetchone()
            print(f"[INFO] Table '{table}': {count_result[0]:,} records")

            # Show column info
            table_info = db.get_table_info(table)
            if table_info:
                print(f"[INFO] Columns in '{table}': {len(table_info['columns'])} columns")

    return True

if __name__ == "__main__":
    verify_acs_data()
