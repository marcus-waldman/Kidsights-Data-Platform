"""
NSCH Database Insertion Script

Inserts validated NSCH data from Feather files into DuckDB database.
Stores raw survey data without harmonization.

Usage:
    # Insert 2023 data (replace mode - default)
    python pipelines/python/nsch/insert_nsch_database.py --year 2023

    # Insert in append mode
    python pipelines/python/nsch/insert_nsch_database.py --year 2023 --mode append

    # Use custom chunk size
    python pipelines/python/nsch/insert_nsch_database.py --year 2023 --chunk-size 5000

    # Use raw data instead of processed
    python pipelines/python/nsch/insert_nsch_database.py --year 2023 --source raw

    # Use custom database path
    python pipelines/python/nsch/insert_nsch_database.py --year 2023 \
        --database data/duckdb/custom.duckdb

Command-line Arguments:
    --year: Survey year (required, 2016-2023)
    --mode: Insert mode - 'replace' (default) or 'append'
    --source: Source file - 'processed' (default) or 'raw'
    --chunk-size: Rows per insert batch (default: 10000)
    --database: Database path (defaults to data/duckdb/kidsights_local.duckdb)
    --verbose: Enable verbose logging

Output:
    - Creates nsch_{year}_raw table in DuckDB
    - Inserts data with progress tracking
    - Generates insertion summary statistics

Author: Kidsights Data Platform
Date: 2025-10-03
"""

import argparse
import sys
import structlog
import pandas as pd
import duckdb
from pathlib import Path
from datetime import datetime
from typing import Dict, Any, Tuple

# Configure structured logging
log = structlog.get_logger()


