#!/usr/bin/env python3
"""
Database initialization script for NE25 pipeline.

This script replaces R's schema initialization functionality to avoid
DuckDB segmentation faults. It creates all necessary tables and indexes
for the NE25 pipeline.
"""

import sys
import argparse
import os
from pathlib import Path

# Add python module to path
sys.path.insert(0, str(Path(__file__).parent.parent.parent / "python"))

try:
    from db import DatabaseManager
    from utils.logging import setup_logging
except ImportError as e:
    print(f"Import error: {e}")
    print("Current working directory:", os.getcwd())
    print("Python path:", sys.path)
    sys.exit(1)


def init_ne25_schema(db_manager: DatabaseManager) -> bool:
    """
    Initialize the NE25 database schema.

    Args:
        db_manager: Database manager instance

    Returns:
        True if successful, False otherwise
    """
    logger = setup_logging()

    # Path to schema file
    schema_file = Path(__file__).parent.parent.parent / "schemas" / "landing" / "ne25_minimal.sql"

    if not schema_file.exists():
        logger.error(f"Schema file not found: {schema_file}")
        return False

    logger.info("Initializing NE25 database schema...")
    logger.info(f"Database path: {db_manager.database_path}")
    logger.info(f"Schema file: {schema_file}")

    # Execute schema file
    success = db_manager.execute_sql_file(str(schema_file))

    if success:
        logger.info("Successfully initialized NE25 schema")

        # Verify tables were created
        tables = db_manager.list_tables()
        expected_tables = [
            "ne25_raw", "ne25_eligibility", "ne25_harmonized",
            "ne25_data_dictionary", "ne25_pipeline_log",
            "ne25_transformed", "ne25_metadata"
        ]

        created_tables = [t for t in expected_tables if t in tables]
        logger.info(f"Created {len(created_tables)} tables: {', '.join(created_tables)}")

        if len(created_tables) < len(expected_tables):
            missing = [t for t in expected_tables if t not in tables]
            logger.warning(f"Missing tables: {', '.join(missing)}")

    else:
        logger.error("Failed to initialize NE25 schema")

    return success


def main():
    """Main function for command line execution."""
    parser = argparse.ArgumentParser(description="Initialize NE25 database schema")
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
        # Initialize database manager
        db_manager = DatabaseManager(args.config)

        # Test connection (skip for new databases as they will be created)
        if db_manager.database_exists():
            if not db_manager.test_connection():
                logger.error("Database connection test failed")
                sys.exit(1)
        else:
            logger.info("Database does not exist yet - will be created during schema initialization")

        # Initialize schema
        success = init_ne25_schema(db_manager)

        if success:
            logger.info("Database initialization completed successfully")
            sys.exit(0)
        else:
            logger.error("Database initialization failed")
            sys.exit(1)

    except Exception as e:
        logger.error(f"Fatal error during database initialization: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()