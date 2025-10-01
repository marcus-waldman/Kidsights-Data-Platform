#!/usr/bin/env python3
"""
Raw data insertion script for NE25 pipeline.

This script handles bulk insertion of extracted REDCap data into DuckDB tables,
replacing R's dbWriteTable functionality to avoid segmentation faults.

Supports CSV, Parquet, and Feather input formats, with Feather providing optimal
data type preservation for R/Python interoperability.
"""

import sys
import argparse
import pandas as pd
from pathlib import Path
from typing import Dict, Any

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


def insert_raw_data(
    data_file: str,
    table_name: str,
    db_ops: DatabaseOperations,
    pid: int = None
) -> bool:
    """
    Insert raw data from CSV, Parquet, or Feather file into database table.

    Args:
        data_file: Path to CSV, Parquet, or Feather file with data
        table_name: Target table name
        db_ops: Database operations instance
        pid: Project ID (for logging)

    Returns:
        True if successful, False otherwise
    """
    logger = setup_logging()

    try:
        # Read data from CSV, Parquet, or Feather
        data_path = Path(data_file)
        if not data_path.exists():
            logger.error(f"Data file not found: {data_file}")
            return False

        logger.info(f"Reading data from: {data_file}")

        # Determine file format and read accordingly
        if data_path.suffix.lower() == '.parquet':
            df = pd.read_parquet(data_file)
            logger.info(f"Read Parquet file with preserved data types")
        elif data_path.suffix.lower() == '.feather':
            df = pd.read_feather(data_file)
            logger.info(f"Read Feather file with optimal data type preservation")
        elif data_path.suffix.lower() == '.csv':
            df = pd.read_csv(data_file)
            logger.info(f"Read CSV file with inferred data types")
        else:
            logger.error(f"Unsupported file format: {data_path.suffix}")
            return False

        if df.empty:
            logger.warning(f"No data found in {data_file}")
            return True

        logger.info(f"Loaded {len(df)} records with {len(df.columns)} columns")

        # Insert data
        logger.info(f"Inserting data into table: {table_name}")
        success = db_ops.insert_dataframe(
            df=df,
            table_name=table_name,
            if_exists="replace",
            chunk_size=500
        )

        if success:
            final_count = db_ops.get_table_count(table_name)
            logger.info(f"Successfully inserted data. Table {table_name} now has {final_count} rows")
        else:
            logger.error(f"Failed to insert data into {table_name}")

        return success

    except Exception as e:
        logger.error(f"Error inserting raw data: {e}")
        return False


def insert_dictionary_data(
    dictionary_file: str,
    table_name: str,
    db_ops: DatabaseOperations,
    pid: int
) -> bool:
    """
    Insert data dictionary from CSV file into database table.

    Args:
        dictionary_file: Path to CSV file with dictionary data
        table_name: Target table name
        db_ops: Database operations instance
        pid: Project ID

    Returns:
        True if successful, False otherwise
    """
    logger = setup_logging()

    try:
        # Read dictionary data
        dict_path = Path(dictionary_file)
        if not dict_path.exists():
            logger.error(f"Dictionary file not found: {dictionary_file}")
            return False

        logger.info(f"Reading dictionary from: {dictionary_file}")

        # Support both CSV and Feather formats for dictionaries
        if dict_path.suffix.lower() == '.feather':
            df = pd.read_feather(dictionary_file)
        elif dict_path.suffix.lower() == '.csv':
            df = pd.read_csv(dictionary_file)
        else:
            logger.error(f"Unsupported dictionary file format: {dict_path.suffix}")
            return False

        if df.empty:
            logger.warning(f"No dictionary data found in {dictionary_file}")
            return True

        # Add PID column
        df['pid'] = pid
        df['created_at'] = pd.Timestamp.now()

        logger.info(f"Loaded {len(df)} dictionary fields for PID {pid}")

        # Insert data
        success = db_ops.insert_dataframe(
            df=df,
            table_name=table_name,
            if_exists="replace",
            chunk_size=500
        )

        if success:
            logger.info(f"Successfully inserted dictionary data for PID {pid}")
        else:
            logger.error(f"Failed to insert dictionary data for PID {pid}")

        return success

    except Exception as e:
        logger.error(f"Error inserting dictionary data: {e}")
        return False


