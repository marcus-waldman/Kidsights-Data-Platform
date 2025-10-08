#!/usr/bin/env python3
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent))

from python.db.connection import DatabaseManager

db = DatabaseManager()

with db.get_connection() as conn:
    # Fixed query with explicit column references
    phq_link_query = """
    SELECT c.YEAR, COUNT(DISTINCT c.SERIAL || '-' || c.PERNUM) as children_with_parent_phq
    FROM nhis_raw c
    JOIN nhis_raw p ON c.SERIAL = p.SERIAL AND c.PAR1REL = p.PERNUM
    WHERE c.REGION = 2 
      AND c.AGE <= 5
      AND p.PHQINTR IS NOT NULL
      AND p.PHQDEP IS NOT NULL
    GROUP BY c.YEAR
    ORDER BY c.YEAR
    """
    print("Children with Parent PHQ-2 Data (North Central, ages 0-5):")
    print("Year | Children")
    print("-----|----------")
    for row in conn.execute(phq_link_query).fetchall():
        print(f"{row[0]} | {row[1]:,}")
