"""
NHIS Database Insertion Script

Inserts NHIS data from Feather files into DuckDB database.
Stores raw IPUMS NHIS variables without harmonization.

Usage:
    # Insert 2019-2024 data (replace mode - default)
    python pipelines/python/nhis/insert_nhis_database.py --year-range 2019-2024

    # Insert in append mode (add to existing data)
    python pipelines/python/nhis/insert_nhis_database.py --year-range 2019-2024 --mode append

    # Use custom database path
    python pipelines/python/nhis/insert_nhis_database.py \
        --year-range 2019-2024 \
        --database data/duckdb/custom.duckdb

Command-line Arguments:
    --year-range: Year range (required, e.g., 2019-2024)
    --mode: Insert mode - 'replace' (default) or 'append'
    --source: Source file - 'processed' (default) or 'raw'
    --database: Database path (defaults to data/duckdb/kidsights_local.duckdb)
    --verbose: Enable verbose logging

Output:
    - Inserts data into nhis_raw table in DuckDB
    - Generates insertion summary statistics
    - Logs IPUMS NHIS variable names stored

Author: Kidsights Data Platform
Date: 2025-10-03
"""

import argparse
import sys
import structlog
import pandas as pd
from pathlib import Path
from datetime import datetime
from typing import Dict, Any

# Configure structured logging
log = structlog.get_logger()


