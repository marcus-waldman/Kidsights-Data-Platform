#!/usr/bin/env python3
"""Check NSCH data for raking targets"""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent))

from python.db.connection import DatabaseManager

db = DatabaseManager()

print("[INFO] Checking NSCH data for Nebraska children ages 0-5...\n")

with db.get_connection() as conn:
    # Check for NSCH tables
    tables = conn.execute("SHOW TABLES").fetchall()
    nsch_tables = [t[0] for t in tables if 'nsch' in t[0].lower()]
    
    print(f"[INFO] NSCH tables: {nsch_tables}\n")
    
    if not nsch_tables:
        print("[ERROR] No NSCH tables found")
    else:
        # Check 2023 data
        for table in nsch_tables:
            if '2023' in table or table == 'nsch_raw':
                print(f"[INFO] Checking table: {table}")
                
                # Check Nebraska children 0-5
                query = f"""
                SELECT COUNT(*) 
                FROM {table}
                WHERE FIPSST = 31 AND SC_AGE_YEARS <= 5
                """
                try:
                    count = conn.execute(query).fetchone()[0]
                    print(f"  Nebraska children 0-5: {count:,}\n")
                    
                    # Check for key variables
                    key_vars = ['ACE1more_23', 'MEDB10ScrQ5_23', 'K2Q01', 'SC_SEX']
                    cols = conn.execute(f"DESCRIBE {table}").fetchall()
                    col_names = [c[0] for c in cols]
                    
                    print(f"  Key variables:")
                    for var in key_vars:
                        status = "[OK]" if var in col_names else "[MISSING]"
                        print(f"    {status} {var}")
                    
                except Exception as e:
                    print(f"  Error: {e}")

