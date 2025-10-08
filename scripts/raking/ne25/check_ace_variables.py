#!/usr/bin/env python3
"""Check for specific ACE variables needed for raking targets"""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent))

from python.db.connection import DatabaseManager

# ACE variables from RAKING_TARGETS_ESTIMATION_PLAN.md
ace_vars_needed = [
    'VIOLENEV',   # Lived with violent person
    'JAILEV',     # Lived with incarcerated person  
    'MENTDEPEV',  # Lived with mentally ill person
    'ALCDRUGEV',  # Lived with substance user
    'ADLTPUTDOWN',# Physical abuse
    'UNFAIRRACE', # Discrimination (race)
    'UNFAIRSEXOR',# Discrimination (sex/orientation)
    'BASENEED'    # Couldn't afford basic needs
]

db = DatabaseManager()

with db.get_connection() as conn:
    print("[INFO] Checking for ACE variables in nhis_raw table:\n")
    
    # Get all columns
    cols = conn.execute("DESCRIBE nhis_raw").fetchall()
    col_names = [c[0] for c in cols]
    
    found = []
    missing = []
    
    for var in ace_vars_needed:
        if var in col_names:
            found.append(var)
            print(f"  [OK] {var}")
        else:
            missing.append(var)
            print(f"  [MISSING] {var}")
    
    print(f"\n[SUMMARY] Found: {len(found)}/8 ACE variables")
    
    if len(found) == 8:
        print("[SUCCESS] All ACE variables present!")
    elif len(found) > 0:
        print(f"[WARN] Partial ACE coverage - missing: {', '.join(missing)}")
    else:
        print("[ERROR] No ACE variables found")

