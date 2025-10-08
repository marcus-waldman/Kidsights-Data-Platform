#!/usr/bin/env python3
"""Check Nebraska ACS data for raking targets"""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent))

from python.db.connection import DatabaseManager

db = DatabaseManager()

print("[INFO] Checking Nebraska ACS data for children ages 0-5...")

with db.get_connection() as conn:
    # Check if Nebraska data exists and filter to children 0-5
    query = """
    SELECT 
        COUNT(*) as total_records,
        MIN(YEAR) as min_year,
        MAX(YEAR) as max_year,
        COUNT(DISTINCT YEAR) as n_years
    FROM acs_data
    WHERE STATEFIP = 31  -- Nebraska
      AND AGE <= 5       -- Children ages 0-5
    """
    result = conn.execute(query).fetchone()
    
    print(f"\n[INFO] Nebraska children ages 0-5:")
    print(f"  Total records: {result[0]:,}")
    print(f"  Year range: {result[1]}-{result[2]}")
    print(f"  Number of years: {result[3]}")
    
    # Check key variables exist
    print(f"\n[INFO] Checking key variables...")
    vars_query = """
    SELECT COLUMN_NAME 
    FROM (DESCRIBE acs_data)
    WHERE COLUMN_NAME IN ('SEX', 'RACE', 'HISPAN', 'POVERTY', 'PUMA', 'CLUSTER', 'STRATA', 'PERWT')
    """
    key_vars = [row[0] for row in conn.execute(vars_query).fetchall()]
    print(f"  Found key variables: {key_vars}")
    
    # Sample by year
    print(f"\n[INFO] Sample size by year:")
    year_query = """
    SELECT YEAR, COUNT(*) as n
    FROM acs_data
    WHERE STATEFIP = 31 AND AGE <= 5
    GROUP BY YEAR
    ORDER BY YEAR
    """
    for row in conn.execute(year_query).fetchall():
        print(f"  {row[0]}: {row[1]:,} children")

