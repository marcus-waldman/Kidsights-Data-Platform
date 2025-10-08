#!/usr/bin/env python3
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent))

from python.db.connection import DatabaseManager

db = DatabaseManager()

with db.get_connection() as conn:
    print("[INFO] Parent-Child Linkage Variables:\n")
    
    # Check PAR1REL and PAR2REL (likely parent PERNUM pointers)
    print("[1] Parent Relationship Pointers:")
    par_check = """
    SELECT 
        COUNT(*) as total,
        COUNT(PAR1REL) as has_par1,
        COUNT(PAR2REL) as has_par2
    FROM nhis_raw
    WHERE REGION = 2 AND AGE <= 5
    """
    result = conn.execute(par_check).fetchone()
    print(f"    Total children 0-5: {result[0]:,}")
    print(f"    With PAR1REL: {result[1]:,}")
    print(f"    With PAR2REL: {result[2]:,}")
    
    # Check sample parent linkage
    print("\n[2] Sample Parent-Child Linkage (first 3 children):")
    sample_query = """
    SELECT SERIAL, PERNUM, AGE, PAR1REL, PAR2REL
    FROM nhis_raw
    WHERE REGION = 2 AND AGE <= 5
    LIMIT 3
    """
    print("    SERIAL | PERNUM | AGE | PAR1REL | PAR2REL")
    print("    -------|--------|-----|---------|--------")
    for row in conn.execute(sample_query).fetchall():
        print(f"    {row[0]:6} | {row[1]:6} | {row[2]:3} | {row[3] if row[3] else 'NULL':7} | {row[4] if row[4] else 'NULL'}")
    
    # Check if we can link to parents with PHQ data
    print("\n[3] Children with Parent PHQ-2 Data Available:")
    phq_link_query = """
    SELECT YEAR, COUNT(DISTINCT c.SERIAL || '-' || c.PERNUM) as children_with_parent_phq
    FROM nhis_raw c
    JOIN nhis_raw p ON c.SERIAL = p.SERIAL AND c.PAR1REL = p.PERNUM
    WHERE c.REGION = 2 
      AND c.AGE <= 5
      AND p.PHQINTR IS NOT NULL
      AND p.PHQDEP IS NOT NULL
    GROUP BY YEAR
    ORDER BY YEAR
    """
    print("    Year | Children")
    print("    -----|----------")
    for row in conn.execute(phq_link_query).fetchall():
        print(f"    {row[0]} | {row[1]:,}")

