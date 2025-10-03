"""
NSCH Metadata Loading Script

Loads NSCH metadata from JSON files into DuckDB database.
Populates nsch_variables and nsch_value_labels tables.

Usage:
    # Load 2023 metadata
    python pipelines/python/nsch/load_nsch_metadata.py --year 2023

    # Load with custom database path
    python pipelines/python/nsch/load_nsch_metadata.py --year 2023 \
        --database data/duckdb/custom.duckdb

    # Replace existing metadata (default)
    python pipelines/python/nsch/load_nsch_metadata.py --year 2023 --mode replace

    # Append to existing metadata
    python pipelines/python/nsch/load_nsch_metadata.py --year 2023 --mode append

Command-line Arguments:
    --year: Survey year (required, 2016-2023)
    --mode: Insert mode - 'replace' (default) or 'append'
    --database: Database path (defaults to data/duckdb/kidsights_local.duckdb)
    --verbose: Enable verbose logging

Output:
    - Inserts into nsch_variables table
    - Inserts into nsch_value_labels table
    - Generates insertion summary statistics

Author: Kidsights Data Platform
Date: 2025-10-03
"""

import argparse
import sys
import json
import logging
import structlog
import pandas as pd
import duckdb
from pathlib import Path
from datetime import datetime
from typing import Dict, Any, List, Tuple

# Configure structured logging
log = structlog.get_logger()


