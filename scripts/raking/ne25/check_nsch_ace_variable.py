#!/usr/bin/env python3
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent))

from python.db.connection import DatabaseManager

db = DatabaseManager()

with db.get_connection() as conn:
    # Look for ACE-related variables
    cols = conn.execute("DESCRIBE nsch_2023_raw").fetchall()
    col_names = [c[0] for c in cols]
    
    # Search for ACE patterns
    ace_vars = [c for c in col_names if 'ACE' in c.upper()]
    
    print(f"[INFO] ACE-related variables in NSCH 2023:")
    if ace_vars:
        for var in ace_vars:
            print(f"  - {var}")
    else:
        print("  [WARN] No variables with 'ACE' in name found")
        print("\n[INFO] Looking for alternative ACE indicators...")
        
        # Common NSCH ACE variable patterns
        alt_patterns = ['K11Q', 'ACE']
        for pattern in alt_patterns:
            matches = [c for c in col_names if pattern in c]
            if matches:
                print(f"\n  Pattern '{pattern}': {matches[:5]}")

