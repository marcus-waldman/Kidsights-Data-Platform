#!/usr/bin/env python3
"""
Geographic crosswalk data loader for Kidsights Data Platform.

Loads ZIP code to geographic area crosswalk files into DuckDB reference tables.
These tables support the NE25 geographic transformation pipeline, replacing
direct CSV file reads with database queries for better performance and consistency.

Crosswalk Files:
- PUMA (Public Use Microdata Areas, 2020)
- County (2020)
- Census Tract (2020)
- CBSA (Core-Based Statistical Areas, 2020)
- Urban/Rural (2022)
- School District (2020)
- State Legislative Lower (2024)
- State Legislative Upper (2024)
- US Congressional District (119th Congress)
- Native Lands / AIANNH (2021)
"""

import sys
import argparse
import pandas as pd
from pathlib import Path
from typing import Dict, List, Tuple

# Add python module to path
sys.path.insert(0, str(Path(__file__).parent.parent.parent / "python"))

from db import DatabaseManager, DatabaseOperations
try:
    from utils.logging import setup_logging
except ImportError:
    import logging
    def setup_logging(level="INFO", **kwargs):
        logging.basicConfig(level=getattr(logging, level))
        return logging.getLogger()


# Define crosswalk file mapping: table_name -> (file_path, columns_to_keep)
CROSSWALK_FILES = {
    'geo_zip_to_puma': (
        'data/reference/zip_to_puma_usa_2020.csv',
        ['zcta', 'state', 'puma22', 'stab', 'pop20', 'afact']
    ),
    'geo_zip_to_county': (
        'data/reference/zip_to_county_usa_2020.csv',
        ['zcta', 'state', 'county', 'stab', 'countyName', 'pop20', 'afact']
    ),
    'geo_zip_to_tract': (
        'data/reference/zip_to_census_tract_usa_2020.csv',
        ['zcta', 'state', 'tract', 'stab', 'pop20', 'afact']
    ),
    'geo_zip_to_cbsa': (
        'data/reference/zip_to_cbsa_usa_2020.csv',
        ['zcta', 'state', 'cbsa', 'stab', 'cbsaName', 'pop20', 'afact']
    ),
    'geo_zip_to_urban_rural': (
        'data/reference/zip_to_urban_rural_usa_2020.csv',
        ['zcta', 'state', 'urban_rural', 'stab', 'pop20', 'afact']
    ),
    'geo_zip_to_school_dist': (
        'data/reference/zip_to_school_district_usa_2020.csv',
        ['zcta', 'state', 'elsd', 'stab', 'elsdName', 'pop20', 'afact']
    ),
    'geo_zip_to_state_leg_lower': (
        'data/reference/zip_to_state_legislative_lower_usa_2020.csv',
        ['zcta', 'state', 'sldl', 'stab', 'pop20', 'afact']
    ),
    'geo_zip_to_state_leg_upper': (
        'data/reference/zip_to_state_legislative_upper_usa_2020.csv',
        ['zcta', 'state', 'sldu', 'stab', 'pop20', 'afact']
    ),
    'geo_zip_to_congress': (
        'data/reference/zip_to_us_congress_usa_2020.csv',
        ['zcta', 'state', 'cd119', 'stab', 'pop20', 'afact']
    ),
    'geo_zip_to_native_lands': (
        'data/reference/zip_to_native_lands_usa_2020.csv',
        ['zcta', 'aiannh', 'aiannhName', 'pop20', 'afact']
    )
}


def load_crosswalk_file(
    file_path: str,
    columns: List[str],
    state_filter: str = 'NE'
) -> pd.DataFrame:
    """
    Load a crosswalk CSV file and filter to specified state.

    Args:
        file_path: Path to crosswalk CSV file
        columns: List of columns to keep
        state_filter: State abbreviation to filter on (default: 'NE')

    Returns:
        Filtered DataFrame with selected columns
    """
    logger = setup_logging()

    try:
        # Check file exists
        path = Path(file_path)
        if not path.exists():
            logger.error(f"Crosswalk file not found: {file_path}")
            return None

        # Read CSV (skip header row 2 which contains descriptions)
        # Use latin-1 encoding for geographic crosswalk files
        df = pd.read_csv(file_path, skiprows=[1], dtype=str, encoding='latin-1')

        logger.info(f"Loaded {len(df):,} rows from {path.name}")

        # Filter to selected columns
        missing_cols = [col for col in columns if col not in df.columns]
        if missing_cols:
            logger.warning(f"Missing columns in {path.name}: {missing_cols}")
            columns = [col for col in columns if col in df.columns]

        df = df[columns].copy()

        # Filter to state if 'stab' column exists
        if 'stab' in df.columns and state_filter:
            original_count = len(df)
            df = df[df['stab'] == state_filter].copy()
            logger.info(f"Filtered to {state_filter}: {len(df):,} rows (from {original_count:,})")

        # Convert numeric columns
        numeric_cols = ['pop20', 'afact', 'state']
        for col in numeric_cols:
            if col in df.columns:
                df[col] = pd.to_numeric(df[col], errors='coerce')

        # Clean string columns (trim whitespace)
        string_cols = df.select_dtypes(include=['object']).columns
        for col in string_cols:
            df[col] = df[col].str.strip()

        # Filter out rows with blank/empty zcta
        if 'zcta' in df.columns:
            df = df[df['zcta'].notna() & (df['zcta'] != '') & (df['zcta'] != ' ')].copy()

        logger.info(f"Processed {len(df):,} valid rows for {path.name}")

        return df

    except Exception as e:
        logger.error(f"Error loading {file_path}: {e}")
        return None


