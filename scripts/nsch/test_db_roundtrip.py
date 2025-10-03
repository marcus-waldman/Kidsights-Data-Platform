"""
Test NSCH Database Round-Trip

Verifies data integrity by comparing original Feather file with database query results.
Tests that no data loss or corruption occurred during insertion.

Usage:
    python scripts/nsch/test_db_roundtrip.py --year 2023
"""

import argparse
import pandas as pd
import duckdb
import numpy as np
from pathlib import Path


def parse_arguments():
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser(
        description="Test NSCH database round-trip data integrity"
    )

    parser.add_argument(
        "--year",
        type=int,
        default=2023,
        help="Survey year to test (default: 2023)"
    )

    parser.add_argument(
        "--database",
        type=str,
        default="data/duckdb/kidsights_local.duckdb",
        help="Database path"
    )

    return parser.parse_args()


def load_original_feather(year: int) -> pd.DataFrame:
    """Load original Feather file."""
    feather_path = Path(f"data/nsch/{year}/processed.feather")

    if not feather_path.exists():
        raise FileNotFoundError(f"Feather file not found: {feather_path}")

    print(f"[INFO] Loading original Feather: {feather_path}")
    df = pd.read_feather(feather_path)
    print(f"  Rows: {len(df):,}")
    print(f"  Columns: {len(df.columns)}")

    return df


def load_from_database(year: int, database_path: str) -> pd.DataFrame:
    """Load data from database."""
    table_name = f"nsch_{year}_raw"

    print(f"\n[INFO] Loading from database: {table_name}")
    conn = duckdb.connect(database_path)

    df = conn.execute(f"SELECT * FROM {table_name}").fetchdf()

    conn.close()

    print(f"  Rows: {len(df):,}")
    print(f"  Columns: {len(df.columns)}")

    return df


def compare_row_counts(df_original: pd.DataFrame, df_db: pd.DataFrame) -> bool:
    """Compare row counts."""
    print("\n[CHECK 1/6] Row count...")

    original_rows = len(df_original)
    db_rows = len(df_db)

    if original_rows == db_rows:
        print(f"  [PASS] Both have {original_rows:,} rows")
        return True
    else:
        print(f"  [FAIL] Original has {original_rows:,} rows, DB has {db_rows:,} rows")
        return False


def compare_column_counts(df_original: pd.DataFrame, df_db: pd.DataFrame) -> bool:
    """Compare column counts."""
    print("\n[CHECK 2/6] Column count...")

    original_cols = len(df_original.columns)
    db_cols = len(df_db.columns)

    if original_cols == db_cols:
        print(f"  [PASS] Both have {original_cols} columns")
        return True
    else:
        print(f"  [FAIL] Original has {original_cols} columns, DB has {db_cols} columns")
        return False


def compare_column_names(df_original: pd.DataFrame, df_db: pd.DataFrame) -> bool:
    """Compare column names."""
    print("\n[CHECK 3/6] Column names...")

    original_cols = set(df_original.columns)
    db_cols = set(df_db.columns)

    if original_cols == db_cols:
        print(f"  [PASS] Column names match")
        return True
    else:
        missing_in_db = original_cols - db_cols
        extra_in_db = db_cols - original_cols

        if missing_in_db:
            print(f"  [FAIL] Missing in DB: {list(missing_in_db)[:5]}")
        if extra_in_db:
            print(f"  [FAIL] Extra in DB: {list(extra_in_db)[:5]}")

        return False


