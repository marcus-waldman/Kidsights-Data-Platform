"""
Insert HRTL/CAHMI codebook from Update-KidsightsPublic repository into DuckDB
Source: C:/Users/marcu/git-repositories/Update-KidsightsPublic/codebook/codebook_old.csv
"""

import sys
import os
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..')))

from python.db.connection import DatabaseManager
import pandas as pd

def main():
    # File path
    csv_path = "C:/Users/marcu/git-repositories/Update-KidsightsPublic/codebook/codebook_old.csv"

    print(f"[INFO] Reading codebook from: {csv_path}")

    # Read CSV (try multiple encodings)
    try:
        df = pd.read_csv(csv_path, encoding='utf-8')
    except UnicodeDecodeError:
        print("[WARN] UTF-8 encoding failed, trying Windows-1252...")
        try:
            df = pd.read_csv(csv_path, encoding='windows-1252')
        except Exception as e:
            print(f"[ERROR] Failed to read CSV with windows-1252: {e}")
            return 1

    print(f"[OK] Loaded {len(df)} rows, {len(df.columns)} columns")
    print(f"[INFO] Columns: {', '.join(df.columns.tolist()[:10])}...")

    # Initialize database connection
    print("\n[INFO] Connecting to DuckDB...")
    db = DatabaseManager()

    # Table name
    table_name = "hrtl_codebook_reference"

    # Use get_connection context manager
    with db.get_connection() as conn:
        # Drop existing table if it exists
        print(f"[INFO] Dropping existing table '{table_name}' if it exists...")
        conn.execute(f"DROP TABLE IF EXISTS {table_name}")

        # Register pandas dataframe and create table
        print(f"[INFO] Inserting data to table '{table_name}'...")
        try:
            conn.register("df_temp", df)
            conn.execute(f"CREATE TABLE {table_name} AS SELECT * FROM df_temp")
            print(f"[OK] Successfully inserted {len(df)} rows")
        except Exception as e:
            print(f"[ERROR] Failed to insert data: {e}")
            return 1

        # Verify insertion
        print("\n[INFO] Verifying insertion...")
        result = conn.execute(f"SELECT COUNT(*) as count FROM {table_name}").fetchone()
        row_count = result[0]
        print(f"[OK] Table '{table_name}' contains {row_count} rows")

        # Show sample data
        print("\n[INFO] Sample data (first 5 rows):")
        sample = conn.execute(f"""
            SELECT jid, lex_equate, lex_ne25, domain_hrtl, hrtl_calibration_item
            FROM {table_name}
            LIMIT 5
        """).fetchall()
        for row in sample:
            print(f"  JID {row[0]}: {row[1]} -> NE25:{row[2]} | Domain:{row[3]} | Calibration:{row[4]}")

        # Count HRTL items
        print("\n[INFO] Counting HRTL-related items...")
        hrtl_counts = conn.execute(f"""
            SELECT
                domain_hrtl,
                COUNT(*) as count
            FROM {table_name}
            WHERE domain_hrtl IS NOT NULL AND domain_hrtl != ''
            GROUP BY domain_hrtl
            ORDER BY count DESC
        """).fetchall()
        print("[INFO] HRTL items by domain:")
        for domain, count in hrtl_counts:
            print(f"  {domain}: {count} items")

        # Create indexes for faster querying
        print("\n[INFO] Creating indexes...")
        conn.execute(f"CREATE INDEX IF NOT EXISTS idx_hrtl_codebook_jid ON {table_name}(jid)")
        conn.execute(f"CREATE INDEX IF NOT EXISTS idx_hrtl_codebook_equate ON {table_name}(lex_equate)")
        conn.execute(f"CREATE INDEX IF NOT EXISTS idx_hrtl_codebook_ne25 ON {table_name}(lex_ne25)")
        conn.execute(f"CREATE INDEX IF NOT EXISTS idx_hrtl_codebook_domain ON {table_name}(domain_hrtl)")
        print("[OK] Indexes created")

        print(f"\n[OK] HRTL codebook successfully loaded into '{table_name}' table")
        print(f"[INFO] Total rows: {row_count}")

    return 0

if __name__ == "__main__":
    exit(main())
