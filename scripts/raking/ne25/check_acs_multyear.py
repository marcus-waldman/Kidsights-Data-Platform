#!/usr/bin/env python3
"""Check MULTYEAR variable in ACS data"""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent))

from python.db.connection import DatabaseManager

db = DatabaseManager()

print("[INFO] Checking MULTYEAR variable in ACS data...")

with db.get_connection() as conn:
    # Check if MULTYEAR exists
    vars_query = """
    SELECT COLUMN_NAME 
    FROM (DESCRIBE acs_data)
    WHERE COLUMN_NAME = 'MULTYEAR'
    """
    has_multyear = conn.execute(vars_query).fetchone()
    
    if has_multyear:
        print(f"[OK] MULTYEAR variable found")
        
        # Check MULTYEAR distribution for Nebraska children 0-5
        query = """
        SELECT 
            MULTYEAR,
            COUNT(*) as n,
            MIN(YEAR) as sample_year
        FROM acs_data
        WHERE STATEFIP = 31 AND AGE <= 5
        GROUP BY MULTYEAR, YEAR
        ORDER BY MULTYEAR
        """
        
        print(f"\n[INFO] MULTYEAR distribution (Nebraska children ages 0-5):")
        print(f"  MULTYEAR | Sample Year | Count")
        print(f"  ---------|-------------|-------")
        
        total = 0
        for row in conn.execute(query).fetchall():
            print(f"  {row[0]:8} | {row[2]:11} | {row[1]:,}")
            total += row[1]
        
        print(f"\n[INFO] Total: {total:,} children across years")
        
        # Check year range
        year_range_query = """
        SELECT MIN(MULTYEAR) as min_year, MAX(MULTYEAR) as max_year
        FROM acs_data
        WHERE STATEFIP = 31 AND AGE <= 5
        """
        year_range = conn.execute(year_range_query).fetchone()
        print(f"[INFO] MULTYEAR range: {year_range[0]}-{year_range[1]}")
        
    else:
        print(f"[ERROR] MULTYEAR variable not found")
        print(f"[INFO] Available year-related columns:")
        year_cols_query = """
        SELECT COLUMN_NAME 
        FROM (DESCRIBE acs_data)
        WHERE COLUMN_NAME LIKE '%YEAR%' OR COLUMN_NAME = 'YEAR'
        """
        for row in conn.execute(year_cols_query).fetchall():
            print(f"  - {row[0]}")

