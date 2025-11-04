"""
=============================================================================
Database Insertion Script: Psychosocial IRT Scores
=============================================================================
Purpose: Insert psychosocial bifactor MAP scores from Feather files into DuckDB

Input: Feather files from 02_score_psychosocial.R (temp directory)
Output: Rows inserted into ne25_irt_scores_psychosocial table

Execution: Called by run_irt_scoring_pipeline.R or standalone
Runtime: ~X seconds (to be determined)

Version: 1.0
Created: January 4, 2025
=============================================================================
"""

import duckdb
import pandas as pd
import os
import tempfile
from pathlib import Path

print("\n" + "=" * 70)
print("PSYCHOSOCIAL IRT SCORES - DATABASE INSERTION")
print("=" * 70)
print(f"Start time: {pd.Timestamp.now()}\n")

# =============================================================================
# CONFIGURATION
# =============================================================================

print("-" * 70)
print("STEP 1: CONFIGURATION")
print("-" * 70 + "\n")

# Database path
db_path = "data/duckdb/kidsights_local.duckdb"
if not os.path.exists(db_path):
    raise FileNotFoundError(f"Database not found: {db_path}")

print(f"[OK] Database: {db_path}")

# Table name
table_name = "ne25_irt_scores_psychosocial"
print(f"[OK] Target table: {table_name}")

# Feather files directory
temp_dir = Path(tempfile.gettempdir()) / "psychosocial_scores"
if not temp_dir.exists():
    raise FileNotFoundError(f"Feather files directory not found: {temp_dir}")

print(f"[OK] Input directory: {temp_dir}\n")

# =============================================================================
# CONNECT TO DATABASE
# =============================================================================

print("-" * 70)
print("STEP 2: CONNECT TO DATABASE")
print("-" * 70 + "\n")

conn = duckdb.connect(db_path)
print("[OK] Connected to database\n")

# =============================================================================
# CLEAR EXISTING DATA (if any)
# =============================================================================

print("-" * 70)
print("STEP 3: CLEAR EXISTING DATA")
print("-" * 70 + "\n")

# Check if table has existing data
count_query = f"SELECT COUNT(*) FROM {table_name}"
existing_count = conn.execute(count_query).fetchone()[0]

if existing_count > 0:
    print(f"[WARN] Table {table_name} contains {existing_count} existing rows")
    print("[INFO] Deleting existing data...")
    conn.execute(f"DELETE FROM {table_name}")
    print("[OK] Existing data cleared\n")
else:
    print(f"[OK] Table {table_name} is empty\n")

# =============================================================================
# INSERT SCORES FROM FEATHER FILES
# =============================================================================

print("=" * 70)
print("STEP 4: INSERT SCORES")
print("=" * 70 + "\n")

# Find all Feather files
feather_files = sorted(temp_dir.glob("psychosocial_scores_m*.feather"))

if len(feather_files) == 0:
    raise FileNotFoundError(f"No Feather files found in {temp_dir}")

print(f"Found {len(feather_files)} Feather files:\n")

# Expected factors (bifactor model)
factors = ['gen', 'eat', 'sle', 'soc', 'int', 'ext']

total_rows_inserted = 0