def parse_arguments() -> argparse.Namespace:
    """Parse command-line arguments.

    Returns:
        argparse.Namespace: Parsed arguments
    """
    parser = argparse.ArgumentParser(
        description="Insert NSCH data into DuckDB database",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Insert 2023 data (replace existing)
  python pipelines/python/nsch/insert_nsch_database.py --year 2023

  # Append 2022 data
  python pipelines/python/nsch/insert_nsch_database.py --year 2022 --mode append

  # Use raw data instead of processed
  python pipelines/python/nsch/insert_nsch_database.py --year 2023 --source raw

For more information, see: docs/nsch/IMPLEMENTATION_PLAN.md
        """
    )

    # Required arguments
    parser.add_argument(
        "--year",
        type=int,
        required=True,
        help="Survey year (2016-2023)"
    )

    # Optional arguments
    parser.add_argument(
        "--mode",
        type=str,
        default="replace",
        choices=["replace", "append"],
        help="Insert mode: 'replace' drops table first, 'append' adds to existing (default: replace)"
    )

    parser.add_argument(
        "--source",
        type=str,
        default="processed",
        choices=["processed", "raw"],
        help="Source file: 'processed' (validated) or 'raw' (default: processed)"
    )

    parser.add_argument(
        "--chunk-size",
        type=int,
        default=10000,
        help="Number of rows to insert per batch (default: 10000)"
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


def validate_year(year: int) -> None:
    """Validate survey year is in valid range.

    Args:
        year: Survey year

    Raises:
        ValueError: If year is invalid
    """
    if year < 2016 or year > 2023:
        raise ValueError(
            f"Invalid year: {year}. Must be 2016-2023."
        )


def load_feather_data(year: int, source: str = "processed") -> pd.DataFrame:
    """Load NSCH data from Feather file.

    Args:
        year: Survey year
        source: 'processed' or 'raw'

    Returns:
        pd.DataFrame: NSCH data

    Raises:
        FileNotFoundError: If Feather file doesn't exist
    """
    feather_path = Path(f"data/nsch/{year}/{source}.feather")

    log.info("Loading Feather data", path=str(feather_path))

    if not feather_path.exists():
        raise FileNotFoundError(
            f"Feather file not found: {feather_path}\n\n"
            f"Please run SPSS conversion and R pipeline first:\n"
            f"  1. python pipelines/python/nsch/load_nsch_spss.py --year {year}\n"
            f"  2. Rscript pipelines/orchestration/run_nsch_pipeline.R --year {year}"
        )

    df = pd.read_feather(feather_path)

    log.info(
        "Feather data loaded",
        rows=len(df),
        columns=len(df.columns),
        file_size_mb=round(feather_path.stat().st_size / (1024**2), 2)
    )

    return df


def create_nsch_table(conn, year: int, df: pd.DataFrame, mode: str) -> None:
    """Create nsch_{year}_raw table.

    Args:
        conn: DuckDB connection
        year: Survey year
        df: Sample DataFrame for schema inference
        mode: 'replace' or 'append'
    """
    table_name = f"nsch_{year}_raw"

    if mode == "replace":
        # Drop table if exists
        log.info(f"Dropping existing table (replace mode)", table=table_name)
        conn.execute(f"DROP TABLE IF EXISTS {table_name}")

    # Check if table exists (for append mode)
    table_exists = conn.execute(
        f"SELECT COUNT(*) FROM information_schema.tables WHERE table_name = '{table_name}'"
    ).fetchone()[0] > 0

    if not table_exists:
        # Create table from DataFrame schema
        log.info(f"Creating table", table=table_name)

        # Register DataFrame temporarily to infer schema
        conn.register("temp_schema_df", df.head(0))

        # Create table with inferred schema
        conn.execute(f"CREATE TABLE {table_name} AS SELECT * FROM temp_schema_df")

        # Unregister temp DataFrame
        conn.unregister("temp_schema_df")

        log.info(f"Table created", table=table_name, columns=len(df.columns))
    else:
        log.info(f"Table already exists (append mode)", table=table_name)


def create_indexes(conn, year: int) -> None:
    """Create indexes for query performance.

    Args:
        conn: DuckDB connection
        year: Survey year
    """
    table_name = f"nsch_{year}_raw"

    log.info("Creating indexes", table=table_name)

    indexes = [
        f"CREATE INDEX IF NOT EXISTS idx_nsch_{year}_hhid ON {table_name}(HHID);",
        f"CREATE INDEX IF NOT EXISTS idx_nsch_{year}_year ON {table_name}(YEAR);",
    ]

    for idx_sql in indexes:
        try:
            conn.execute(idx_sql)
        except Exception as e:
            # Some columns might not exist, that's okay
            log.debug("Index creation skipped", error=str(e))

    log.info("Indexes created")


def insert_data_chunked(
    conn,
    year: int,
    df: pd.DataFrame,
    chunk_size: int = 10000
) -> int:
    """Insert data into table in chunks.

    Args:
        conn: DuckDB connection
        year: Survey year
        df: DataFrame to insert
        chunk_size: Rows per batch

    Returns:
        int: Total rows inserted
    """
    table_name = f"nsch_{year}_raw"
    total_rows = len(df)
    num_chunks = (total_rows + chunk_size - 1) // chunk_size

    log.info(
        "Inserting data in chunks",
        table=table_name,
        total_rows=total_rows,
        chunk_size=chunk_size,
        num_chunks=num_chunks
    )

    rows_inserted = 0

    for i in range(num_chunks):
        start_idx = i * chunk_size
        end_idx = min((i + 1) * chunk_size, total_rows)
        chunk_df = df.iloc[start_idx:end_idx]

        # Register chunk as temp view
        conn.register("temp_chunk", chunk_df)

        # Insert chunk
        conn.execute(f"INSERT INTO {table_name} SELECT * FROM temp_chunk")

        # Unregister temp view
        conn.unregister("temp_chunk")

        rows_inserted += len(chunk_df)

        # Progress logging
        if (i + 1) % 10 == 0 or (i + 1) == num_chunks:
            progress_pct = (rows_inserted / total_rows) * 100
            log.info(
                "Insertion progress",
                chunk=f"{i+1}/{num_chunks}",
                rows_inserted=rows_inserted,
                progress_pct=f"{progress_pct:.1f}%"
            )

    log.info("Data insertion complete", rows_inserted=rows_inserted)

    return rows_inserted


def validate_insertion(conn, year: int, expected_rows: int) -> Dict[str, Any]:
    """Validate data was inserted correctly.

    Args:
        conn: DuckDB connection
        year: Survey year
        expected_rows: Expected number of rows

    Returns:
        Dict: Validation results
    """
    table_name = f"nsch_{year}_raw"

    log.info("Validating insertion", table=table_name)

    # Check row count
    actual_rows = conn.execute(f"SELECT COUNT(*) FROM {table_name}").fetchone()[0]

    # Check HHID column exists and count nulls
    try:
        hhid_nulls = conn.execute(
            f"SELECT COUNT(*) FROM {table_name} WHERE HHID IS NULL"
        ).fetchone()[0]
    except:
        hhid_nulls = -1  # Column doesn't exist

    # Check YEAR column (if exists)
    try:
        year_values = conn.execute(
            f"SELECT DISTINCT YEAR FROM {table_name} ORDER BY YEAR"
        ).fetchall()
        year_values = [y[0] for y in year_values]
    except:
        year_values = []

    # Get column count
    column_count = conn.execute(
        f"SELECT COUNT(*) FROM information_schema.columns WHERE table_name = '{table_name}'"
    ).fetchone()[0]

    # Get table size
    table_size_bytes = conn.execute(
        f"SELECT estimated_size FROM duckdb_tables() WHERE table_name = '{table_name}'"
    ).fetchone()[0]
    table_size_mb = table_size_bytes / (1024**2) if table_size_bytes else 0

    validation = {
        "table_name": table_name,
        "actual_rows": actual_rows,
        "expected_rows": expected_rows,
        "rows_match": actual_rows == expected_rows,
        "column_count": column_count,
        "hhid_nulls": hhid_nulls,
        "year_values": year_values,
        "table_size_mb": round(table_size_mb, 2)
    }

    log.info(
        "Validation complete",
        table=table_name,
        actual_rows=actual_rows,
        expected_rows=expected_rows,
        rows_match=validation["rows_match"],
        columns=column_count,
        hhid_nulls=hhid_nulls,
        table_size_mb=validation["table_size_mb"]
    )

    if not validation["rows_match"]:
        log.warning(
            "Row count mismatch",
            expected=expected_rows,
            actual=actual_rows,
            difference=actual_rows - expected_rows
        )

    if hhid_nulls > 0:
        log.warning("HHID has null values", count=hhid_nulls)

    return validation


def print_summary(
    year: int,
    mode: str,
    source: str,
    rows_inserted: int,
    validation: Dict[str, Any],
    start_time: datetime,
    end_time: datetime
) -> None:
    """Print insertion summary.

    Args:
        year: Survey year
        mode: Insert mode
        source: Source file
        rows_inserted: Rows inserted
        validation: Validation results
        start_time: Start timestamp
        end_time: End timestamp
    """
    elapsed_seconds = (end_time - start_time).total_seconds()

    log.info("=" * 70)
    log.info("INSERTION SUMMARY")
    log.info("=" * 70)
    log.info(f"Year: {year}")
    log.info(f"Mode: {mode}")
    log.info(f"Source: {source}")
    log.info(f"Table: {validation['table_name']}")
    log.info(f"Rows Inserted: {rows_inserted:,}")
    log.info(f"Columns: {validation['column_count']}")
    log.info(f"Table Size: {validation['table_size_mb']:.2f} MB")
    log.info(f"Validation: {'PASS' if validation['rows_match'] else 'FAIL'}")
    log.info(f"Elapsed Time: {elapsed_seconds:.2f} seconds")
    log.info("=" * 70)


def main() -> int:
    """Main execution function.

    Returns:
        int: Exit code (0 for success, 1 for failure)
    """
    start_time = datetime.now()

    # Parse arguments
    args = parse_arguments()

    year = args.year
    mode = args.mode
    source = args.source
    chunk_size = args.chunk_size
    database_path = args.database
    verbose = args.verbose

    log.info("=" * 70)
    log.info("NSCH DATABASE INSERTION PIPELINE")
    log.info("=" * 70)
    log.info(f"Started: {start_time}")
    log.info(f"Year: {year}")
    log.info(f"Mode: {mode}")
    log.info(f"Source: {source}")
    log.info(f"Chunk Size: {chunk_size:,}")
    log.info(f"Database: {database_path}")
    log.info("=" * 70)

    try:
        # Step 1: Validate year
        validate_year(year)

        # Step 2: Load Feather data
        log.info("STEP 1: Load Feather Data")
        log.info("-" * 70)
        df = load_feather_data(year, source)

        # Step 3: Connect to database
        log.info("STEP 2: Connect to Database")
        log.info("-" * 70)
        db_path = Path(database_path)
        db_path.parent.mkdir(parents=True, exist_ok=True)

        conn = duckdb.connect(str(db_path))
        log.info(f"Connected to database: {db_path}")

        # Step 4: Create table
        log.info("STEP 3: Create Table")
        log.info("-" * 70)
        create_nsch_table(conn, year, df, mode)

        # Step 5: Insert data
        log.info("STEP 4: Insert Data")
        log.info("-" * 70)
        rows_inserted = insert_data_chunked(conn, year, df, chunk_size)

        # Step 6: Create indexes
        log.info("STEP 5: Create Indexes")
        log.info("-" * 70)
        create_indexes(conn, year)

        # Step 7: Validate
        log.info("STEP 6: Validate Insertion")
        log.info("-" * 70)
        validation = validate_insertion(conn, year, len(df))

        # Close connection
        conn.close()

        # Print summary
        end_time = datetime.now()
        print_summary(year, mode, source, rows_inserted, validation, start_time, end_time)

        if not validation["rows_match"]:
            log.warning("Validation failed - row count mismatch")
            return 1

        log.info("NSCH database insertion complete!")
        return 0

    except Exception as e:
        log.error("NSCH database insertion failed", error=str(e))
        import traceback
        traceback.print_exc()
        return 1


if __name__ == "__main__":
    sys.exit(main())
