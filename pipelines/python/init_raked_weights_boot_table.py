#!/usr/bin/env python3
"""
Initialize the ne25_raked_weights_boot table in DuckDB.

Long-format storage for the NE25 Bucket 3 Bayesian-bootstrap weights
(M=5 imputations x B=200 bootstrap draws = 1,000 weight vectors, each
of length N ~ 2,645 => ~2.6M rows).

Schema:
    (pid INTEGER, record_id INTEGER, study_id VARCHAR,
     imputation_m INTEGER, boot_b INTEGER, calibrated_weight DOUBLE)
    PRIMARY KEY (pid, record_id, imputation_m, boot_b)
    INDEX on imputation_m
    INDEX on (imputation_m, boot_b)

Idempotent: CREATE TABLE IF NOT EXISTS + CREATE INDEX IF NOT EXISTS.

Usage:
    python pipelines/python/init_raked_weights_boot_table.py
"""

import sys
import os
from pathlib import Path

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
CREATE TABLE IF NOT EXISTS ne25_raked_weights_boot (
    pid               INTEGER  NOT NULL,
    record_id         INTEGER  NOT NULL,
    study_id          VARCHAR,
    imputation_m      INTEGER  NOT NULL,
    boot_b            INTEGER  NOT NULL,
    calibrated_weight DOUBLE   NOT NULL,
    PRIMARY KEY (pid, record_id, imputation_m, boot_b)
);
"""

DDL_INDEX_M = """
CREATE INDEX IF NOT EXISTS idx_ne25_raked_weights_boot_m
    ON ne25_raked_weights_boot (imputation_m);
"""

DDL_INDEX_MB = """
CREATE INDEX IF NOT EXISTS idx_ne25_raked_weights_boot_mb
    ON ne25_raked_weights_boot (imputation_m, boot_b);
"""


def init_boot_table(db_manager: DatabaseManager) -> bool:
    logger = setup_logging()
    logger.info("Creating ne25_raked_weights_boot table...")

    try:
        with db_manager.get_connection() as conn:
            conn.execute(DDL_CREATE_TABLE)
            logger.info("[OK] ne25_raked_weights_boot table ready")

            conn.execute(DDL_INDEX_M)
            logger.info("[OK] Index on imputation_m ready")

            conn.execute(DDL_INDEX_MB)
            logger.info("[OK] Index on (imputation_m, boot_b) ready")

            result = conn.execute(
                "SELECT column_name, data_type "
                "FROM information_schema.columns "
                "WHERE table_name = 'ne25_raked_weights_boot' "
                "ORDER BY ordinal_position"
            ).fetchall()

            logger.info("Schema:")
            for col_name, col_type in result:
                logger.info(f"  - {col_name}: {col_type}")

            row_count = conn.execute(
                "SELECT COUNT(*) FROM ne25_raked_weights_boot"
            ).fetchone()[0]
            logger.info(f"Current row count: {row_count} (expected 0 on first run)")

            # Indicative: when populated, expect ~5 imputations x 200 boots x
            # N_per_imputation rows total (~2.6M for NE25).
            logger.info("Expected populated size: ~2.6M rows (5 x 200 x ~2,645)")

        return True

    except Exception as e:
        logger.error(f"[ERROR] Failed to create ne25_raked_weights_boot: {e}")
        return False


def main():
    db_manager = DatabaseManager()
    print(f"[INFO] Database path: {db_manager.database_path}")

    success = init_boot_table(db_manager)

    if success:
        print("[OK] ne25_raked_weights_boot table ready")
        sys.exit(0)
    else:
        print("[ERROR] Failed to initialize ne25_raked_weights_boot table")
        sys.exit(1)


if __name__ == "__main__":
    main()
