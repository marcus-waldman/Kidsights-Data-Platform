#!/usr/bin/env python3
"""
Query geographic crosswalk tables from DuckDB and export to Feather format.

This script is called from R to safely access DuckDB without segmentation faults.
The hybrid Python→Feather→R approach ensures 100% reliability.

Usage:
    python python/db/query_geo_crosswalk.py --table geo_zip_to_puma --output temp.feather
"""

import sys
import argparse
import duckdb
import pandas as pd
from pathlib import Path


def query_crosswalk(table_name: str, output_path: str, db_path: str = None) -> bool:
    """
    Query a geographic crosswalk table and write to Feather format.

    Args:
        table_name: Name of crosswalk table to query
        output_path: Path for output Feather file
        db_path: Path to DuckDB database (default: data/duckdb/kidsights_local.duckdb)

    Returns:
        True if successful, False otherwise
    """
    if db_path is None:
        db_path = "data/duckdb/kidsights_local.duckdb"

    try:
        # Connect to database
        conn = duckdb.connect(db_path, read_only=True)

        # Query table
        df = conn.execute(f"SELECT * FROM {table_name}").fetchdf()

        conn.close()

        if df.empty:
            print(f"WARNING: Table {table_name} is empty", file=sys.stderr)
            return False

        # Write to Feather
        df.to_feather(output_path)

        # Success message to stdout
        print(f"SUCCESS: Exported {len(df)} rows from {table_name} to {output_path}")

        return True

    except Exception as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return False


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description='Query geographic crosswalk from DuckDB'
    )
    parser.add_argument(
        '--table',
        required=True,
        help='Table name to query'
    )
    parser.add_argument(
        '--output',
        required=True,
        help='Output Feather file path'
    )
    parser.add_argument(
        '--db',
        default='data/duckdb/kidsights_local.duckdb',
        help='Database path (default: data/duckdb/kidsights_local.duckdb)'
    )

    args = parser.parse_args()

    success = query_crosswalk(
        table_name=args.table,
        output_path=args.output,
        db_path=args.db
    )

    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
