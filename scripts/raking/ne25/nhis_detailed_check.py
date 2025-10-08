#!/usr/bin/env python3
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent))

from python.db.connection import DatabaseManager

db = DatabaseManager()
print("[INFO] NHIS Data Verification for Raking Targets\n")

with db.get_connection() as conn:
    # Check North Central region
    print("[1] North Central Region (REGION = 2):")
    nc_count = conn.execute("""
        SELECT COUNT(*) FROM nhis_raw WHERE REGION = 2
    """).fetchone()[0]
    print(f"    Total records: {nc_count:,}\n")
    
    # Check PHQ-2 availability by year (should be 2019, 2022)
    print("[2] PHQ-2 Data (PHQINTR, PHQDEP):")
    phq_query = """
    SELECT YEAR, COUNT(*) as n
    FROM nhis_raw
    WHERE REGION = 2 
      AND PHQINTR IS NOT NULL 
      AND PHQDEP IS NOT NULL
    GROUP BY YEAR
    ORDER BY YEAR
    """
    print("    Year | Count")
    print("    -----|-------")
    for row in conn.execute(phq_query).fetchall():
        print(f"    {row[0]} | {row[1]:,}")
    
    # Check for ACE variables
    print("\n[3] ACE Variables:")
    ace_query = """
    SELECT COLUMN_NAME 
    FROM (DESCRIBE nhis_raw)
    WHERE COLUMN_NAME LIKE 'ACE%'
    ORDER BY COLUMN_NAME
    """
    ace_vars = [row[0] for row in conn.execute(ace_query).fetchall()]
    if ace_vars:
        print(f"    Found {len(ace_vars)} ACE variables: {', '.join(ace_vars[:5])}...")
    else:
        print("    [WARN] No ACE variables found")
    
    # Check for parent-child linkage variables
    print("\n[4] Household Linkage Variables:")
    link_vars = ['SERIAL', 'PERNUM', 'FAMID', 'RELATFAM', 'RELATED']
    for var in link_vars:
        check = conn.execute(f"""
            SELECT COLUMN_NAME FROM (DESCRIBE nhis_raw) WHERE COLUMN_NAME = '{var}'
        """).fetchone()
        status = "[OK]" if check else "[MISSING]"
        print(f"    {status} {var}")

