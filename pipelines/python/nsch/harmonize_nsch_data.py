"""
NSCH Harmonization Database Integration

Calls R harmonization functions to create lex_equate columns and appends them
to existing nsch_{year} tables in DuckDB.

Usage:
    python pipelines/python/nsch/harmonize_nsch_data.py --year 2021
    python pipelines/python/nsch/harmonize_nsch_data.py --year 2022

Command-line Arguments:
    --year: NSCH year (required, 2021 or 2022)
    --database: Database path (defaults to data/duckdb/kidsights_local.duckdb)
    --verbose: Enable verbose logging

Output:
    - Adds harmonized columns to nsch_{year} table
    - Creates indexes on harmonized columns
    - Logs column additions and update statistics

Author: Kidsights Data Platform
Date: 2025-11-13
"""

import argparse
import sys
import subprocess
import tempfile
import json
from pathlib import Path
import duckdb
import pandas as pd

def harmonize_via_r(year: int) -> pd.DataFrame:
    """
    Call R harmonization function and return harmonized data frame.

    Args:
        year: NSCH year (2021 or 2022)

    Returns:
        DataFrame with HHID + harmonized columns
    """
    print(f"[1/3] Calling R harmonization function for NSCH {year}...")

    # Create Python-controlled temp file for feather output
    temp_feather_fd, temp_feather_path = tempfile.mkstemp(suffix='.feather')
    import os
    os.close(temp_feather_fd)  # Close file descriptor, R will write to this path

    # Convert Windows path to R-compatible format (forward slashes)
    r_temp_path = temp_feather_path.replace('\\', '/')

    # Create temporary R script
    # Use Python's temp file path to avoid R's session cleanup
    r_script = f"""
    # Load harmonization function
    source("R/transform/nsch/harmonize_nsch_{year}.R")

    # Run harmonization (suppress messages to avoid stdout pollution)
    harmonized_df <- suppressMessages(harmonize_nsch_{year}())

    # Save to temporary feather file for Python to read
    library(arrow)
    arrow::write_feather(harmonized_df, "{r_temp_path}")
    cat("SUCCESS")
    """

    # Write script to temp file
    with tempfile.NamedTemporaryFile(mode='w', suffix='.R', delete=False) as f:
        f.write(r_script)
        r_script_path = f.name

    try:
        # Execute R script
        result = subprocess.run(
            ["C:\\Program Files\\R\\R-4.5.1\\bin\\Rscript.exe", r_script_path],
            capture_output=True,
            text=True,
            check=True
        )

        # Check R completed successfully
        if "SUCCESS" not in result.stdout:
            raise RuntimeError(f"R harmonization did not complete: {result.stderr}")

        # Read feather file
        print(f"[2/3] Reading harmonized data from temporary file...")
        harmonized_df = pd.read_feather(temp_feather_path)

        print(f"  Received: {len(harmonized_df)} records, {len(harmonized_df.columns)} columns")
        print(f"  Columns: {', '.join(list(harmonized_df.columns)[:10])}{'...' if len(harmonized_df.columns) > 10 else ''}")

        return harmonized_df

    finally:
        # Clean up temp files
        Path(r_script_path).unlink(missing_ok=True)
        Path(temp_feather_path).unlink(missing_ok=True)