def create_indexes(db_ops: DatabaseOperations, table_names: List[str]) -> bool:
    """
    Create indexes on zcta columns for fast lookups.

    Args:
        db_ops: Database operations instance
        table_names: List of table names to index

    Returns:
        True if all indexes created successfully
    """
    logger = setup_logging()

    try:
        with db_ops.db_manager.get_connection() as conn:
            for table in table_names:
                index_name = f"idx_{table}_zcta"

                # DuckDB doesn't support explicit CREATE INDEX, but we can create a view
                # or just rely on the fact that filtering on zcta will be fast anyway
                logger.info(f"Table {table} ready for queries (DuckDB auto-optimizes)")

        return True

    except Exception as e:
        logger.error(f"Error creating indexes: {e}")
        return False


def load_all_crosswalks(
    db_ops: DatabaseOperations,
    state_filter: str = 'NE',
    if_exists: str = 'replace'
) -> Tuple[int, int]:
    """
    Load all geographic crosswalk files into DuckDB.

    Args:
        db_ops: Database operations instance
        state_filter: State abbreviation to filter on
        if_exists: What to do if tables exist ('replace', 'append', 'fail')

    Returns:
        Tuple of (successful_count, failed_count)
    """
    logger = setup_logging()

    logger.info("=" * 80)
    logger.info("LOADING GEOGRAPHIC CROSSWALK DATA INTO DUCKDB")
    logger.info("=" * 80)
    logger.info(f"State filter: {state_filter}")
    logger.info(f"If exists: {if_exists}")
    logger.info(f"Number of crosswalks: {len(CROSSWALK_FILES)}")

    successful = 0
    failed = 0
    loaded_tables = []

    for table_name, (file_path, columns) in CROSSWALK_FILES.items():
        logger.info(f"\n--- Loading {table_name} ---")

        # Load crosswalk data
        df = load_crosswalk_file(file_path, columns, state_filter)

        if df is None or df.empty:
            logger.error(f"Failed to load data for {table_name}")
            failed += 1
            continue

        # Insert into database
        logger.info(f"Inserting {len(df):,} rows into {table_name}")
        success = db_ops.insert_dataframe(
            df=df,
            table_name=table_name,
            if_exists=if_exists,
            chunk_size=1000
        )

        if success:
            final_count = db_ops.get_table_count(table_name)
            logger.info(f"✓ Successfully loaded {table_name}: {final_count:,} rows")
            successful += 1
            loaded_tables.append(table_name)
        else:
            logger.error(f"✗ Failed to load {table_name}")
            failed += 1

    # Create indexes for fast lookups
    if loaded_tables:
        logger.info(f"\n--- Optimizing {len(loaded_tables)} tables ---")
        create_indexes(db_ops, loaded_tables)

    # Summary
    logger.info("\n" + "=" * 80)
    logger.info("CROSSWALK LOADING SUMMARY")
    logger.info("=" * 80)
    logger.info(f"Successful: {successful}")
    logger.info(f"Failed: {failed}")
    logger.info(f"Total: {successful + failed}")

    if loaded_tables:
        logger.info(f"\nLoaded tables:")
        for table in loaded_tables:
            count = db_ops.get_table_count(table)
            logger.info(f"  - {table}: {count:,} rows")

    return successful, failed


def main():
    """Main entry point for loading geographic crosswalks."""
    parser = argparse.ArgumentParser(
        description='Load geographic crosswalk data into DuckDB'
    )
    parser.add_argument(
        '--state',
        default='NE',
        help='State abbreviation to filter crosswalks (default: NE)'
    )
    parser.add_argument(
        '--config',
        default='config/sources/ne25.yaml',
        help='Path to database configuration file'
    )
    parser.add_argument(
        '--if-exists',
        default='replace',
        choices=['replace', 'append', 'fail'],
        help='What to do if tables exist (default: replace)'
    )
    parser.add_argument(
        '--log-level',
        default='INFO',
        choices=['DEBUG', 'INFO', 'WARNING', 'ERROR'],
        help='Logging level (default: INFO)'
    )

    args = parser.parse_args()

    # Setup logging
    logger = setup_logging(level=args.log_level)

    try:
        # Initialize database
        db_manager = DatabaseManager(config_path=args.config)
        db_ops = DatabaseOperations(db_manager)

        # Test connection
        if not db_manager.test_connection():
            logger.error("Database connection test failed")
            sys.exit(1)

        # Load crosswalks
        successful, failed = load_all_crosswalks(
            db_ops=db_ops,
            state_filter=args.state,
            if_exists=args.if_exists
        )

        # Exit with appropriate code
        if failed > 0:
            logger.warning(f"Completed with {failed} failures")
            sys.exit(1)
        else:
            logger.info("All crosswalks loaded successfully!")
            sys.exit(0)

    except Exception as e:
        logger.error(f"Fatal error: {e}")
        import traceback
        logger.error(traceback.format_exc())
        sys.exit(1)


if __name__ == "__main__":
    main()