def compare_sample_values(df_original: pd.DataFrame, df_db: pd.DataFrame) -> bool:
    """Compare sample values from random rows."""
    print("\n[CHECK 4/6] Sample values (10 random rows)...")

    # Reorder DB columns to match original
    df_db = df_db[df_original.columns]

    # Sample 10 random rows
    sample_size = min(10, len(df_original))
    sample_indices = np.random.choice(len(df_original), size=sample_size, replace=False)

    all_match = True

    for i, idx in enumerate(sample_indices):
        original_row = df_original.iloc[idx]
        db_row = df_db.iloc[idx]

        # Compare values (allowing for floating point precision differences)
        for col in df_original.columns:
            orig_val = original_row[col]
            db_val = db_row[col]

            # Handle NaN comparison
            if pd.isna(orig_val) and pd.isna(db_val):
                continue

            # Handle numeric comparison with tolerance
            if isinstance(orig_val, (int, float)) and isinstance(db_val, (int, float)):
                if not np.isclose(orig_val, db_val, rtol=1e-09, atol=0, equal_nan=True):
                    print(f"  [FAIL] Row {idx}, Column {col}: {orig_val} != {db_val}")
                    all_match = False
                    break
            else:
                if orig_val != db_val:
                    print(f"  [FAIL] Row {idx}, Column {col}: {orig_val} != {db_val}")
                    all_match = False
                    break

    if all_match:
        print(f"  [PASS] All {sample_size} sampled rows match")

    return all_match


def compare_null_counts(df_original: pd.DataFrame, df_db: pd.DataFrame) -> bool:
    """Compare null counts for first 10 columns."""
    print("\n[CHECK 5/6] Null counts (first 10 columns)...")

    # Reorder DB columns to match original
    df_db = df_db[df_original.columns]

    all_match = True

    for col in list(df_original.columns)[:10]:
        orig_nulls = df_original[col].isna().sum()
        db_nulls = df_db[col].isna().sum()

        if orig_nulls != db_nulls:
            print(f"  [FAIL] Column {col}: Original has {orig_nulls} nulls, DB has {db_nulls} nulls")
            all_match = False

    if all_match:
        print(f"  [PASS] Null counts match for first 10 columns")

    return all_match


def compare_summary_stats(df_original: pd.DataFrame, df_db: pd.DataFrame) -> bool:
    """Compare summary statistics for numeric columns."""
    print("\n[CHECK 6/6] Summary statistics (first 5 numeric columns)...")

    # Reorder DB columns to match original
    df_db = df_db[df_original.columns]

    # Get first 5 numeric columns
    numeric_cols = df_original.select_dtypes(include=[np.number]).columns[:5]

    all_match = True

    for col in numeric_cols:
        orig_mean = df_original[col].mean()
        db_mean = df_db[col].mean()

        orig_std = df_original[col].std()
        db_std = df_db[col].std()

        # Compare with tolerance
        if not np.isclose(orig_mean, db_mean, rtol=1e-09, atol=0, equal_nan=True):
            print(f"  [FAIL] Column {col} mean: {orig_mean} != {db_mean}")
            all_match = False

        if not np.isclose(orig_std, db_std, rtol=1e-09, atol=0, equal_nan=True):
            print(f"  [FAIL] Column {col} std: {orig_std} != {db_std}")
            all_match = False

    if all_match:
        print(f"  [PASS] Summary statistics match for first 5 numeric columns")

    return all_match


def main():
    """Main test function."""
    args = parse_arguments()

    print("=" * 70)
    print("NSCH DATABASE ROUND-TRIP TEST")
    print("=" * 70)
    print(f"Year: {args.year}")
    print(f"Database: {args.database}")

    try:
        # Load data
        df_original = load_original_feather(args.year)
        df_db = load_from_database(args.year, args.database)

        # Run checks
        checks = [
            compare_row_counts(df_original, df_db),
            compare_column_counts(df_original, df_db),
            compare_column_names(df_original, df_db),
            compare_sample_values(df_original, df_db),
            compare_null_counts(df_original, df_db),
            compare_summary_stats(df_original, df_db)
        ]

        # Summary
        print("\n" + "=" * 70)
        print("TEST SUMMARY")
        print("=" * 70)

        passed = sum(checks)
        total = len(checks)

        print(f"Checks passed: {passed}/{total}")

        if all(checks):
            print("\n[SUCCESS] All round-trip checks passed!")
            print("Data integrity verified - no data loss or corruption detected.")
            return 0
        else:
            print("\n[FAILURE] Some checks failed")
            print("Data may have been corrupted or modified during insertion.")
            return 1

    except Exception as e:
        print(f"\n[ERROR] {e}")
        import traceback
        traceback.print_exc()
        return 1


if __name__ == "__main__":
    import sys
    sys.exit(main())