def add_harmonized_columns_to_database(year: int, harmonized_df: pd.DataFrame, db_path: str):
    """
    Add harmonized columns to nsch_{year} table.

    Args:
        year: NSCH year
        harmonized_df: DataFrame with HHID + harmonized columns
        db_path: Path to DuckDB database
    """
    print(f"[3/3] Adding harmonized columns to nsch_{year} table...")

    # Connect to database
    con = duckdb.connect(db_path)

    try:
        table_name = f"nsch_{year}"

        # Get current columns
        current_cols = con.execute(f"PRAGMA table_info({table_name})").df()
        current_col_names = set(current_cols['name'].tolist())

        # Identify new columns to add
        harmonized_cols = [col for col in harmonized_df.columns if col != 'HHID']
        new_cols = [col for col in harmonized_cols if col not in current_col_names]
        existing_cols = [col for col in harmonized_cols if col in current_col_names]

        if existing_cols:
            print(f"  Found {len(existing_cols)} existing harmonized columns (will update)")

        if new_cols:
            print(f"  Adding {len(new_cols)} new harmonized columns...")

            # Add new columns
            for col in new_cols:
                con.execute(f"ALTER TABLE {table_name} ADD COLUMN {col} DOUBLE")

            print(f"  [OK] Added {len(new_cols)} columns")

        # Update values for all harmonized columns
        all_harmonized_cols = new_cols + existing_cols
        print(f"  Updating values for {len(all_harmonized_cols)} columns...")

        # Register harmonized_df as temporary table
        con.register('harmonized_temp', harmonized_df)

        # Update via single SQL statement (much faster than row-by-row)
        # Note: DuckDB doesn't allow qualified column names in SET clause
        set_clauses = [f"{col} = harmonized_temp.{col}" for col in all_harmonized_cols]
        update_sql = f"""
        UPDATE {table_name}
        SET {', '.join(set_clauses)}
        FROM harmonized_temp
        WHERE {table_name}.HHID = harmonized_temp.HHID
        """

        con.execute(update_sql)
        print(f"  [OK] Updated {len(harmonized_df)} records")

        # Create indexes on harmonized columns for query performance
        print(f"  Creating indexes on harmonized columns...")

        # Create composite index on frequently-used columns
        # (individual indexes created on-demand if needed)
        if 'DD201' in all_harmonized_cols and 'DD299' in all_harmonized_cols:
            index_name = f"idx_{table_name}_harmonized_sample"
            try:
                con.execute(f"CREATE INDEX IF NOT EXISTS {index_name} ON {table_name} (DD201, DD299)")
                print(f"  [OK] Created sample index ({index_name})")
            except Exception as e:
                print(f"  [WARNING] Could not create index: {e}")

        # Verify updates
        print(f"  Verifying updates...")
        sample_col = all_harmonized_cols[0]
        non_null_count = con.execute(f"SELECT COUNT(*) FROM {table_name} WHERE {sample_col} IS NOT NULL").fetchone()[0]
        print(f"  Sample column ({sample_col}): {non_null_count:,} non-null values")

        print(f"\n[OK] Harmonization complete for nsch_{year}")
        print(f"  Total harmonized columns: {len(all_harmonized_cols)}")
        print(f"  New columns added: {len(new_cols)}")
        print(f"  Existing columns updated: {len(existing_cols)}")

    finally:
        con.close()


def main():
    parser = argparse.ArgumentParser(
        description='Add harmonized columns to NSCH database tables'
    )
    parser.add_argument('--year', type=int, required=True,
                        choices=[2021, 2022],
                        help='NSCH year to harmonize')
    parser.add_argument('--database', type=str,
                        default='data/duckdb/kidsights_local.duckdb',
                        help='Path to DuckDB database')
    parser.add_argument('--verbose', action='store_true',
                        help='Enable verbose logging')

    args = parser.parse_args()

    print("="*80)
    print(f"NSCH {args.year} Harmonization - Database Integration")
    print("="*80)
    print()

    try:
        # Step 1-2: Call R harmonization and get data frame
        harmonized_df = harmonize_via_r(args.year)

        # Step 3: Add columns to database
        add_harmonized_columns_to_database(args.year, harmonized_df, args.database)

        print()
        print("="*80)
        print("[OK] Harmonization pipeline completed successfully")
        print("="*80)

    except subprocess.CalledProcessError as e:
        print(f"\n[ERROR] R harmonization failed:")
        print(f"  {e.stderr}")
        sys.exit(1)
    except Exception as e:
        print(f"\n[ERROR] Harmonization pipeline failed:")
        print(f"  {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
