#!/usr/bin/env python3
"""
Initialize the ne25_raked_weights table in DuckDB.

Creates the long-format storage table for M=5 multi-imputation calibrated
raking weights, consistent with the ne25_imputed_* table convention.

Schema:
    (pid INTEGER, record_id INTEGER, study_id VARCHAR,
     imputation_m INTEGER, calibrated_weight DOUBLE)
    PRIMARY KEY (pid, record_id, imputation_m)
    INDEX on imputation_m

This script is idempotent: it uses CREATE TABLE IF NOT EXISTS and is safe
to run repeatedly. It does NOT populate the table -- population is handled
by scripts/raking/ne25/34_store_raked_weights_long.R after the Stan refits.

Usage:
    python pipelines/python/init_raked_weights_table.py
"""

import sys
import os
from pathlib import Path

# Add python module to path
sys.path.insert(0, str(Path(__file__).parent.parent.parent / "python"))

try:
    from db import DatabaseManager
    from utils.logging import setup_logging
except ImportError as e:
    print(f"[ERROR] Import error: {e}")
    print(f"Current working directory: {os.getcwd()}")
    print(f"Python path: {sys.path}")
    sys.exit(1)


DDL_CREATE_TABLE = """
CREATE TABLE IF NOT EXISTS ne25_raked_weights (
    pid               INTEGER  NOT NULL,
    record_id         INTEGER  NOT NULL,
    study_id          VARCHAR,
    imputation_m      INTEGER  NOT NULL,
    calibrated_weight DOUBLE   NOT NULL,
    PRIMARY KEY (pid, record_id, imputation_m)
);
"""

DDL_CREATE_INDEX = """
CREATE INDEX IF NOT EXISTS idx_ne25_raked_weights_imputation_m
    ON ne25_raked_weights (imputation_m);
"""


def init_raked_weights_table(db_manager: DatabaseManager) -> bool:
    """Create the ne25_raked_weights table and its imputation_m index."""
    logger = setup_logging()
    logger.info("Creating ne25_raked_weights table...")

    try:
        with db_manager.get_connection() as conn:
            conn.execute(DDL_CREATE_TABLE)
            logger.info("[OK] ne25_raked_weights table created (or already existed)")

            conn.execute(DDL_CREATE_INDEX)
            logger.info("[OK] Index on imputation_m created (or already existed)")

            # Verify
            result = conn.execute(
                "SELECT column_name, data_type "
                "FROM information_schema.columns "
                "WHERE table_name = 'ne25_raked_weights' "
                "ORDER BY ordinal_position"
            ).fetchall()

            logger.info("Schema:")
            for col_name, col_type in result:
                logger.info(f"  - {col_name}: {col_type}")

            row_count = conn.execute(
                "SELECT COUNT(*) FROM ne25_raked_weights"
            ).fetchone()[0]
            logger.info(f"Current row count: {row_count} (expected 0 on first run)")

        return True

    except Exception as e:
        logger.error(f"[ERROR] Failed to create ne25_raked_weights table: {e}")
        return False


def main():
    db_manager = DatabaseManager()

    print(f"[INFO] Database path: {db_manager.database_path}")

    success = init_raked_weights_table(db_manager)

    if success:
        print("[OK] ne25_raked_weights table ready")
        sys.exit(0)
    else:
        print("[ERROR] Failed to initialize ne25_raked_weights table")
        sys.exit(1)


if __name__ == "__main__":
    main()