for feather_file in feather_files:
    print(f"Processing: {feather_file.name}")

    # Read Feather file
    df = pd.read_feather(feather_file)

    print(f"  Rows: {len(df)}")
    print(f"  Columns: {list(df.columns)}")

    # Validate required columns
    required_cols = ['study_id', 'pid', 'record_id', 'imputation_m']

    # Add factor columns (theta and SE for each factor)
    for factor in factors:
        required_cols.extend([f'theta_{factor}', f'se_{factor}'])

    missing_cols = set(required_cols) - set(df.columns)
    if missing_cols:
        raise ValueError(f"Missing columns: {missing_cols}")

    # Validate no NULL values in required columns
    null_counts = df[required_cols].isnull().sum()
    if null_counts.any():
        print(f"  [WARN] NULL values detected:")
        for col, count in null_counts[null_counts > 0].items():
            print(f"    {col}: {count} nulls")
        raise ValueError("NULL values found in required columns")

    # Validate theta and SE ranges for each factor
    print(f"  Factor score ranges:")
    for factor in factors:
        theta_col = f'theta_{factor}'
        se_col = f'se_{factor}'

        theta_min = df[theta_col].min()
        theta_max = df[theta_col].max()
        se_min = df[se_col].min()
        se_max = df[se_col].max()

        print(f"    {factor}: theta [{theta_min:.3f}, {theta_max:.3f}], SE [{se_min:.3f}, {se_max:.3f}]")

        # Check plausibility
        if theta_min < -5 or theta_max > 5:
            print(f"      [WARN] Theta values outside typical range [-4, 4]")

        if se_min <= 0:
            raise ValueError(f"SE values must be positive for {factor} (found min SE: {se_min})")

        if se_max > 3:
            print(f"      [WARN] Some SE values are quite large (max: {se_max})")

    # Insert into database
    conn.execute(f"""
        INSERT INTO {table_name}
        SELECT
            study_id,
            pid,
            record_id,
            imputation_m,
            theta_gen, se_gen,
            theta_eat, se_eat,
            theta_sle, se_sle,
            theta_soc, se_soc,
            theta_int, se_int,
            theta_ext, se_ext,
            CURRENT_TIMESTAMP as scoring_date,
            '1.0' as scoring_version
        FROM df
    """)

    rows_inserted = len(df)
    total_rows_inserted += rows_inserted

    print(f"  [OK] Inserted {rows_inserted} rows\n")

# =============================================================================
# VALIDATION
# =============================================================================

print("=" * 70)
print("STEP 5: VALIDATION")
print("=" * 70 + "\n")

# Count total rows in table
final_count = conn.execute(count_query).fetchone()[0]
print(f"Total rows in {table_name}: {final_count}")

# Verify count matches expected
if final_count != total_rows_inserted:
    raise ValueError(f"Row count mismatch! Expected {total_rows_inserted}, found {final_count}")

print(f"[OK] Row count verified: {total_rows_inserted} rows\n")

# Check distribution across imputations
dist_query = f"""
SELECT
    imputation_m,
    COUNT(*) as n_scores,
    AVG(theta_gen) as mean_theta_gen,
    STDDEV(theta_gen) as sd_theta_gen,
    AVG(se_gen) as mean_se_gen
FROM {table_name}
GROUP BY imputation_m
ORDER BY imputation_m
"""

print("Distribution across imputations (general factor):")
dist_df = conn.execute(dist_query).df()
print(dist_df.to_string(index=False))
print()

# Check for duplicate keys
dup_query = f"""
SELECT study_id, pid, record_id, imputation_m, COUNT(*) as n
FROM {table_name}
GROUP BY study_id, pid, record_id, imputation_m
HAVING COUNT(*) > 1
"""

duplicates = conn.execute(dup_query).fetchall()
if len(duplicates) > 0:
    raise ValueError(f"Duplicate primary keys found: {len(duplicates)} duplicates")

print("[OK] No duplicate primary keys\n")

# Factor correlation check (should be present but not perfect)
print("Inter-factor correlations (general with specific factors):")
corr_query = f"""
SELECT
    CORR(theta_gen, theta_eat) as corr_gen_eat,
    CORR(theta_gen, theta_sle) as corr_gen_sle,
    CORR(theta_gen, theta_soc) as corr_gen_soc,
    CORR(theta_gen, theta_int) as corr_gen_int,
    CORR(theta_gen, theta_ext) as corr_gen_ext
FROM {table_name}
"""
corr_df = conn.execute(corr_query).df()
print(corr_df.to_string(index=False))
print()

print("[INFO] Bifactor model correlations should be moderate (not 1.0)")
print("[INFO] Perfect correlation would indicate model identification issue\n")

# =============================================================================
# CLEANUP
# =============================================================================

conn.close()
print("[OK] Database connection closed\n")

# =============================================================================
# SUMMARY
# =============================================================================

print("=" * 70)
print("DATABASE INSERTION COMPLETE")
print("=" * 70 + "\n")

print("SUMMARY:")
print(f"  Table: {table_name}")
print(f"  Total rows inserted: {total_rows_inserted}")
print(f"  Imputations: {len(feather_files)}")
print(f"  Factors per record: {len(factors)} (gen + 5 specific)")
print(f"  Average scores per imputation: {total_rows_inserted / len(feather_files):.0f}")
print()

print(f"End time: {pd.Timestamp.now()}")
print("=" * 70 + "\n")