def parse_arguments() -> argparse.Namespace:
    """Parse command-line arguments.

    Returns:
        argparse.Namespace: Parsed arguments
    """
    parser = argparse.ArgumentParser(
        description="Insert NHIS data into DuckDB database",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Insert 2019-2024 data (replace existing)
  python pipelines/python/nhis/insert_nhis_database.py --year-range 2019-2024

  # Append mode
  python pipelines/python/nhis/insert_nhis_database.py --year-range 2019-2024 --mode append

  # Use raw data instead of processed
  python pipelines/python/nhis/insert_nhis_database.py --year-range 2019-2024 --source raw

For more information, see: docs/nhis/pipeline_usage.md
        """
    )

    # Required arguments
    parser.add_argument(
        "--year-range",
        type=str,
        required=True,
        help="Year range for NHIS data (e.g., 2019-2024)"
    )

    # Optional arguments
    parser.add_argument(
        "--mode",
        type=str,
        default="replace",
        choices=["replace", "append"],
        help="Insert mode: 'replace' removes existing year data first, 'append' adds to existing (default: replace)"
    )

    parser.add_argument(
        "--source",
        type=str,
        default="processed",
        choices=["processed", "raw"],
        help="Source file: 'processed' (validated) or 'raw' (default: processed)"
    )

    parser.add_argument(
        "--database",
        type=str,
        default="data/duckdb/kidsights_local.duckdb",
        help="Database file path (default: data/duckdb/kidsights_local.duckdb)"
    )

    parser.add_argument(
        "--verbose",
        action="store_true",
        help="Enable verbose logging"
    )

    return parser.parse_args()


def load_nhis_feather(year_range: str, source: str = "processed") -> pd.DataFrame:
    """Load NHIS data from Feather file.

    Args:
        year_range: Year range (e.g., "2019-2024")
        source: Source file type ('processed' or 'raw')

    Returns:
        pd.DataFrame: NHIS data

    Raises:
        FileNotFoundError: If file doesn't exist
    """
    # Construct file path
    data_dir = Path(f"data/nhis/{year_range}")
    filename = f"{source}.feather"
    file_path = data_dir / filename

    log.info("Loading NHIS Feather file", path=str(file_path))

    if not file_path.exists():
        log.error("Feather file not found", path=str(file_path))
        raise FileNotFoundError(
            f"NHIS Feather file not found: {file_path}\n\n"
            f"Run extraction first:\n"
            f"  python pipelines/python/nhis/extract_nhis_data.py --year-range {year_range}"
        )

    # Load Feather
    df = pd.read_feather(str(file_path))

    log.info(
        "NHIS data loaded",
        rows=len(df),
        columns=len(df.columns),
        memory_mb=df.memory_usage(deep=True).sum() / 1024 / 1024
    )

    return df


def insert_to_database(
    df: pd.DataFrame,
    year_range: str,
    mode: str,
    database_path: str
) -> Dict[str, Any]:
    """Insert NHIS data into DuckDB database.

    Args:
        df: DataFrame to insert
        year_range: Year range for metadata
        mode: Insert mode ('replace' or 'append')
        database_path: Path to DuckDB database

    Returns:
        Dict with insertion statistics
    """
    import duckdb

    log.info(
        "Inserting NHIS data to database",
        database_path=database_path,
        mode=mode,
        records=len(df)
    )

    # Create database directory if needed (match ACS pattern)
    db_path = Path(database_path)
    db_path.parent.mkdir(parents=True, exist_ok=True)

    # Connect directly with duckdb (match ACS pattern, not DatabaseManager)
    conn = duckdb.connect(str(db_path))

    try:
        # Replace mode: drop table to allow schema changes
        if mode == 'replace':
            log.info("Replace mode: dropping existing table to allow schema updates")
            try:
                conn.execute("DROP TABLE IF EXISTS nhis_raw")
                log.info("Existing nhis_raw table dropped")
            except Exception as e:
                log.warning("Could not drop table (may not exist)", error=str(e))

        # Insert data
        log.info("Inserting NHIS data", records=len(df))

        # Create table from DataFrame schema
        conn.execute("CREATE TABLE IF NOT EXISTS nhis_raw AS SELECT * FROM df LIMIT 0")

        # Insert data
        conn.execute("INSERT INTO nhis_raw SELECT * FROM df")

        # Get row count
        result = conn.execute("SELECT COUNT(*) FROM nhis_raw").fetchone()
        total_rows = result[0] if result else 0

        log.info("NHIS data inserted successfully", inserted=len(df), total_rows=total_rows)

        stats = {
            "year_range": year_range,
            "inserted_at": datetime.utcnow().isoformat() + "Z",
            "mode": mode,
            "records_inserted": len(df),
            "total_records": total_rows,
            "variables": list(df.columns),
            "variable_count": len(df.columns)
        }

        return stats

    except Exception as e:
        log.error("Failed to insert NHIS data", error=str(e))
        raise Exception(f"Failed to insert NHIS data: {e}") from e
    finally:
        # Close connection (match ACS pattern)
        conn.close()
        log.debug("Database connection closed")


def main():
    """Main insertion workflow."""

    args = parse_arguments()

    log.info(
        "Starting NHIS database insertion",
        year_range=args.year_range,
        mode=args.mode,
        source=args.source
    )

    try:
        # 1. Load NHIS data
        print(f"\n{'='*70}")
        print("NHIS DATABASE INSERTION")
        print(f"{'='*70}")
        print(f"Year Range: {args.year_range}")
        print(f"Source: {args.source}")
        print(f"Mode: {args.mode}")
        print(f"Database: {args.database}")
        print(f"{'='*70}\n")

        df = load_nhis_feather(args.year_range, args.source)

        print(f"[OK] Loaded {len(df):,} records with {len(df.columns)} variables")

        # 2. Insert to database
        stats = insert_to_database(df, args.year_range, args.mode, args.database)

        # 3. Success summary
        print("\n" + "="*70)
        print("INSERTION COMPLETE")
        print("="*70)
        print(f"Records Inserted: {stats['records_inserted']:,}")
        print(f"Total Records in DB: {stats['total_records']:,}")
        print(f"Variables: {stats['variable_count']}")
        print(f"Mode: {stats['mode']}")
        print(f"Table: nhis_raw")
        print("="*70)

        log.info("NHIS database insertion completed successfully")

        return 0

    except KeyboardInterrupt:
        log.warning("Insertion interrupted by user")
        print("\n\nInsertion interrupted by user (Ctrl+C)")
        return 130

    except Exception as e:
        log.error("Insertion failed", error=str(e), error_type=type(e).__name__)
        print(f"\n\n[ERROR] {e}")
        print("\nFor troubleshooting, see: docs/nhis/pipeline_usage.md")
        return 1


if __name__ == "__main__":
    sys.exit(main())
