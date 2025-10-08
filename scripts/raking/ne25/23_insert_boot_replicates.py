"""
Phase 5, Task 5.3: Insert Bootstrap Replicates into Database

This script:
1. Creates the raking_targets_boot_replicates table schema
2. Inserts 720 bootstrap replicates (test mode) from consolidated RDS file
3. Creates indexes for efficient querying
4. Tests database queries and validates structure
"""

import sys
from pathlib import Path

# Add project root to Python path
project_root = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(project_root))

from python.db.connection import DatabaseManager
import pyarrow.feather as feather
import pandas as pd
import subprocess

def main():
    print("\n========================================")
    print("Phase 5: Insert Bootstrap Replicates")
    print("========================================\n")

    db = DatabaseManager()

    # Task 5.3.1: Create table schema
    print("[1] Creating raking_targets_boot_replicates table schema...")

    create_table_sql = """
    CREATE TABLE IF NOT EXISTS raking_targets_boot_replicates (
        survey VARCHAR NOT NULL,
        data_source VARCHAR NOT NULL,
        age INTEGER NOT NULL CHECK (age >= 0 AND age <= 5),
        estimand VARCHAR NOT NULL,
        replicate INTEGER NOT NULL CHECK (replicate >= 1),
        estimate DOUBLE,
        bootstrap_method VARCHAR NOT NULL,
        n_boot INTEGER NOT NULL,
        estimation_date DATE NOT NULL,
        created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (survey, data_source, estimand, age, replicate)
    )
    """

    with db.get_connection() as conn:
        conn.execute(create_table_sql)
    print("    [OK] Table schema created")
    print("    Primary key: (survey, data_source, estimand, age, replicate)\n")

    # Task 5.3.2: Load and insert data
    print("[2] Loading bootstrap replicates from RDS file...")

    # Use R to convert RDS to Feather for Python reading
    r_script = """
    library(arrow)
    data <- readRDS("data/raking/ne25/all_bootstrap_replicates.rds")

    # Remove consolidated_at timestamp (will use database default)
    if ("consolidated_at" %in% names(data)) {
      data <- dplyr::select(data, -consolidated_at)
    }

    arrow::write_feather(data, "data/raking/ne25/temp_boot_replicates.feather")
    cat("[OK] Converted RDS to Feather\\n")
    cat("    Rows:", nrow(data), "\\n")
    cat("    Columns:", paste(names(data), collapse = ", "), "\\n")
    """

    with open("scripts/temp/convert_boot_replicates.R", "w") as f:
        f.write(r_script)

    subprocess.run([
        r"C:\Program Files\R\R-4.5.1\bin\Rscript.exe",
        "scripts/temp/convert_boot_replicates.R"
    ], check=True)

    # Read feather file
    df = feather.read_feather("data/raking/ne25/temp_boot_replicates.feather")

    # Detect n_boot from data
    n_boot_detected = df['n_boot'].iloc[0]
    expected_rows = 30 * 6 * n_boot_detected  # 30 estimands × 6 ages × n_boot

    print(f"\n    Loaded: {len(df)} rows x {len(df.columns)} columns")
    print(f"    Columns: {', '.join(df.columns)}")
    print(f"    Detected n_boot: {n_boot_detected}")
    print(f"    Expected: {expected_rows} rows (30 estimands × 6 ages × {n_boot_detected} replicates)\n")

    if len(df) != expected_rows:
        print(f"    [ERROR] Expected {expected_rows} rows, got {len(df)}")
        return

    # Task 5.3.3: Insert data
    print("[3] Inserting bootstrap replicates into database...")

    with db.get_connection() as conn:
        # Clear existing data
        conn.execute("DELETE FROM raking_targets_boot_replicates")

        # Use DuckDB's direct DataFrame insertion for much better performance
        # Replace NaN with None for proper NULL handling
        df_clean = df.replace({pd.NA: None, float('nan'): None})

        # Register as temporary view and insert (exclude created_at - uses DEFAULT)
        conn.register('temp_boot_data', df_clean)
        conn.execute("""
            INSERT INTO raking_targets_boot_replicates (
                survey, data_source, age, estimand, replicate,
                estimate, bootstrap_method, n_boot, estimation_date
            )
            SELECT * FROM temp_boot_data
        """)

        rows_inserted = len(df_clean)
        conn.unregister('temp_boot_data')

    print(f"    [OK] Inserted {rows_inserted} rows (batch insert)\n")

    # Task 5.3.4: Create indexes
    print("[4] Creating indexes...")

    indexes = [
        "CREATE INDEX IF NOT EXISTS idx_boot_estimand_age ON raking_targets_boot_replicates(estimand, age)",
        "CREATE INDEX IF NOT EXISTS idx_boot_estimand_age_rep ON raking_targets_boot_replicates(estimand, age, replicate)",
        "CREATE INDEX IF NOT EXISTS idx_boot_data_source ON raking_targets_boot_replicates(data_source)"
    ]

    with db.get_connection() as conn:
        for idx_sql in indexes:
            conn.execute(idx_sql)

    print("    [OK] Created 3 indexes:")
    print("      - idx_boot_estimand_age (on estimand, age)")
    print("      - idx_boot_estimand_age_rep (on estimand, age, replicate)")
    print("      - idx_boot_data_source (on data_source)\n")

    # Task 5.3.5: Test database queries
    print("[5] Testing database queries and validation...\n")

    with db.get_connection(read_only=True) as conn:
        # Test 1: Count total rows
        test1 = conn.execute("SELECT COUNT(*) as n FROM raking_targets_boot_replicates").fetchall()
        print(f"    Test 1 - Total rows: {test1[0][0]} (expected: {expected_rows})")

        if test1[0][0] != expected_rows:
            print("      [ERROR] Row count mismatch!")
        else:
            print("      [OK] Row count verified")

        # Test 2: Count by data source
        test2 = conn.execute("""
            SELECT data_source, COUNT(*) as n
            FROM raking_targets_boot_replicates
            GROUP BY data_source
            ORDER BY data_source
        """).fetchall()
        print("\n    Test 2 - Rows by data source:")
        expected_by_source = {
            "ACS": 25 * 6 * n_boot_detected,
            "NHIS": 1 * 6 * n_boot_detected,
            "NSCH": 4 * 6 * n_boot_detected
        }
        for row in test2:
            expected = expected_by_source.get(row[0], 0)
            status = "[OK]" if row[1] == expected else "[ERROR]"
            print(f"      {status} {row[0]}: {row[1]} (expected: {expected})")

        # Test 3: Verify replicate counts
        test3 = conn.execute("""
            SELECT COUNT(DISTINCT replicate) as n_replicates
            FROM raking_targets_boot_replicates
        """).fetchall()
        print(f"\n    Test 3 - Number of replicates: {test3[0][0]} (expected: {n_boot_detected})")
        print(f"      [OK] n_boot = {n_boot_detected}" if test3[0][0] == n_boot_detected else f"      [ERROR] Expected {n_boot_detected} replicates")

        # Test 4: Check age coverage
        test4 = conn.execute("""
            SELECT COUNT(DISTINCT age) as n_ages,
                   MIN(age) as min_age,
                   MAX(age) as max_age
            FROM raking_targets_boot_replicates
        """).fetchall()
        print(f"\n    Test 4 - Age coverage: {test4[0][0]} ages (range: {test4[0][1]}-{test4[0][2]})")
        print(f"      [OK] Covers ages 0-5" if test4[0][0] == 6 else f"      [ERROR] Expected 6 ages")

        # Test 5: Verify estimand counts
        test5 = conn.execute("""
            SELECT COUNT(DISTINCT estimand) as n_estimands
            FROM raking_targets_boot_replicates
        """).fetchall()
        print(f"\n    Test 5 - Total estimands: {test5[0][0]} (expected: 30)")
        print("      Expected: 25 ACS + 1 NHIS + 4 NSCH = 30")

        # Test 6: Check for NULL estimates
        test6 = conn.execute("""
            SELECT data_source, estimand,
                   SUM(CASE WHEN estimate IS NULL THEN 1 ELSE 0 END) as n_null
            FROM raking_targets_boot_replicates
            GROUP BY data_source, estimand
            HAVING n_null > 0
            ORDER BY data_source, estimand
        """).fetchall()
        print("\n    Test 6 - NULL estimates by estimand:")
        if len(test6) == 0:
            print("      [OK] No NULL estimates found")
        else:
            for row in test6:
                print(f"      {row[0]} - {row[1]}: {row[2]} NULLs")
                if row[0] == "NSCH" and row[1] == "emotional_behavioral":
                    print("        (Expected: ages 0-2 are NA by design)")

        # Test 7: Get sample replicates for one estimand
        test7 = conn.execute("""
            SELECT replicate, age, estimate
            FROM raking_targets_boot_replicates
            WHERE estimand = 'sex_male' AND age = 0
            ORDER BY replicate
        """).fetchall()
        print("\n    Test 7 - Sample bootstrap replicates (sex_male, age 0):")
        for row in test7:
            print(f"      Replicate {row[0]}: {row[2]:.6f}")

        # Test 8: Verify shared bootstrap structure
        test8 = conn.execute("""
            SELECT r1.replicate,
                   r1.estimate as sex_estimate,
                   r2.estimate as race_estimate
            FROM raking_targets_boot_replicates r1
            JOIN raking_targets_boot_replicates r2
              ON r1.survey = r2.survey
              AND r1.data_source = r2.data_source
              AND r1.age = r2.age
              AND r1.replicate = r2.replicate
            WHERE r1.estimand = 'sex_male'
              AND r2.estimand = 'race_white_nh'
              AND r1.age = 0
              AND r1.data_source = 'ACS'
            ORDER BY r1.replicate
        """).fetchall()
        print("\n    Test 8 - Verify shared bootstrap structure (ACS, age 0):")
        print("      Comparing sex_male and race_white_nh replicates:")
        for row in test8:
            print(f"      Rep {row[0]}: sex={row[1]:.4f}, race={row[2]:.4f}")

        # Test 9: Check primary key uniqueness
        test9 = conn.execute("""
            SELECT COUNT(*) as total_rows,
                   COUNT(DISTINCT survey || data_source || estimand || age || replicate) as unique_keys
            FROM raking_targets_boot_replicates
        """).fetchall()
        print(f"\n    Test 9 - Primary key uniqueness:")
        print(f"      Total rows: {test9[0][0]}")
        print(f"      Unique keys: {test9[0][1]}")
        if test9[0][0] == test9[0][1]:
            print("      [OK] All rows have unique primary keys")
        else:
            print("      [ERROR] Duplicate primary keys detected!")

        print("\n    [OK] All database queries executed successfully\n")

        # Summary
        print("[6] Summary:")
        summary = conn.execute("""
            SELECT
                COUNT(*) as total_rows,
                COUNT(DISTINCT estimand) as total_estimands,
                COUNT(DISTINCT data_source) as total_sources,
                COUNT(DISTINCT replicate) as total_replicates,
                SUM(CASE WHEN estimate IS NULL THEN 1 ELSE 0 END) as missing_estimates
            FROM raking_targets_boot_replicates
        """).fetchall()

        print(f"    Total rows: {summary[0][0]}")
        print(f"    Total estimands: {summary[0][1]}")
        print(f"    Total data sources: {summary[0][2]}")
        print(f"    Total replicates: {summary[0][3]}")
        print(f"    Missing estimates: {summary[0][4]}")
        print("      (Note: NSCH emotional_behavioral has NA for ages 0-2 by design)")
        print("    Table: raking_targets_boot_replicates")
        print("    Location: data/duckdb/kidsights_local.duckdb\n")

    print("========================================")
    print("Phase 5, Task 5.3 Complete")
    print("========================================\n")

    print(f"Current configuration: n_boot = {n_boot_detected} ({len(df)} rows)")
    if n_boot_detected < 4096:
        print("\nProduction mode (n_boot = 4096) will have:")
        print("  - ACS:  614,400 rows (25 estimands x 6 ages x 4096 replicates)")
        print("  - NHIS:  24,576 rows (1 estimand x 6 ages x 4096 replicates)")
        print("  - NSCH:  98,304 rows (4 estimands x 6 ages x 4096 replicates)")
        print("  - TOTAL: 737,280 rows\n")

    print("Next steps:")
    print("  1. Run validation queries to verify bootstrap structure")
    print("  2. Update database schema documentation")
    print("  3. Complete Phase 5 checkpoint\n")

    # Clean up temp files
    Path("data/raking/ne25/temp_boot_replicates.feather").unlink(missing_ok=True)
    Path("scripts/temp/convert_boot_replicates.R").unlink(missing_ok=True)

if __name__ == "__main__":
    main()
