"""
Setup Imputation Schema

Creates database tables for storing multiple imputations of variables with
missing or uncertain values.

Usage:
    python scripts/imputation/00_setup_imputation_schema.py --study-id ne25
    python scripts/imputation/00_setup_imputation_schema.py --study-id ia26
"""

import sys
import argparse
from pathlib import Path

# Add project root to path
project_root = Path(__file__).parent.parent.parent
sys.path.insert(0, str(project_root))

from python.db.connection import DatabaseManager
from python.imputation.config import get_study_config, get_table_prefix


def setup_imputation_schema(study_id="ne25"):
    """
    Create imputation tables in the database for a specific study

    Parameters
    ----------
    study_id : str
        Study identifier (e.g., "ne25", "ia26", "co27")
    """
    print(f"Setting up imputation schema for {study_id.upper()}...")
    print("=" * 60)

    # Load study-specific configuration
    config = get_study_config(study_id)
    table_prefix = get_table_prefix(study_id)

    print(f"[OK] Configuration loaded for {config['study_name']}")
    print(f"     - Study ID: {study_id}")
    print(f"     - Table prefix: {table_prefix}")
    print(f"     - Number of imputations (M): {config['n_imputations']}")
    print(f"     - Geography variables: {', '.join(config['geography']['variables'])}")
    print(f"     - Sociodem variables: {', '.join(config['sociodemographic']['variables'])}")

    # Connect to database
    db = DatabaseManager()
    print(f"[OK] Connected to database: {config['database']['db_path']}")

    # Define SQL scripts to execute
    sql_scripts = [
        "create_imputation_tables.sql",      # Geographic imputation tables
        "create_sociodem_imputation_tables.sql"  # Sociodemographic imputation tables
    ]

    total_statements = 0

    # Execute each SQL script
    for script_name in sql_scripts:
        sql_path = project_root / "sql" / "imputation" / script_name
        if not sql_path.exists():
            raise FileNotFoundError(f"SQL script not found: {sql_path}")

        with open(sql_path, 'r') as f:
            sql_script = f.read()

        print(f"\n[OK] Loaded SQL script: {script_name}")

        # Execute SQL statements one by one with error reporting
        statements = [stmt.strip() for stmt in sql_script.split(';') if stmt.strip()]
        print(f"[INFO] Executing {len(statements)} SQL statements...")

        with db.get_connection() as conn:
            for i, statement in enumerate(statements, 1):
                # Skip empty or comment-only statements
                if not statement or all(line.strip().startswith('--') for line in statement.split('\n') if line.strip()):
                    continue

                try:
                    conn.execute(statement)
                    # Show first 50 chars of statement for debugging
                    stmt_preview = statement[:50].replace('\n', ' ')
                    print(f"  [{i}/{len(statements)}] OK: {stmt_preview}...")
                    total_statements += 1
                except Exception as e:
                    print(f"  [{i}/{len(statements)}] FAIL: {e}")
                    print(f"  Statement: {statement[:200]}")
                    # Continue on error (tables may already exist)

    print(f"\n[OK] Schema creation complete ({total_statements} statements executed)")

    # Verify tables were created
    tables = db.list_tables()
    imputation_tables = [t for t in tables if t.startswith(f'{table_prefix}_')]

    print(f"\n[OK] Imputation tables created ({len(imputation_tables)} tables):")

    # Separate geographic and sociodemographic tables
    geo_table_names = [f'{table_prefix}_puma', f'{table_prefix}_county', f'{table_prefix}_census_tract']
    geo_tables = [t for t in imputation_tables if t in geo_table_names]
    sociodem_tables = [t for t in imputation_tables if t not in geo_tables]

    print(f"\n  Geographic imputation tables:")
    for table in sorted(geo_tables):
        print(f"     - {table}")

    print(f"\n  Sociodemographic imputation tables:")
    for table in sorted(sociodem_tables):
        print(f"     - {table}")

    # Check if metadata table exists
    if 'imputation_metadata' in tables:
        print(f"\n[OK] Metadata table created: imputation_metadata")
    else:
        print(f"\n[WARN] Metadata table not found")

    print("\n" + "=" * 60)
    print("Setup complete!")
    print(f"\nNext steps for {study_id.upper()}:")
    print(f"  1. Run: python scripts/imputation/{study_id}/01_impute_geography.py")
    print(f"  2. Run: Rscript scripts/imputation/{study_id}/02_impute_sociodemographic.R")
    print(f"  3. Run: python scripts/imputation/{study_id}/02b_insert_sociodem_imputations.py")
    print(f"  4. Verify: python -m python.imputation.helpers")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Setup imputation database schema for a specific study"
    )
    parser.add_argument(
        "--study-id",
        type=str,
        default="ne25",
        help="Study identifier (e.g., ne25, ia26, co27). Default: ne25"
    )
    args = parser.parse_args()

    setup_imputation_schema(study_id=args.study_id)
