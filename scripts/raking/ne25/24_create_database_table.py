"""
Phase 5, Tasks 5.6-5.9: Database Operations for Raking Targets

This script:
1. Creates the raking_targets_ne25 table schema
2. Inserts data from consolidated RDS file
3. Creates indexes for efficient querying
4. Tests database queries
"""

import sys
from pathlib import Path

# Add project root to Python path
project_root = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(project_root))

from python.db.connection import DatabaseManager
import pyarrow.feather as feather
import pandas as pd

def main():
    print("\n========================================")
    print("Phase 5: Database Operations")
    print("========================================\n")

    db = DatabaseManager()

    # Task 5.6: Create table schema
    print("[1] Creating table schema...")

    create_table_sql = """
    CREATE TABLE IF NOT EXISTS raking_targets_ne25 (
        target_id INTEGER PRIMARY KEY,
        survey VARCHAR NOT NULL,
        age_years INTEGER NOT NULL,
        estimand VARCHAR NOT NULL,
        description VARCHAR NOT NULL,
        data_source VARCHAR NOT NULL,
        estimator VARCHAR NOT NULL,
        estimate DOUBLE,
        se DOUBLE,
        lower_ci DOUBLE,
        upper_ci DOUBLE,
        sample_size INTEGER,
        estimation_date DATE NOT NULL,
        notes VARCHAR
    )
    """

    with db.get_connection() as conn:
        conn.execute(create_table_sql)
    print("    [OK] Table schema created\n")

    # Task 5.7: Load and insert data
    print("[2] Loading data from RDS file...")

    # Use R to convert RDS to Feather for Python reading
    import subprocess

    r_script = """
    library(arrow)
    data <- readRDS("data/raking/ne25/raking_targets_consolidated.rds")
    arrow::write_feather(data, "data/raking/ne25/temp_targets.feather")
    cat("[OK] Converted RDS to Feather\\n")
    """

    with open("scripts/temp/convert_targets.R", "w") as f:
        f.write(r_script)

    subprocess.run([
        r"C:\Program Files\R\R-4.5.1\bin\Rscript.exe",
        "scripts/temp/convert_targets.R"
    ], check=True)

    # Read feather file
    df = feather.read_feather("data/raking/ne25/temp_targets.feather")

    print(f"    Loaded: {len(df)} rows x {len(df.columns)} columns")
    print(f"    Columns: {', '.join(df.columns)}\n")

    # Task 5.7: Insert data
    print("[3] Inserting data into database...")

    with db.get_connection() as conn:
        # Clear existing data
        conn.execute("DELETE FROM raking_targets_ne25")

        # Convert DataFrame to list of tuples for insertion
        insert_sql = """
        INSERT INTO raking_targets_ne25 (
            target_id, survey, age_years, estimand, description,
            data_source, estimator, estimate, se, lower_ci, upper_ci,
            sample_size, estimation_date, notes
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """

        # Insert rows with proper NULL handling
        rows_inserted = 0
        for _, row in df.iterrows():
            # Convert row to list and handle NaN/None values properly
            row_values = []
            for i, val in enumerate(row):
                # Check if value is NaN or None
                if pd.isna(val):
                    row_values.append(None)
                else:
                    row_values.append(val)

            conn.execute(insert_sql, tuple(row_values))
            rows_inserted += 1

    print(f"    [OK] Inserted {rows_inserted} rows\n")

    # Task 5.8: Create indexes
    print("[4] Creating indexes...")

    indexes = [
        "CREATE INDEX IF NOT EXISTS idx_estimand ON raking_targets_ne25(estimand)",
        "CREATE INDEX IF NOT EXISTS idx_data_source ON raking_targets_ne25(data_source)",
        "CREATE INDEX IF NOT EXISTS idx_age_years ON raking_targets_ne25(age_years)",
        "CREATE INDEX IF NOT EXISTS idx_estimand_age ON raking_targets_ne25(estimand, age_years)"
    ]

    with db.get_connection() as conn:
        for idx_sql in indexes:
            conn.execute(idx_sql)

    print("    [OK] Created 4 indexes:")
    print("      - idx_estimand (on estimand)")
    print("      - idx_data_source (on data_source)")
    print("      - idx_age_years (on age_years)")
    print("      - idx_estimand_age (on estimand, age_years)\n")

    # Task 5.9: Test database queries
    print("[5] Testing database queries...\n")

    with db.get_connection(read_only=True) as conn:
        # Test 1: Count total rows
        test1 = conn.execute("SELECT COUNT(*) as n FROM raking_targets_ne25").fetchall()
        print(f"    Test 1 - Total rows: {test1[0][0]} (expected: 180)")

        # Test 2: Count by data source
        test2 = conn.execute("""
            SELECT data_source, COUNT(*) as n
            FROM raking_targets_ne25
            GROUP BY data_source
            ORDER BY data_source
        """).fetchall()
        print("    Test 2 - Rows by data source:")
        for row in test2:
            print(f"      {row[0]}: {row[1]}")

        # Test 3: Get specific estimand across all ages
        test3 = conn.execute("""
            SELECT age_years, estimate
            FROM raking_targets_ne25
            WHERE estimand = 'PHQ-2 Positive'
            ORDER BY age_years
        """).fetchall()
        print("    Test 3 - PHQ-2 Positive by age:")
        for row in test3:
            print(f"      Age {row[0]}: {row[1]:.4f}")

        # Test 4: Get all NSCH estimands for age 3
        test4 = conn.execute("""
            SELECT estimand, estimate
            FROM raking_targets_ne25
            WHERE data_source = 'NSCH' AND age_years = 3
            ORDER BY estimand
        """).fetchall()
        print("    Test 4 - NSCH estimands at age 3:")
        for row in test4:
            est_str = f"{row[1]:.4f}" if row[1] is not None else "NULL"
            print(f"      {row[0]}: {est_str}")

        # Test 5: Get income distribution for age 0
        test5 = conn.execute("""
            SELECT estimand, estimate
            FROM raking_targets_ne25
            WHERE estimand LIKE '%-%' AND age_years = 0
            ORDER BY target_id
        """).fetchall()
        print("    Test 5 - Income distribution at age 0:")
        for row in test5:
            print(f"      {row[0]}: {row[1]:.4f}")

        print("\n    [OK] All database queries executed successfully\n")

        # Summary
        print("[6] Summary:")
        summary = conn.execute("""
            SELECT
                COUNT(*) as total_rows,
                COUNT(DISTINCT estimand) as total_estimands,
                COUNT(DISTINCT data_source) as total_sources,
                SUM(CASE WHEN estimate IS NULL THEN 1 ELSE 0 END) as missing_estimates
            FROM raking_targets_ne25
        """).fetchall()

        print(f"    Total rows: {summary[0][0]}")
        print(f"    Total estimands: {summary[0][1]}")
        print(f"    Total data sources: {summary[0][2]}")
        print(f"    Missing estimates: {summary[0][3]}")
        print("    Table: raking_targets_ne25")
        print("    Location: data/duckdb/kidsights_local.duckdb\n")

    print("========================================")
    print("Tasks 5.6-5.9 Complete")
    print("========================================\n")

    # Clean up temp file
    Path("data/raking/ne25/temp_targets.feather").unlink(missing_ok=True)
    Path("scripts/temp/convert_targets.R").unlink(missing_ok=True)

if __name__ == "__main__":
    main()
