#!/usr/bin/env python3
"""Check NHIS data availability for raking targets"""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent))

from python.db.connection import DatabaseManager

db = DatabaseManager()

print("[INFO] Checking NHIS data availability...")

with db.get_connection() as conn:
    # Check for NHIS tables
    tables = conn.execute("SHOW TABLES").fetchall()
    nhis_tables = [t[0] for t in tables if 'nhis' in t[0].lower()]
    
    print(f"[INFO] NHIS tables found: {nhis_tables}")
    
    if not nhis_tables:
        print("[WARN] No NHIS tables in database")
        print("[INFO] Need to run NHIS pipeline first")
    else:
        # Check main NHIS data table
        for table in nhis_tables:
            if 'data' in table or table == 'nhis':
                count = conn.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]
                print(f"\n[INFO] Table '{table}': {count:,} total records")
                
                # Check year range
                year_query = f"""
                SELECT MIN(YEAR) as min_year, MAX(YEAR) as max_year, COUNT(DISTINCT YEAR) as n_years
                FROM {table}
                """
                years = conn.execute(year_query).fetchone()
                print(f"[INFO] Year range: {years[0]}-{years[1]} ({years[2]} years)")
                
                # Check for region variable
                region_check = f"""
                SELECT COLUMN_NAME 
                FROM (DESCRIBE {table})
                WHERE COLUMN_NAME = 'REGION'
                """
                has_region = conn.execute(region_check).fetchone()
                
                if has_region:
                    # Count North Central region (2)
                    nc_query = f"""
                    SELECT COUNT(*) 
                    FROM {table}
                    WHERE REGION = 2
                    """
                    nc_count = conn.execute(nc_query).fetchone()[0]
                    print(f"[INFO] North Central region records: {nc_count:,}")
                
                # Check for PHQ variables
                phq_check = f"""
                SELECT COLUMN_NAME 
                FROM (DESCRIBE {table})
                WHERE COLUMN_NAME IN ('PHQINTR', 'PHQDEP')
                """
                phq_vars = [row[0] for row in conn.execute(phq_check).fetchall()]
                if phq_vars:
                    print(f"[OK] PHQ variables found: {phq_vars}")
                
                # Check for ACE variables  
                ace_check = f"""
                SELECT COLUMN_NAME
                FROM (DESCRIBE {table})
                WHERE COLUMN_NAME LIKE 'ACE%'
                """
                ace_vars = [row[0] for row in conn.execute(ace_check).fetchall()]
                if ace_vars:
                    print(f"[OK] ACE variables found: {len(ace_vars)} variables")