def insert_eligibility_data(
    eligibility_file: str,
    table_name: str,
    db_ops: DatabaseOperations
) -> bool:
    """
    Insert eligibility data from CSV file into database table.

    Args:
        eligibility_file: Path to CSV file with eligibility data
        table_name: Target table name
        db_ops: Database operations instance

    Returns:
        True if successful, False otherwise
    """
    logger = setup_logging()

    try:
        # Read eligibility data
        elig_path = Path(eligibility_file)
        if not elig_path.exists():
            logger.error(f"Eligibility file not found: {eligibility_file}")
            return False

        logger.info(f"Reading eligibility data from: {eligibility_file}")
        df = pd.read_csv(eligibility_file)

        if df.empty:
            logger.warning(f"No eligibility data found in {eligibility_file}")
            return True

        logger.info(f"Loaded {len(df)} eligibility records")

        # Insert data using upsert to handle duplicates
        success = db_ops.upsert_data(
            df=df,
            table_name=table_name,
            key_columns=['record_id', 'pid', 'retrieved_date'],
            chunk_size=500
        )

        if success:
            final_count = db_ops.get_table_count(table_name)
            logger.info(f"Successfully upserted eligibility data. Table {table_name} now has {final_count} rows")
        else:
            logger.error(f"Failed to upsert eligibility data into {table_name}")

        return success

    except Exception as e:
        logger.error(f"Error inserting eligibility data: {e}")
        return False


def main():
    """Main function for command line execution."""
    parser = argparse.ArgumentParser(description="Insert raw data into NE25 database")
    parser.add_argument(
        "--data-file",
        required=True,
        help="Path to CSV file with raw data"
    )
    parser.add_argument(
        "--table-name",
        required=True,
        help="Target table name"
    )
    parser.add_argument(
        "--data-type",
        choices=["raw", "dictionary", "eligibility"],
        default="raw",
        help="Type of data being inserted"
    )
    parser.add_argument(
        "--pid",
        type=int,
        help="Project ID (required for dictionary data)"
    )
    parser.add_argument(
        "--config",
        default="config/sources/ne25.yaml",
        help="Configuration file path"
    )
    parser.add_argument(
        "--log-level",
        default="INFO",
        choices=["DEBUG", "INFO", "WARNING", "ERROR"],
        help="Logging level"
    )

    args = parser.parse_args()

    # Setup logging
    logger = setup_logging(level=args.log_level)

    try:
        # Initialize database components
        db_manager = DatabaseManager(args.config)
        db_ops = DatabaseOperations(db_manager)

        # Test connection
        if not db_manager.test_connection():
            logger.error("Database connection test failed")
            sys.exit(1)

        # Insert data based on type
        if args.data_type == "raw":
            success = insert_raw_data(args.data_file, args.table_name, db_ops, args.pid)
        elif args.data_type == "dictionary":
            if not args.pid:
                logger.error("PID is required for dictionary data")
                sys.exit(1)
            success = insert_dictionary_data(args.data_file, args.table_name, db_ops, args.pid)
        elif args.data_type == "eligibility":
            success = insert_eligibility_data(args.data_file, args.table_name, db_ops)
        else:
            logger.error(f"Unknown data type: {args.data_type}")
            sys.exit(1)

        if success:
            logger.info("Data insertion completed successfully")
            sys.exit(0)
        else:
            logger.error("Data insertion failed")
            sys.exit(1)

    except Exception as e:
        logger.error(f"Fatal error during data insertion: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()