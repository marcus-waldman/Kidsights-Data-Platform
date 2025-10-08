#!/usr/bin/env python3
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent))

from python.db.connection import DatabaseManager

db = DatabaseManager()
with db.get_connection() as conn:
    # Quick check
    count = conn.execute("SELECT COUNT(*) FROM nhis_raw").fetchone()[0]
    print(f"NHIS records: {count:,}")
    
    years = conn.execute("SELECT MIN(YEAR), MAX(YEAR) FROM nhis_raw").fetchone()
    print(f"Years: {years[0]}-{years[1]}")
    
    # Check for key columns
    cols = conn.execute("DESCRIBE nhis_raw").fetchall()
    col_names = [c[0] for c in cols]
    
    key_vars = ['REGION', 'PHQINTR', 'PHQDEP', 'AGE']
    found = [v for v in key_vars if v in col_names]
    print(f"Key variables: {found}")
