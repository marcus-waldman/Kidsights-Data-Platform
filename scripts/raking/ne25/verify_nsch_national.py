#!/usr/bin/env python3
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent))

from python.db.connection import DatabaseManager

db = DatabaseManager()

with db.get_connection() as conn:
    # National sample 0-5
    national = conn.execute("""
        SELECT COUNT(*) FROM nsch_2023 WHERE SC_AGE_YEARS <= 5
    """).fetchone()[0]
    
    print(f"[INFO] National NSCH 2023 children ages 0-5: {national:,}")
    print(f"[INFO] Nebraska subset: 418 children")
    print(f"\n[OK] Will use mixed model with all states, predict for NE")

