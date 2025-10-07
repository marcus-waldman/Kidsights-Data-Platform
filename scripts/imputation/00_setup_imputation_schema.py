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

    # Connect to database
    db = DatabaseManager()
    print(f"[OK] Connected to database: {config['database']['db_path']}")

    # Load SQL script
    sql_path = project_root / "sql" / "imputation" / "create_imputation_tables.sql"
    if not sql_path.exists():
        raise FileNotFoundError(f"SQL script not found: {sql_path}")

    with open(sql_path, 'r') as f:
        sql_script = f.read()

    print(f"[OK] Loaded SQL script: {sql_path.name}")

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
            except Exception as e:
                print(f"  [{i}/{len(statements)}] FAIL: {e}")
                print(f"  Statement: {statement[:200]}")
                # Continue on error (tables may already exist)

    print(f"\n[OK] Schema creation complete")

    # Verify tables were created
    tables = db.list_tables()
    imputation_tables = [t for t in tables if t.startswith('imputed_')]

    print(f"\n[OK] Imputation tables created:")
    for table in sorted(imputation_tables):
        print(f"     - {table}")

    # Check if metadata table exists
    if 'imputation_metadata' in tables:
        print(f"[OK] Metadata table created: imputation_metadata")
    else:
        print(f"[WARN] Metadata table not found")

    print("\n" + "=" * 60)
    print("Setup complete!")
    print("\nNext steps:")
    print("  1. Run: python scripts/imputation/01_impute_geography.py")
    print("  2. Verify: python scripts/imputation/02_validate_imputations.py")


if __name__ == "__main__":
    setup_imputation_schema()