def parse_arguments() -> argparse.Namespace:
    """Parse command-line arguments.

    Returns:
        argparse.Namespace: Parsed arguments
    """
    parser = argparse.ArgumentParser(
        description="Load NSCH metadata into DuckDB database",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Load 2023 metadata
  python pipelines/python/nsch/load_nsch_metadata.py --year 2023

  # Append 2022 metadata
  python pipelines/python/nsch/load_nsch_metadata.py --year 2022 --mode append

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
        help="Insert mode: 'replace' removes existing year data first, 'append' adds to existing (default: replace)"
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


def load_metadata_json(year: int) -> Dict[str, Any]:
    """Load metadata JSON file.

    Args:
        year: Survey year

    Returns:
        Dict: Metadata dictionary

    Raises:
        FileNotFoundError: If metadata file doesn't exist
    """
    metadata_path = Path(f"data/nsch/{year}/metadata.json")

    log.info("Loading metadata JSON", path=str(metadata_path))

    if not metadata_path.exists():
        raise FileNotFoundError(
            f"Metadata file not found: {metadata_path}\n\n"
            f"Please run SPSS conversion first:\n"
            f"  python pipelines/python/nsch/load_nsch_spss.py --year {year}"
        )

    with open(metadata_path, 'r', encoding='utf-8') as f:
        metadata = json.load(f)

    log.info(
        "Metadata JSON loaded",
        year=metadata['year'],
        file_name=metadata['file_name'],
        variable_count=metadata['variable_count'],
        record_count=metadata['record_count']
    )

    return metadata


def prepare_variables_df(metadata: Dict[str, Any]) -> pd.DataFrame:
    """Prepare DataFrame for nsch_variables table.

    Args:
        metadata: Metadata dictionary

    Returns:
        pd.DataFrame: Variables data ready for insertion
    """
    year = metadata['year']
    source_file = metadata['file_name']
    variables = metadata['variables']

    rows = []

    for position, (var_name, var_info) in enumerate(variables.items()):
        row = {
            'year': year,
            'variable_name': var_name,
            'variable_label': var_info.get('label', ''),
            'variable_type': 'numeric',  # All NSCH SPSS variables are numeric
            'source_file': source_file,
            'position': position,
            'loaded_at': datetime.now()
        }
        rows.append(row)

    df = pd.DataFrame(rows)

    log.info("Variables DataFrame prepared", rows=len(df))

    return df


def prepare_value_labels_df(metadata: Dict[str, Any]) -> pd.DataFrame:
    """Prepare DataFrame for nsch_value_labels table.

    Args:
        metadata: Metadata dictionary

    Returns:
        pd.DataFrame: Value labels data ready for insertion
    """
    year = metadata['year']
    variables = metadata['variables']

    rows = []

    for var_name, var_info in variables.items():
        if var_info.get('has_value_labels', False):
            value_labels = var_info.get('value_labels', {})

            for value, label in value_labels.items():
                row = {
                    'year': year,
                    'variable_name': var_name,
                    'value': str(value),
                    'label': label,
                    'loaded_at': datetime.now()
                }
                rows.append(row)

    df = pd.DataFrame(rows)

    log.info("Value labels DataFrame prepared", rows=len(df))

    return df


def create_metadata_tables(conn) -> None:
    """Create metadata tables using schema SQL.

    Args:
        conn: DuckDB connection
    """
    log.info("Creating metadata tables")

    schema_path = Path("config/sources/nsch/database_schema.sql")

    if not schema_path.exists():
        raise FileNotFoundError(f"Schema file not found: {schema_path}")

    # Read schema SQL
    with open(schema_path, 'r', encoding='utf-8') as f:
        schema_sql = f.read()

    # Execute schema SQL (creates tables if they don't exist)
    conn.execute(schema_sql)

    log.info("Metadata tables created (if not exists)")


def delete_existing_metadata(conn, year: int) -> Tuple[int, int]:
    """Delete existing metadata for a year (replace mode).

    Args:
        conn: DuckDB connection
        year: Survey year

    Returns:
        Tuple[int, int]: (variables deleted, value_labels deleted)
    """
    log.info("Deleting existing metadata", year=year, mode="replace")

    # Delete value labels first (foreign key constraint)
    conn.execute(
        "DELETE FROM nsch_value_labels WHERE year = ?",
        [year]
    )

    # Delete variables
    conn.execute(
        "DELETE FROM nsch_variables WHERE year = ?",
        [year]
    )

    # Get counts (simplified - just log that we deleted)
    log.info("Existing metadata deleted", year=year)

    return 0, 0  # DuckDB doesn't return row counts easily


def insert_metadata(conn, variables_df: pd.DataFrame, value_labels_df: pd.DataFrame) -> None:
    """Insert metadata into database.

    Args:
        conn: DuckDB connection
        variables_df: Variables data
        value_labels_df: Value labels data
    """
    log.info("Inserting metadata into database")

    # Register DataFrames as temporary views
    conn.register("variables_df", variables_df)

    # Insert variables
    conn.execute(
        """
        INSERT INTO nsch_variables
        (year, variable_name, variable_label, variable_type, source_file, position, loaded_at)
        SELECT * FROM variables_df
        """
    )

    # Unregister temp view
    conn.unregister("variables_df")

    log.info("Variables inserted", rows=len(variables_df))

    # Insert value labels (if any)
    if len(value_labels_df) > 0:
        # Register value labels DataFrame
        conn.register("value_labels_df", value_labels_df)

        conn.execute(
            """
            INSERT INTO nsch_value_labels
            (year, variable_name, value, label, loaded_at)
            SELECT * FROM value_labels_df
            """
        )

        # Unregister temp view
        conn.unregister("value_labels_df")

        log.info("Value labels inserted", rows=len(value_labels_df))
    else:
        log.info("No value labels to insert")


def validate_insertion(conn, year: int, expected_var_count: int) -> None:
    """Validate metadata was inserted correctly.

    Args:
        conn: DuckDB connection
        year: Survey year
        expected_var_count: Expected number of variables
    """
    log.info("Validating insertion", year=year)

    # Check variable count
    var_count = conn.execute(
        "SELECT COUNT(*) FROM nsch_variables WHERE year = ?",
        [year]
    ).fetchone()[0]

    # Check value label count
    label_count = conn.execute(
        "SELECT COUNT(*) FROM nsch_value_labels WHERE year = ?",
        [year]
    ).fetchone()[0]

    # Check sample variable
    sample_var = conn.execute(
        "SELECT * FROM nsch_variables WHERE year = ? LIMIT 1",
        [year]
    ).fetchdf()

    log.info(
        "Validation complete",
        year=year,
        variables_in_db=var_count,
        expected_variables=expected_var_count,
        value_labels_in_db=label_count
    )

    if var_count != expected_var_count:
        log.warning(
            "Variable count mismatch",
            expected=expected_var_count,
            actual=var_count
        )

    # Display sample variable
    if len(sample_var) > 0:
        log.info("Sample variable", data=sample_var.to_dict('records')[0])


def main() -> int:
    """Main execution function.

    Returns:
        int: Exit code (0 for success, 1 for failure)
    """
    # Parse arguments
    args = parse_arguments()

    year = args.year
    mode = args.mode
    database_path = args.database
    verbose = args.verbose

    # Configure logging
    if verbose:
        structlog.configure(
            wrapper_class=structlog.make_filtering_bound_logger(logging.DEBUG)
        )

    log.info(
        "Starting NSCH metadata loading",
        year=year,
        mode=mode,
        database=database_path
    )

    try:
        # Validate year
        validate_year(year)

        # Load metadata JSON
        metadata = load_metadata_json(year)

        # Prepare DataFrames
        variables_df = prepare_variables_df(metadata)
        value_labels_df = prepare_value_labels_df(metadata)

        # Connect to database
        db_path = Path(database_path)
        db_path.parent.mkdir(parents=True, exist_ok=True)

        conn = duckdb.connect(str(db_path))
        log.info("Connected to database", path=str(db_path))

        # Create tables (if not exist)
        create_metadata_tables(conn)

        # Delete existing metadata if replace mode
        if mode == "replace":
            delete_existing_metadata(conn, year)

        # Insert metadata
        insert_metadata(conn, variables_df, value_labels_df)

        # Validate insertion
        validate_insertion(conn, year, metadata['variable_count'])

        # Close connection
        conn.close()

        log.info(
            "NSCH metadata loading complete",
            year=year,
            variables_inserted=len(variables_df),
            value_labels_inserted=len(value_labels_df)
        )

        return 0

    except Exception as e:
        log.error("NSCH metadata loading failed", error=str(e))
        import traceback
        traceback.print_exc()
        return 1


if __name__ == "__main__":
    sys.exit(main())
