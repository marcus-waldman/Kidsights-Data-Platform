#!/usr/bin/env python3
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent))

from python.db.connection import DatabaseManager

db = DatabaseManager()

with db.get_connection() as conn:
    # Look for any family/relationship variables
    query = """
    SELECT COLUMN_NAME 
    FROM (DESCRIBE nhis_raw)
    WHERE COLUMN_NAME LIKE '%FAM%' 
       OR COLUMN_NAME LIKE '%REL%'
       OR COLUMN_NAME LIKE '%PARENT%'
       OR COLUMN_NAME LIKE '%CHILD%'
    ORDER BY COLUMN_NAME
    """
    vars_found = [row[0] for row in conn.execute(query).fetchall()]
    
    if vars_found:
        print(f"[INFO] Found {len(vars_found)} family/relationship variables:")
        for var in vars_found:
            print(f"  - {var}")
    else:
        print("[INFO] No family/relationship variables found with standard patterns")
    
    # Also check for ACE with different naming
    ace_query = """
    SELECT COLUMN_NAME 
    FROM (DESCRIBE nhis_raw)
    WHERE COLUMN_NAME LIKE '%ADVERS%'
       OR COLUMN_NAME LIKE '%CHILDH%'
       OR COLUMN_NAME LIKE '%TRAUMA%'
    ORDER BY COLUMN_NAME
    """
    ace_alt = [row[0] for row in conn.execute(ace_query).fetchall()]
    if ace_alt:
        print(f"\n[INFO] Possible ACE-related variables:")
        for var in ace_alt:
            print(f"  - {var}")
