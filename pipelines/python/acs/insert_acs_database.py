"""
ACS Database Insertion Script

Inserts validated ACS data from Feather files into DuckDB database.
Stores raw IPUMS variables without harmonization.

Usage:
    # Insert Nebraska 2019-2023 data (replace mode - default)
    python pipelines/python/acs/insert_acs_database.py \
        --state nebraska --year-range 2019-2023

    # Insert in append mode (add to existing data)
    python pipelines/python/acs/insert_acs_database.py \
        --state nebraska --year-range 2019-2023 --mode append

    # Use custom database path
    python pipelines/python/acs/insert_acs_database.py \
        --state nebraska --year-range 2019-2023 \
        --database data/duckdb/custom.duckdb

Command-line Arguments:
    --state: State name (required, e.g., nebraska)
    --year-range: Year range (required, e.g., 2019-2023)
    --mode: Insert mode - 'replace' (default) or 'append'
    --source: Source file - 'processed' (default) or 'raw'
    --database: Database path (defaults to data/duckdb/kidsights_local.duckdb)
    --verbose: Enable verbose logging

Output:
    - Inserts data into acs_data table in DuckDB
    - Generates insertion summary statistics
    - Logs IPUMS variable names stored

Author: Kidsights Data Platform
Date: 2025-09-30
"""

import argparse
import sys
import structlog
import pandas as pd
from pathlib import Path
from datetime import datetime
from typing import Dict, Any, Tuple, List

# Import database connection
from python.db.connection import DatabaseManager

# Configure structured logging
log = structlog.get_logger()


