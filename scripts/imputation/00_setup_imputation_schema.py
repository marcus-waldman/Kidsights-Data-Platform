"""
Setup Imputation Schema

Creates database tables for storing multiple imputations of variables with
missing or uncertain values.

Usage:
    python scripts/imputation/00_setup_imputation_schema.py
"""

import sys
from pathlib import Path

# Add project root to path
project_root = Path(__file__).parent.parent.parent
sys.path.insert(0, str(project_root))

from python.db.connection import DatabaseManager
from python.imputation.config import get_imputation_config


def setup_imputation_schema():
    """
    Create imputation tables in the database
    """
    print("Setting up imputation schema...")
    print("=" * 60)

    # Load configuration
    config = get_imputation_config()
    print(f"[OK] Configuration loaded")
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
    imputation_tables = [t for t in tables if t.startswith('imputed_')]

    print(f"\n[OK] Imputation tables created ({len(imputation_tables)} tables):")

    # Separate geographic and sociodemographic tables
    geo_tables = [t for t in imputation_tables if t in ['imputed_puma', 'imputed_county', 'imputed_census_tract']]
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
    print("\nNext steps:")
    print("  1. Run: python scripts/imputation/01_impute_geography.py")
    print("  2. Run: scripts/imputation/02_impute_sociodemographic.R")
    print("  3. Verify: python -m python.imputation.helpers")


if __name__ == "__main__":
    setup_imputation_schema()