def parse_arguments() -> argparse.Namespace:
    """Parse command-line arguments.

    Returns:
        argparse.Namespace: Parsed arguments
    """
    parser = argparse.ArgumentParser(
        description="Insert ACS data into DuckDB database",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Insert Nebraska data (replace existing)
  python pipelines/python/acs/insert_acs_database.py --state nebraska --year-range 2019-2023

  # Append Iowa data
  python pipelines/python/acs/insert_acs_database.py --state iowa --year-range 2019-2023 --mode append

  # Use raw data instead of processed
  python pipelines/python/acs/insert_acs_database.py --state nebraska --year-range 2019-2023 --source raw

For more information, see: docs/acs/pipeline_usage.md
        """
    )

    # Required arguments
    parser.add_argument(
        "--state",
        type=str,
        required=True,
        help="State name (lowercase, e.g., nebraska, iowa, kansas)"
    )

    parser.add_argument(
        "--year-range",
        type=str,
        required=True,
        help="Year range for ACS sample (e.g., 2019-2023)"
    )

    # Optional arguments
    parser.add_argument(
        "--mode",
        type=str,
        default="replace",
        choices=["replace", "append"],
        help="Insert mode: 'replace' removes existing state/year data first, 'append' adds to existing (default: replace)"
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


def load_feather_data(state: str, year_range: str, source: str = "processed") -> pd.DataFrame:
    """Load ACS data from Feather file.

    Args:
        state: State name
        year_range: Year range
        source: 'processed' or 'raw'

    Returns:
        pd.DataFrame: ACS data

    Raises:
        FileNotFoundError: If Feather file doesn't exist
    """
    feather_path = Path(f"data/acs/{state}/{year_range}/{source}.feather")

    log.info("Loading Feather data", path=str(feather_path))

    if not feather_path.exists():
        raise FileNotFoundError(
            f"Feather file not found: {feather_path}\n\n"
            f"Please run extraction and R pipeline first:\n"
            f"  1. python pipelines/python/acs/extract_acs_data.py --state {state} --year-range {year_range}\n"
            f"  2. R pipeline: run_acs_pipeline.R --args state={state} year_range={year_range}"
        )

    df = pd.read_feather(feather_path)

    log.info(
        "Feather data loaded",
        rows=len(df),
        columns=len(df.columns),
        file_size_mb=round(feather_path.stat().st_size / (1024**2), 2)
    )

    return df


def add_metadata_columns(df: pd.DataFrame, state: str, year_range: str) -> pd.DataFrame:
    """Add state and year_range columns for multi-state tracking.

    Args:
        df: Input DataFrame
        state: State name
        year_range: Year range

    Returns:
        pd.DataFrame: DataFrame with metadata columns
    """
    df = df.copy()
    df['state'] = state
    df['year_range'] = year_range

    log.debug("Added metadata columns", state=state, year_range=year_range)

    return df


def create_acs_table(conn) -> None:
    """Create acs_data table if it doesn't exist.

    Args:
        conn: DuckDB connection

    Note:
        Schema follows config/duckdb.yaml definition
    """
    log.info("Creating acs_data table (if not exists)")

    create_table_sql = """
    CREATE TABLE IF NOT EXISTS acs_data (
        -- Multi-state tracking
        state VARCHAR NOT NULL,
        year_range VARCHAR NOT NULL,

        -- Core IPUMS identifiers
        SERIAL BIGINT NOT NULL,
        PERNUM INTEGER NOT NULL,

        -- Sampling weights
        HHWT DOUBLE,
        PERWT DOUBLE,

        -- Core demographics
        AGE INTEGER NOT NULL,
        SEX INTEGER,
        RACE INTEGER,
        HISPAN INTEGER,

        -- Geographic identifiers
        STATEFIP INTEGER NOT NULL,
        PUMA INTEGER,
        METRO INTEGER,

        -- Education (with attached characteristics)
        EDUC INTEGER,
        EDUC_mom INTEGER,
        EDUC_pop INTEGER,
        EDUCD INTEGER,
        EDUCD_mom INTEGER,
        EDUCD_pop INTEGER,

        -- Household economics
        HHINCOME INTEGER,
        FTOTINC INTEGER,
        POVERTY INTEGER,
        GRPIP INTEGER,

        -- Government programs
        FOODSTMP INTEGER,
        HINSCAID INTEGER,
        HCOVANY INTEGER,

        -- Household composition
        RELATE INTEGER,
        MARST INTEGER,
        MARST_head INTEGER,
        MOMLOC INTEGER,
        POPLOC INTEGER,

        -- Primary key: unique child within state/year
        PRIMARY KEY (state, year_range, SERIAL, PERNUM)
    );
    """

    conn.execute(create_table_sql)

    log.info("acs_data table created (or already exists)")


def create_indexes(conn) -> None:
    """Create indexes for query performance.

    Args:
        conn: DuckDB connection
    """
    log.info("Creating indexes on acs_data table")

    indexes = [
        "CREATE INDEX IF NOT EXISTS idx_acs_state ON acs_data(state);",
        "CREATE INDEX IF NOT EXISTS idx_acs_year_range ON acs_data(year_range);",
        "CREATE INDEX IF NOT EXISTS idx_acs_state_year ON acs_data(state, year_range);",
        "CREATE INDEX IF NOT EXISTS idx_acs_age ON acs_data(AGE);",
        "CREATE INDEX IF NOT EXISTS idx_acs_statefip ON acs_data(STATEFIP);",
    ]

    for idx_sql in indexes:
        conn.execute(idx_sql)

    log.info("Indexes created")


def delete_existing_data(conn, state: str, year_range: str) -> int:
    """Delete existing data for state/year (replace mode).

    Args:
        conn: DuckDB connection
        state: State name
        year_range: Year range

    Returns:
        int: Number of rows deleted
    """
    log.info("Deleting existing data (replace mode)", state=state, year_range=year_range)

    delete_sql = """
    DELETE FROM acs_data
    WHERE state = ? AND year_range = ?
    """

    result = conn.execute(delete_sql, [state, year_range])

    # Get row count from result
    rows_deleted = result.fetchall()
    count = rows_deleted[0][0] if rows_deleted and len(rows_deleted[0]) > 0 else 0

    log.info("Existing data deleted", rows_deleted=count)

    return count


def insert_data(conn, df: pd.DataFrame, mode: str, state: str, year_range: str) -> Tuple[int, int]:
    """Insert data into acs_data table.

    Args:
        conn: DuckDB connection
        df: DataFrame to insert
        mode: 'replace' or 'append'
        state: State name
        year_range: Year range

    Returns:
        Tuple[int, int]: (rows_inserted, rows_deleted)
    """
    rows_deleted = 0

    # Replace mode: delete existing data first
    if mode == "replace":
        rows_deleted = delete_existing_data(conn, state, year_range)

    # Insert data
    log.info("Inserting data into acs_data", rows=len(df), mode=mode)

    # Register DataFrame as temporary view
    conn.register("temp_acs_data", df)

    # Insert from temp view
    insert_sql = """
    INSERT INTO acs_data
    SELECT * FROM temp_acs_data
    """

    conn.execute(insert_sql)

    # Unregister temp view
    conn.unregister("temp_acs_data")

    rows_inserted = len(df)

    log.info("Data inserted successfully", rows_inserted=rows_inserted)

    return rows_inserted, rows_deleted


def get_table_statistics(conn, state: str, year_range: str) -> Dict[str, Any]:
    """Get statistics about inserted data.

    Args:
        conn: DuckDB connection
        state: State name (optional filter)
        year_range: Year range (optional filter)

    Returns:
        Dict with statistics
    """
    log.debug("Gathering table statistics")

    stats = {}

    # Total rows for this state/year
    result = conn.execute(
        "SELECT COUNT(*) FROM acs_data WHERE state = ? AND year_range = ?",
        [state, year_range]
    ).fetchone()
    stats['rows_this_state_year'] = result[0]

    # Total rows in table
    result = conn.execute("SELECT COUNT(*) FROM acs_data").fetchone()
    stats['rows_total'] = result[0]

    # Number of states
    result = conn.execute("SELECT COUNT(DISTINCT state) FROM acs_data").fetchone()
    stats['distinct_states'] = result[0]

    # Number of year ranges
    result = conn.execute("SELECT COUNT(DISTINCT year_range) FROM acs_data").fetchone()
    stats['distinct_year_ranges'] = result[0]

    # Age distribution for this state/year
    result = conn.execute("""
        SELECT AGE, COUNT(*) as count
        FROM acs_data
        WHERE state = ? AND year_range = ?
        GROUP BY AGE
        ORDER BY AGE
    """, [state, year_range]).fetchall()

    stats['age_distribution'] = {row[0]: row[1] for row in result}

    # Variable names
    result = conn.execute("""
        SELECT column_name
        FROM information_schema.columns
        WHERE table_name = 'acs_data'
        ORDER BY ordinal_position
    """).fetchall()

    stats['variables'] = [row[0] for row in result]

    return stats


def main():
    """Main insertion pipeline."""
    start_time = datetime.now()

    # Parse arguments
    args = parse_arguments()

    log.info(
        "=" * 70 + "\n" +
        "ACS DATABASE INSERTION PIPELINE\n" +
        "=" * 70
    )
    log.info(f"Started: {start_time}")
    log.info(f"State: {args.state}")
    log.info(f"Year Range: {args.year_range}")
    log.info(f"Mode: {args.mode}")
    log.info(f"Source: {args.source}")
    log.info(f"Database: {args.database}")

    try:
        # Step 1: Load Feather data
        log.info("=" * 70)
        log.info("STEP 1: Load Feather Data")
        log.info("=" * 70)

        df = load_feather_data(args.state, args.year_range, args.source)

        # Step 2: Add metadata columns
        log.info("=" * 70)
        log.info("STEP 2: Add Metadata Columns")
        log.info("=" * 70)

        df = add_metadata_columns(df, args.state, args.year_range)

        # Step 3: Connect to database
        log.info("=" * 70)
        log.info("STEP 3: Connect to Database")
        log.info("=" * 70)

        db_path = Path(args.database)
        db_path.parent.mkdir(parents=True, exist_ok=True)

        import duckdb
        conn = duckdb.connect(str(db_path))

        log.info(f"Connected to database: {db_path}")
        log.info(f"Database exists: {db_path.exists()}")

        # Step 4: Create table and indexes
        log.info("=" * 70)
        log.info("STEP 4: Create Table and Indexes")
        log.info("=" * 70)

        create_acs_table(conn)
        create_indexes(conn)

        # Step 5: Insert data
        log.info("=" * 70)
        log.info("STEP 5: Insert Data")
        log.info("=" * 70)

        rows_inserted, rows_deleted = insert_data(
            conn, df, args.mode, args.state, args.year_range
        )

        # Step 6: Gather statistics
        log.info("=" * 70)
        log.info("STEP 6: Gather Statistics")
        log.info("=" * 70)

        stats = get_table_statistics(conn, args.state, args.year_range)

        # Close connection
        conn.close()

        # Step 7: Summary
        end_time = datetime.now()
        elapsed = (end_time - start_time).total_seconds()

        log.info("=" * 70)
        log.info("INSERTION SUMMARY")
        log.info("=" * 70)
        log.info(f"State: {args.state}")
        log.info(f"Year Range: {args.year_range}")
        log.info(f"Mode: {args.mode}")
        log.info(f"Rows Inserted: {rows_inserted:,}")
        if rows_deleted > 0:
            log.info(f"Rows Deleted (replaced): {rows_deleted:,}")
        log.info(f"Total Rows (this state/year): {stats['rows_this_state_year']:,}")
        log.info(f"Total Rows (all data): {stats['rows_total']:,}")
        log.info(f"Distinct States: {stats['distinct_states']}")
        log.info(f"Distinct Year Ranges: {stats['distinct_year_ranges']}")
        log.info(f"Variables Stored: {len(stats['variables'])}")
        log.info(f"Age Distribution: {stats['age_distribution']}")
        log.info(f"Database: {db_path}")
        log.info(f"Elapsed Time: {elapsed:.2f} seconds")

        log.info("=" * 70)
        log.info("✓ INSERTION COMPLETE")
        log.info("=" * 70)

        return 0

    except FileNotFoundError as e:
        log.error("File not found", error=str(e))
        return 1

    except Exception as e:
        log.error(
            "Insertion failed",
            error=str(e),
            error_type=type(e).__name__
        )
        import traceback
        traceback.print_exc()
        return 1


if __name__ == "__main__":
    sys.exit(main())
